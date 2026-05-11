
using Colors

"""
    SparseMatrixCell{T}(; row, column, color, value=nothing)

A single cell in a sparse, reorderable matrix visualization.

# Fields
- `row::String`: row label
- `column::String`: column label
- `color::Colors.Colorant`: cell fill color
- `value::T`: optional datum shown on hover; defaults to `nothing`
"""
Base.@kwdef struct SparseMatrixCell{T}
    row::String
    column::String
    color::Colors.Colorant
    value::T = nothing
end

# Bridge constructor — accepts any NamedTuple with the required fields
# (plus optional `:value`); field order doesn't matter.
SparseMatrixCell(nt::NamedTuple) =
    SparseMatrixCell(nt.row, nt.column, nt.color, get(nt, :value, nothing))

"""
    SparseMatrixConfig

Styling configuration for a reorderable sparse matrix. Safe to share across
plots — carries no per-plot content (the title lives on `SparseMatrixSpec`).
"""
Base.@kwdef struct SparseMatrixConfig
    width::Int = 600
    height::Int = 600
    band_padding::Float64 = 0.05
    label_font_size::Int = 12
    label_gap::Int = 8
    title_color::String = "#005ca5"
    title_fontsize::Int = 24
    background::String = "#fafafa"
    default_color::Colors.Colorant = colorant"steelblue"
    hover_color::String = "#ffd54f"
    hover_opacity::Float64 = 0.25
    cell_stroke::String = "#ffffff"
    cell_stroke_width::Float64 = 1.0
    chart_padding::NamedTuple{(:top,:right,:bottom,:left),NTuple{4,Int}} =
        (top=80, right=20, bottom=20, left=120)
end

"""
    SparseMatrixSpec(cells::AbstractVector;
                     title="", row_order=String[], column_order=String[],
                     config=SparseMatrixConfig())

A reorderable sparse matrix. Each element of `cells` is either a
`SparseMatrixCell` or a `NamedTuple` carrying `row`, `column`, an optional
`color` (defaulting from `config.default_color`), and an optional `value`.

Rows and columns are derived from the cells in first-seen order; the
`row_order` / `column_order` kwargs place the listed names first (unknown
names are dropped) and the remaining data names follow in first-seen order.
"""
struct SparseMatrixSpec <: VegaVisualizerSpec
    cells::Vector{SparseMatrixCell}
    row_order::Vector{String}
    column_order::Vector{String}
    title::String
    config::SparseMatrixConfig
end

function SparseMatrixSpec(cells::AbstractVector;
                          title::AbstractString = "",
                          row_order::AbstractVector{<:AbstractString} = String[],
                          column_order::AbstractVector{<:AbstractString} = String[],
                          config::SparseMatrixConfig = SparseMatrixConfig())
    normalized = SparseMatrixCell[_normalize_cell(c, config) for c in cells]
    deduped = dedupe_cells(normalized)
    rows, cols = derive_orderings(deduped,
                                  String.(row_order),
                                  String.(column_order))
    return SparseMatrixSpec(deduped, rows, cols, String(title), config)
end

function _normalize_cell(c, config::SparseMatrixConfig)
    c isa SparseMatrixCell && return c
    if c isa NamedTuple
        hasrc = hasproperty(c, :row) && hasproperty(c, :column)
        hasrc || throw(ArgumentError(
            "SparseMatrixCell NamedTuple input requires :row and :column fields"))
        if hasproperty(c, :color)
            return SparseMatrixCell(c)
        else
            return SparseMatrixCell(merge(c, (color = config.default_color,)))
        end
    end
    throw(ArgumentError(
        "SparseMatrixSpec cell must be a SparseMatrixCell or NamedTuple with :row and :column"))
end


# =============================================================================
# Ordering resolution and dedupe
# =============================================================================

