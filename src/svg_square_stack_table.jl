# SquareStackTable — direct-SVG table plot.
#
# See docs/square_stack_table_design.md for the design rationale and the
# layout algorithm. Types and functions are added here in TDD cycles.

"""
    SquareStackTableRow(label, squares; extras=Any[])

One row of a SquareStackTable.

- `label::String` — right-aligned text in column 1.
- `squares::Vector{String}` — one entry per square, value = category name.
  Order is rendered left-to-right.
- `extras::Vector{Any}` — optional trailing column values (strings or
  numbers). Rows may have fewer extras than the spec declares; missing
  cells render blank.
"""
struct SquareStackTableRow
    label::String
    squares::Vector{String}
    extras::Vector{Any}
end

SquareStackTableRow(label::AbstractString, squares::AbstractVector; extras=Any[]) =
    SquareStackTableRow(String(label), String[String(s) for s in squares], Vector{Any}(extras))

"""
    SquareStackTableColumn(header, align; font_family=nothing, char_width_ratio=nothing)

Describes one of the optional extra columns (those after the label and
square-histogram columns).

- `header::String` — column header text. Empty strings are allowed and
  render as a blank header cell when `config.show_header` is true.
- `align::Symbol` — `:left`, `:right`, or `:center`. Numeric columns
  should generally be `:right`.
- `font_family::Union{String,Nothing}` — optional per-column font
  override. `nothing` inherits `config.font_family` (monospace by
  default).
- `char_width_ratio::Union{Float64,Nothing}` — optional per-column
  char-width-to-font-size ratio used for layout math. `nothing` inherits
  `config.char_width_ratio`. Override when switching a column to a
  proportional font (the default `0.6` is monospace-tuned).
"""
struct SquareStackTableColumn
    header::String
    align::Symbol
    font_family::Union{String,Nothing}
    char_width_ratio::Union{Float64,Nothing}
end

SquareStackTableColumn(header::AbstractString, align::Symbol;
                       font_family=nothing, char_width_ratio=nothing) =
    SquareStackTableColumn(String(header), align, font_family, char_width_ratio)

"""
    SquareStackTableConfig(; kwargs...)

Styling and layout configuration for a `SquareStackTableSpec`. Safe to share
across multiple plots — contains no per-plot content (the chart title and
data live on the `SquareStackTableSpec`).
"""
Base.@kwdef struct SquareStackTableConfig
    # Typography — monospace is load-bearing for layout math.
    font_family::String = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
    font_size::Int = 14
    # Approx char width as a fraction of font_size. 0.6 is safe for the
    # monospace fonts above. Override per column when switching to a
    # proportional font.
    char_width_ratio::Float64 = 0.6

    # Row & square geometry. square_gap is non-zero so readers can count
    # individual squares easily.
    row_height::Int  = 22
    square_size::Int = 14
    square_gap::Int  = 4
    column_gap::Int  = 20

    # Chrome
    padding::NamedTuple{(:top, :right, :bottom, :left),NTuple{4,Int}} =
        (top=20, right=20, bottom=20, left=20)
    background::String   = "#ffffff"
    text_color::String   = "#222222"
    header_color::String = "#555555"
    show_header::Bool    = true
    title_fontsize::Int  = 20
    title_color::String  = "#222222"

    # Legend
    show_legend::Bool         = true
    legend_swatch_size::Int   = 14
    legend_row_height::Int    = 20
    legend_gap::Int           = 8   # gap between swatch and label text
    legend_bottom_margin::Int = 12  # space between legend and header row

    # Default color palette for auto-assigned categories.
    palette::Vector{String} = [
        "#4e79a7", "#f28e2b", "#e15759", "#76b7b2", "#59a14f",
        "#edc949", "#af7aa1", "#ff9da7", "#9c755f", "#bab0ab",
    ]
end