"""
    derive_orderings(cells, row_override, column_override)
        -> (rows::Vector{String}, cols::Vector{String})

Resolve row and column orderings using "override-first-then-append-in-
first-seen-order" semantics (override names absent from the data are dropped).
"""
function derive_orderings(cells::AbstractVector{<:SparseMatrixCell},
                          row_override::Vector{String},
                          column_override::Vector{String})
    rows_seen = String[]
    cols_seen = String[]
    rows_set = Set{String}()
    cols_set = Set{String}()
    for c in cells
        if !(c.row in rows_set)
            push!(rows_seen, c.row); push!(rows_set, c.row)
        end
        if !(c.column in cols_set)
            push!(cols_seen, c.column); push!(cols_set, c.column)
        end
    end
    return (_resolve_order(rows_seen, row_override),
            _resolve_order(cols_seen, column_override))
end

function _resolve_order(seen::Vector{String}, override::Vector{String})
    seen_set = Set(seen)
    ordered = String[]
    placed = Set{String}()
    for name in override
        if name in seen_set && !(name in placed)
            push!(ordered, name); push!(placed, name)
        end
    end
    for name in seen
        if !(name in placed)
            push!(ordered, name); push!(placed, name)
        end
    end
    return ordered
end

"""
    dedupe_cells(cells) -> Vector{SparseMatrixCell}

Collapse duplicate `(row, column)` entries with last-wins semantics. Emits a
`@warn` per duplicate key.
"""
function dedupe_cells(cells::AbstractVector{<:SparseMatrixCell})
    seen = Dict{Tuple{String,String},Int}()
    kept = SparseMatrixCell[]
    for c in cells
        key = (c.row, c.column)
        if haskey(seen, key)
            @warn "Duplicate (row, column) cell — last occurrence wins" row=c.row column=c.column
            kept[seen[key]] = c
        else
            push!(kept, c)
            seen[key] = length(kept)
        end
    end
    return kept
end


# =============================================================================
# Vega spec generation
# =============================================================================

"""
    cell_to_hex_dict(cell::SparseMatrixCell) -> Dict{String,Any}

Serialize a cell to a plain dict for Vega. The `"value"` key is omitted when
the value is `nothing`, `missing`, or a `NaN` float — matching the tooltip
signal's null-suppression.
"""
function cell_to_hex_dict(cell::SparseMatrixCell)
    d = Dict{String,Any}(
        "row" => cell.row,
        "column" => cell.column,
        "color" => "#" * Colors.hex(cell.color),
    )
    v = cell.value
    omit = v === nothing || v === missing ||
           (v isa AbstractFloat && isnan(v))
    omit || (d["value"] = v)
    return d
end

function vega_spec(spec::SparseMatrixSpec)
    config = spec.config
    cells_data = [cell_to_hex_dict(c) for c in spec.cells]

    Dict{String,Any}(
        "\$schema" => "https://vega.github.io/schema/vega/v5.json",
        "description" => "Reorderable Sparse Matrix",
        "width" => config.width,
        "height" => config.height,
        "padding" => Dict(
            "top" => config.chart_padding.top,
            "right" => config.chart_padding.right,
            "bottom" => config.chart_padding.bottom,
            "left" => config.chart_padding.left,
        ),
        "title" => Dict(
            "text" => spec.title,
            "color" => config.title_color,
            "fontSize" => config.title_fontsize,
            "fontWeight" => "bold",
            "offset" => 30,
        ),
        "background" => config.background,
        "signals" => generate_signals(),
        "data" => generate_data_transforms(cells_data, spec.row_order, spec.column_order),
        "scales" => generate_scales(config),
        "marks" => generate_marks(config),
        "config" => Dict(
            "view" => Dict("stroke" => "transparent"),
            "text" => Dict("fontSize" => config.label_font_size, "fill" => "#333333"),
        ),
    )
end