"""
    SquareStackTableSpec(rows; title="", label_header="", histogram_header="",
                         columns=SquareStackTableColumn[],
                         category_colors=Dict{String,String}(),
                         legend_order=String[],
                         label_font_family=nothing,
                         config=SquareStackTableConfig())

A complete SquareStackTable plot. Pass to `svg`, `html`, or `open_in_browser`
to render.

- `rows` — the data, in display order (top to bottom).
- `label_header` — header text for the label column.
- `histogram_header` — header text for the square-histogram column.
- `columns` — schema for the extra columns (after label and histogram).
- `category_colors` — explicit category→hex overrides. Categories not
  listed are assigned from `config.palette` in first-seen order.
  Entries that don't correspond to any category in the data are ignored.
- `legend_order` — optional explicit category order for the legend.
  Categories present in the data but missing from this list are appended
  in first-seen order. Entries not in the data are dropped.
- `label_font_family` — optional override for the label column's font.
- `title` — optional chart title rendered above the legend.
"""
struct SquareStackTableSpec <: SVGVisualizerSpec
    rows::Vector{SquareStackTableRow}
    label_header::String
    histogram_header::String
    columns::Vector{SquareStackTableColumn}
    category_colors::Dict{String,String}
    legend_order::Vector{String}
    label_font_family::Union{String,Nothing}
    title::String
    config::SquareStackTableConfig
end

SquareStackTableSpec(rows::AbstractVector{SquareStackTableRow};
                     title::AbstractString="",
                     label_header::AbstractString="",
                     histogram_header::AbstractString="",
                     columns::AbstractVector{SquareStackTableColumn}=SquareStackTableColumn[],
                     category_colors::AbstractDict=Dict{String,String}(),
                     legend_order::AbstractVector=String[],
                     label_font_family::Union{AbstractString,Nothing}=nothing,
                     config::SquareStackTableConfig=SquareStackTableConfig()) =
    SquareStackTableSpec(
        rows,
        String(label_header),
        String(histogram_header),
        collect(SquareStackTableColumn, columns),
        Dict{String,String}(String(k) => String(v) for (k, v) in category_colors),
        String[String(c) for c in legend_order],
        isnothing(label_font_family) ? nothing : String(label_font_family),
        String(title),
        config,
    )

# =============================================================================
# Layout pre-pass: colors and legend order
# =============================================================================

"""
    distinct_categories(rows) -> Vector{String}

Return the distinct category names appearing in `rows`, in first-seen order
(top-to-bottom, left-to-right).
"""
function distinct_categories(rows::AbstractVector{SquareStackTableRow})
    seen = String[]
    seen_set = Set{String}()
    for row in rows
        for cat in row.squares
            if !(cat in seen_set)
                push!(seen, cat)
                push!(seen_set, cat)
            end
        end
    end
    return seen
end

"""
    resolve_colors(spec::SquareStackTableSpec) -> Dict{String,String}

Build a `category → hex color` mapping for every distinct category that
appears in `spec.rows`. Explicit `spec.category_colors` overrides win;
otherwise the category's first-seen-order index `i` is mapped through
`config.palette[mod1(i, length(palette))]`. Override entries that don't
correspond to any category in the data are ignored.
"""
function resolve_colors(spec::SquareStackTableSpec)
    palette = spec.config.palette
    overrides = spec.category_colors
    colors = Dict{String,String}()
    for (i, cat) in enumerate(distinct_categories(spec.rows))
        colors[cat] = haskey(overrides, cat) ? overrides[cat] :
                      palette[mod1(i, length(palette))]
    end
    return colors
end

"""
    resolve_legend_order(spec::SquareStackTableSpec) -> Vector{String}

Build the ordered list of categories shown in the legend.

- Start with `spec.legend_order`, dropping entries that don't appear in
  the data.
- Append the remaining data categories in first-seen order.
"""
function resolve_legend_order(spec::SquareStackTableSpec)
    seen = distinct_categories(spec.rows)
    seen_set = Set(seen)
    ordered = String[]
    placed = Set{String}()
    for cat in spec.legend_order
        if cat in seen_set && !(cat in placed)
            push!(ordered, cat)
            push!(placed, cat)
        end
    end
    for cat in seen
        if !(cat in placed)
            push!(ordered, cat)
            push!(placed, cat)
        end
    end
    return ordered
end

# =============================================================================
# Layout pre-pass: column widths
# =============================================================================

# Render the kth extras cell of `row` as a string. Rows shorter than the
# spec's column count produce empty cells.
function _extras_cell_str(row::SquareStackTableRow, k::Int)
    k <= length(row.extras) ? string(row.extras[k]) : ""
end

"""
    compute_column_widths(spec::SquareStackTableSpec)
        -> (label_w::Int, squares_w::Int, extras_w::Vector{Int})

Compute the pixel widths of every data column. All widths are integers
(rounded up via `ceil`) so downstream layout math stays in integer
arithmetic — that's what makes the byte-for-byte regression test stable
across platforms.

When `config.show_header` is false, header text is excluded from the
max-width calculation entirely (it isn't drawn, so it shouldn't inflate
column widths).
"""
function compute_column_widths(spec::SquareStackTableSpec)
    config = spec.config
    rows = spec.rows
    show_header = config.show_header

    cw_default = config.font_size * config.char_width_ratio
    cw_label = cw_default

    hlen(s) = show_header ? length(s) : 0

    label_content = maximum((length(r.label) for r in rows); init=0)
    label_w = ceil(Int, max(hlen(spec.label_header), label_content) * cw_label)

    squares_content = maximum((length(r.squares) for r in rows); init=0)
    squares_w_from_data = squares_content == 0 ? 0 :
        squares_content * (config.square_size + config.square_gap) - config.square_gap
    squares_w_from_header = ceil(Int, hlen(spec.histogram_header) * cw_default)
    squares_w = max(squares_w_from_header, squares_w_from_data)

    extras_w = Int[]
    for (k, col) in enumerate(spec.columns)
        cw = config.font_size * something(col.char_width_ratio, config.char_width_ratio)
        content_max = maximum((length(_extras_cell_str(r, k)) for r in rows); init=0)
        push!(extras_w, ceil(Int, max(hlen(col.header), content_max) * cw))
    end

    return (label_w=label_w, squares_w=squares_w, extras_w=extras_w)
end

# =============================================================================
# Layout pre-pass: full geometry
# =============================================================================

"""
    compute_layout(spec::SquareStackTableSpec) -> NamedTuple

Compute the full pixel-level layout of a `SquareStackTableSpec`. Returns a
NamedTuple containing precomputed widths, legend dimensions, column
origins, and the vertical band positions used by the SVG emit pass.

Empty extras columns (zero width) are dropped — they consume neither
horizontal space nor a `column_gap`. The legend block is also dropped
(`legend_w == legend_h == 0`) when `config.show_legend` is false or no
categories appear in the data.
"""
function compute_layout(spec::SquareStackTableSpec)
    config = spec.config
    widths = compute_column_widths(spec)
    legend_entries = resolve_legend_order(spec)

    cw_default = config.font_size * config.char_width_ratio

    # ---- Legend dimensions ----
    show_legend = config.show_legend && !isempty(legend_entries)
    if show_legend
        legend_label_w = ceil(Int, maximum(length(c) for c in legend_entries) * cw_default)
        legend_w = config.legend_swatch_size + config.legend_gap + legend_label_w
        legend_h = length(legend_entries) * config.legend_row_height + config.legend_bottom_margin
    else
        legend_w = 0
        legend_h = 0
    end

    # ---- Horizontal column origins ----
    x0 = config.padding.left
    label_x = x0 + widths.label_w
    hist_x = label_x + config.column_gap
    cursor = hist_x + widths.squares_w

    extras_left  = Dict{Int,Int}()
    extras_right = Dict{Int,Int}()
    for k in 1:length(spec.columns)
        widths.extras_w[k] == 0 && continue
        cursor += config.column_gap
        extras_left[k]  = cursor
        cursor += widths.extras_w[k]
        extras_right[k] = cursor
    end
    table_right = cursor
    total_width = max(table_right, x0 + legend_w) + config.padding.right

    # ---- Vertical band layout ----
    title_h    = isempty(spec.title) ? 0 : config.title_fontsize + 10
    legend_y0  = config.padding.top + title_h
    header_y   = legend_y0 + legend_h
    header_h   = config.show_header ? config.row_height : 0
    y0         = header_y + header_h
    total_height = y0 + length(spec.rows) * config.row_height + config.padding.bottom

    return (
        widths        = widths,
        legend_entries = legend_entries,
        legend_w      = legend_w,
        legend_h      = legend_h,
        x0            = x0,
        label_x       = label_x,
        hist_x        = hist_x,
        extras_left   = extras_left,
        extras_right  = extras_right,
        table_right   = table_right,
        total_width   = total_width,
        title_h       = title_h,
        legend_y0     = legend_y0,
        header_y      = header_y,
        header_h      = header_h,
        y0            = y0,
        total_height  = total_height,
    )