function generate_signals()
    [
        Dict{String,Any}(
            "name" => "rowSrc", "value" => nothing,
            "on" => [
                Dict("events" => "@rowLabels:mousedown", "update" => "datum"),
                Dict("events" => "@rowLabels:mouseover",
                     "update" => "rowSrc ? datum : rowSrc"),
                Dict("events" => "window:mouseup", "update" => "null"),
            ],
        ),
        Dict{String,Any}(
            "name" => "rowDest", "value" => nothing,
            "on" => [
                Dict("events" => "@rowLabels:mouseover",
                     "update" => "rowSrc ? datum : null"),
                Dict("events" => "window:mouseup", "update" => "null"),
            ],
        ),
        Dict{String,Any}(
            "name" => "rowActive", "value" => nothing,
            "on" => [
                Dict("events" => "@rowLabels:mouseover", "update" => "datum.name"),
                Dict("events" => "@rowLabels:mouseout",  "update" => "null"),
                Dict("events" => "@cells:mouseover",     "update" => "datum.row"),
                Dict("events" => "@cells:mouseout",      "update" => "null"),
            ],
        ),
        Dict{String,Any}(
            "name" => "colSrc", "value" => nothing,
            "on" => [
                Dict("events" => "@colLabels:mousedown", "update" => "datum"),
                Dict("events" => "@colLabels:mouseover",
                     "update" => "colSrc ? datum : colSrc"),
                Dict("events" => "window:mouseup", "update" => "null"),
            ],
        ),
        Dict{String,Any}(
            "name" => "colDest", "value" => nothing,
            "on" => [
                Dict("events" => "@colLabels:mouseover",
                     "update" => "colSrc ? datum : null"),
                Dict("events" => "window:mouseup", "update" => "null"),
            ],
        ),
        Dict{String,Any}(
            "name" => "colActive", "value" => nothing,
            "on" => [
                Dict("events" => "@colLabels:mouseover", "update" => "datum.name"),
                Dict("events" => "@colLabels:mouseout",  "update" => "null"),
                Dict("events" => "@cells:mouseover",     "update" => "datum.column"),
                Dict("events" => "@cells:mouseout",      "update" => "null"),
            ],
        ),
        Dict{String,Any}(
            "name" => "anyDragging",
            "update" => "rowSrc != null || colSrc != null",
        ),
    ]
end

function generate_data_transforms(cells_data::Vector,
                                  rows::Vector{String},
                                  cols::Vector{String})
    row_values = [Dict{String,Any}("name" => name, "i" => i - 1)
                  for (i, name) in enumerate(rows)]
    col_values = [Dict{String,Any}("name" => name, "i" => i - 1)
                  for (i, name) in enumerate(cols)]
    [
        Dict{String,Any}("name" => "cellData", "values" => cells_data),
        Dict{String,Any}(
            "name" => "rowIndex",
            "values" => row_values,
            "on" => [
                Dict("trigger" => "rowSrc && rowDest && rowSrc.name != rowDest.name",
                     "modify" => "rowSrc",  "values" => "{i: rowDest.i}"),
                Dict("trigger" => "rowSrc && rowDest && rowSrc.name != rowDest.name",
                     "modify" => "rowDest", "values" => "{i: rowSrc.i}"),
            ],
        ),
        Dict{String,Any}(
            "name" => "colIndex",
            "values" => col_values,
            "on" => [
                Dict("trigger" => "colSrc && colDest && colSrc.name != colDest.name",
                     "modify" => "colSrc",  "values" => "{i: colDest.i}"),
                Dict("trigger" => "colSrc && colDest && colSrc.name != colDest.name",
                     "modify" => "colDest", "values" => "{i: colSrc.i}"),
            ],
        ),
    ]
end

function generate_scales(config::SparseMatrixConfig)
    [
        Dict{String,Any}(
            "name" => "xScale", "type" => "band", "range" => "width",
            "domain" => Dict("data" => "colIndex", "field" => "name",
                             "sort" => Dict("field" => "i", "order" => "ascending")),
            "paddingInner" => config.band_padding,
        ),
        Dict{String,Any}(
            "name" => "yScale", "type" => "band", "range" => "height",
            "domain" => Dict("data" => "rowIndex", "field" => "name",
                             "sort" => Dict("field" => "i", "order" => "ascending")),
            "paddingInner" => config.band_padding,
        ),
    ]