end

# =============================================================================
# SVG emit
# =============================================================================

# Per-alignment text-anchor SVG attribute value.
function _text_anchor(align::Symbol)
    align === :left   && return "start"
    align === :right  && return "end"
    align === :center && return "middle"
    error("SquareStackTableColumn align must be :left, :right, or :center; got $(align)")
end

# Per-alignment x coordinate for the kth extras column, computed from
# precomputed left/right edges in the layout.
function _extras_anchor_x(L, k::Int, align::Symbol)
    align === :left   && return L.extras_left[k]
    align === :right  && return L.extras_right[k]
    align === :center && return (L.extras_left[k] + L.extras_right[k]) ÷ 2
    error("SquareStackTableColumn align must be :left, :right, or :center; got $(align)")
end

# Effective font family for the label column.
_label_font(spec::SquareStackTableSpec) =
    something(spec.label_font_family, spec.config.font_family)

# Effective font family for an extras column.
_column_font(spec::SquareStackTableSpec, col::SquareStackTableColumn) =
    something(col.font_family, spec.config.font_family)

# Emit one <text> element with the given attributes and (escaped) content.
function _text!(io::IO, x::Int, y::Int, content::AbstractString;
                font_family::AbstractString,
                font_size::Int,
                fill::AbstractString,
                text_anchor::AbstractString)
    print(io, "  <text x=\"", x,
              "\" y=\"", y,
              "\" font-family=\"", escape_xml(font_family),
              "\" font-size=\"", font_size,
              "\" fill=\"", fill,
              "\" text-anchor=\"", text_anchor,
              "\" dominant-baseline=\"central\">",
              escape_xml(content),
              "</text>\n")
end

page_title(spec::SquareStackTableSpec) = spec.title

"""
    sort_squares_for_render(squares, legend_order) -> Vector{String}

Reorder a row's `squares` so that all squares of the same category are
contiguous, with categories themselves laid out in `legend_order`. The
input `squares` vector is treated as a multiset; the output has the
same length and same per-category counts. Used by the SVG emit pass to
group similar colors together within each row.
"""
function sort_squares_for_render(squares::AbstractVector{<:AbstractString},
                                 legend_order::AbstractVector{<:AbstractString})
    isempty(squares) && return String[]
    counts = Dict{String,Int}()
    for s in squares
        counts[s] = get(counts, s, 0) + 1
    end
    out = String[]
    for cat in legend_order
        n = get(counts, cat, 0)
        for _ in 1:n
            push!(out, cat)
        end
    end
    return out
end