end

function generate_marks(config::SparseMatrixConfig)
    [
        # Row hover bar
        Dict{String,Any}(
            "type" => "rect",
            "interactive" => false,
            "encode" => Dict(
                "update" => Dict(
                    "x" => Dict("value" => 0),
                    "width" => Dict("signal" => "width"),
                    "y" => Dict("signal" =>
                        "rowActive != null ? scale('yScale', rowActive) : 0"),
                    "height" => Dict("signal" => "bandwidth('yScale')"),
                    "fill" => Dict("value" => config.hover_color),
                    "fillOpacity" => Dict("signal" =>
                        "rowActive != null ? $(config.hover_opacity) : 0"),
                ),
            ),
        ),
        # Column hover bar
        Dict{String,Any}(
            "type" => "rect",
            "interactive" => false,
            "encode" => Dict(
                "update" => Dict(
                    "x" => Dict("signal" =>
                        "colActive != null ? scale('xScale', colActive) : 0"),
                    "width" => Dict("signal" => "bandwidth('xScale')"),
                    "y" => Dict("value" => 0),
                    "height" => Dict("signal" => "height"),
                    "fill" => Dict("value" => config.hover_color),
                    "fillOpacity" => Dict("signal" =>
                        "colActive != null ? $(config.hover_opacity) : 0"),
                ),
            ),
        ),
        # Cells
        Dict{String,Any}(
            "type" => "rect",
            "name" => "cells",
            "from" => Dict("data" => "cellData"),
            "encode" => Dict(
                "update" => Dict(
                    "x" => Dict("scale" => "xScale", "field" => "column"),
                    "y" => Dict("scale" => "yScale", "field" => "row"),
                    "width" => Dict("signal" => "bandwidth('xScale')"),
                    "height" => Dict("signal" => "bandwidth('yScale')"),
                    "fill" => Dict("field" => "color"),
                    "stroke" => Dict("value" => config.cell_stroke),
                    "strokeWidth" => Dict("value" => config.cell_stroke_width),
                    "fillOpacity" => Dict("signal" =>
                        "indata('rowIndex','name',datum.row) && indata('colIndex','name',datum.column) ? 1 : 0"),
                    "tooltip" => Dict("signal" =>
                        "!anyDragging && datum.value != null ? datum.value : null"),
                ),
            ),
        ),
        # Row labels
        Dict{String,Any}(
            "type" => "text",
            "name" => "rowLabels",
            "from" => Dict("data" => "rowIndex"),
            "encode" => Dict(
                "update" => Dict(
                    "x" => Dict("value" => -config.label_gap),
                    "y" => Dict("scale" => "yScale", "field" => "name",
                                "band" => 0.5),
                    "text" => Dict("field" => "name"),
                    "align" => Dict("value" => "right"),
                    "baseline" => Dict("value" => "middle"),
                    "fontSize" => Dict("value" => config.label_font_size),
                    "cursor" => Dict("signal" =>
                        "anyDragging ? 'grabbing' : 'grab'"),
                ),
            ),
        ),
        # Column labels
        Dict{String,Any}(
            "type" => "text",
            "name" => "colLabels",
            "from" => Dict("data" => "colIndex"),
            "encode" => Dict(
                "update" => Dict(
                    "x" => Dict("scale" => "xScale", "field" => "name",
                                "band" => 0.5),
                    "y" => Dict("value" => -config.label_gap),
                    "text" => Dict("field" => "name"),
                    "angle" => Dict("value" => -90),
                    "align" => Dict("value" => "left"),
                    "baseline" => Dict("value" => "middle"),
                    "fontSize" => Dict("value" => config.label_font_size),
                    "cursor" => Dict("signal" =>
                        "anyDragging ? 'grabbing' : 'grab'"),
                ),
            ),
        ),
    ]
end