"""
    svg(spec::SquareStackTableSpec) -> String

Render `spec` to a self-contained SVG document. All layout math is
integer-based, so output is byte-stable across platforms.
"""
function svg(spec::SquareStackTableSpec)
    config = spec.config
    L      = compute_layout(spec)
    colors = resolve_colors(spec)

    io = IOBuffer()

    # ---- Document framing ----
    print(io, "<svg xmlns=\"http://www.w3.org/2000/svg\" ",
              "width=\"", L.total_width,
              "\" height=\"", L.total_height,
              "\" viewBox=\"0 0 ", L.total_width, " ", L.total_height, "\">\n")
    print(io, "  <rect width=\"100%\" height=\"100%\" fill=\"",
              config.background, "\"/>\n")

    # ---- Title ----
    if !isempty(spec.title)
        # Place baseline so the visible top of the text is roughly at
        # padding.top. Title sits inside [padding.top, padding.top + title_h].
        title_y = config.padding.top + config.title_fontsize
        print(io, "  <text x=\"", L.x0,
                  "\" y=\"", title_y,
                  "\" font-family=\"", escape_xml(config.font_family),
                  "\" font-size=\"", config.title_fontsize,
                  "\" fill=\"", config.title_color,
                  "\" text-anchor=\"start\">",
                  escape_xml(spec.title),
                  "</text>\n")
    end

    # ---- Legend ----
    if config.show_legend && !isempty(L.legend_entries)
        sw = config.legend_swatch_size
        for (i, cat) in enumerate(L.legend_entries)
            entry_y = L.legend_y0 + (i - 1) * config.legend_row_height
            print(io, "  <rect x=\"", L.x0,
                      "\" y=\"", entry_y,
                      "\" width=\"", sw,
                      "\" height=\"", sw,
                      "\" fill=\"", colors[cat], "\"/>\n")
            _text!(io,
                L.x0 + sw + config.legend_gap,
                entry_y + sw ÷ 2,
                cat;
                font_family = config.font_family,
                font_size   = config.font_size,
                fill        = config.text_color,
                text_anchor = "start")
        end
    end

    # ---- Header row ----
    if config.show_header
        header_text_y = L.header_y + config.row_height ÷ 2

        if !isempty(spec.label_header)
            _text!(io, L.label_x, header_text_y, spec.label_header;
                font_family = _label_font(spec),
                font_size   = config.font_size,
                fill        = config.header_color,
                text_anchor = "end")
        end

        if !isempty(spec.histogram_header)
            _text!(io, L.hist_x, header_text_y, spec.histogram_header;
                font_family = config.font_family,
                font_size   = config.font_size,
                fill        = config.header_color,
                text_anchor = "start")
        end

        for (k, col) in enumerate(spec.columns)
            haskey(L.extras_left, k) || continue
            isempty(col.header) && continue
            _text!(io,
                _extras_anchor_x(L, k, col.align),
                header_text_y,
                col.header;
                font_family = _column_font(spec, col),
                font_size   = config.font_size,
                fill        = config.header_color,
                text_anchor = _text_anchor(col.align))
        end
    end

    # ---- Data rows ----
    for (i, row) in enumerate(spec.rows)
        row_top = L.y0 + (i - 1) * config.row_height
        text_y  = row_top + config.row_height ÷ 2
        sq_y    = row_top + (config.row_height - config.square_size) ÷ 2

        # Label
        _text!(io, L.label_x, text_y, row.label;
            font_family = _label_font(spec),
            font_size   = config.font_size,
            fill        = config.text_color,
            text_anchor = "end")

        # Squares — grouped by category in legend order so similar
        # colors land next to each other.
        for (j, cat) in enumerate(sort_squares_for_render(row.squares, L.legend_entries))
            sx = L.hist_x + (j - 1) * (config.square_size + config.square_gap)
            print(io, "  <rect x=\"", sx,
                      "\" y=\"", sq_y,
                      "\" width=\"", config.square_size,
                      "\" height=\"", config.square_size,
                      "\" fill=\"", colors[cat], "\"/>\n")
        end

        # Extras cells
        for (k, col) in enumerate(spec.columns)
            haskey(L.extras_left, k) || continue
            cell = _extras_cell_str(row, k)
            isempty(cell) && continue
            _text!(io,
                _extras_anchor_x(L, k, col.align),
                text_y,
                cell;
                font_family = _column_font(spec, col),
                font_size   = config.font_size,
                fill        = config.text_color,
                text_anchor = _text_anchor(col.align))
        end
    end

    print(io, "</svg>\n")
    return String(take!(io))
end
