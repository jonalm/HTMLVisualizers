# SquareStackTable — design doc

## What we're building

A table-shaped plot with:

1. A **label column**: right-aligned text (one line per row).
2. A **square-histogram column**: per row, a horizontal run of unit-sized
   squares. Each square is colored by a *category*, so a row's histogram is
   really "how many of each category does this row have", rendered one
   square at a time. Squares are **grouped by category** within the row
   (similar colors next to each other), in legend order — input order
   in `row.squares` is treated as a multiset, not a sequence.
3. Zero or more **extra columns**: free-form text or numeric cells,
   per-column alignment.

All columns share a **header row** above the data rows. Above the header
row sits a **color legend** — one entry per category that appears in the
data, each showing the swatch color and the category name — so readers
can decode the histogram without guessing.

ASCII reference from the request:

```
  foo | █ █ █ █ █        | 31   |
  bar | █ █ █ █ █ █ █ █  | 211  | comment here bla bla
  baz | █ █              | 32   |
bamma | █                | 53   |
```

Export targets: self-contained **HTML** (same as the Sankey spec) and
standalone **SVG**.

---

## Renderer evaluation: Vega vs HTML vs direct SVG

Three candidate backends. The question the user raised is whether Vega
is a good fit here, since it's the only existing path that already has
SVG export wired up.

### Option A — Vega

**Can it do it?** Yes, with effort.

Sketch: one datum per row, with a `squares` field. A `flatten` / `sequence`
transform expands each row into one datum per square, tagged with category
and square-index. Square marks are placed at
`x = histogram_col_x + i * (sq_size + sq_gap)`,
`y = row_y(row_index)`, fill-by-category. Label and numeric columns are
separate `text` mark sets with hard-coded pixel offsets.

**Downsides:**

- **Scales don't help.** The layout is a grid of fixed pixel cells, not a
  data-driven coordinate system. Every column's position has to be
  pre-computed in Julia and injected as signal constants — Vega's main
  value add (declarative scales) is essentially unused.
- **Unit-square histograms are non-idiomatic.** Vega prefers `rect` marks
  with `y` and `y2` for stacked bars. Getting one discrete square per
  unit requires a flatten transform and manual positioning. Workable,
  but every feature request ("category legend on the right", "row
  hover", "cell borders") fights the framework.
- **Heterogeneous columns are painful.** Label text, squares, and numeric
  text are three mark types that need to share vertical alignment per
  row. Doable with groups, but fiddly.
- **We'd inherit all of Vega's runtime cost** (vega-embed JS in HTML,
  `vg2svg` for SVG) for a plot that doesn't need it.

**Upside:** SVG export already works via the existing
`svg(::VegaVisualizerSpec)` that pipes `vg2svg`.

### Option B — Vanilla HTML `<table>`

**Can it do it?** Yes, and very naturally. `<td>` cells hold text; the
histogram cell holds a row of colored `<span>`s or inline SVG rects.

**Downside that kills it:** SVG export. Converting HTML tables to SVG
needs a headless browser (Puppeteer, wkhtmltopdf, etc.) — a huge new
dependency for a single feature. The user explicitly said they want SVG
export, and the whole point of this spec is that "currently only Vega
supports SVG; maybe we could use SVG directly".

We could do HTML for `html()` and *something else* for `svg()`, but
maintaining two independent layout implementations for the same plot is
a trap.

### Option C — Direct SVG (recommended)

Generate an SVG document in Julia by string-concatenating `<rect>` and
`<text>` elements at deterministically computed pixel coordinates. Wrap
that SVG in a minimal HTML shell for `html()`.

**Why this wins:**

- **The layout is already a grid of known-size cells.** There's no real
  coordinate-space math, no scales, no interactive pan/zoom — just "put
  text here, put rects there". SVG is the right level of abstraction.
- **One implementation serves both outputs.** `svg()` returns the SVG
  string; `html()` embeds the same SVG inline. No vega-embed runtime,
  no `vg2svg` dependency for SquareStackTable.
- **No runtime text measurement needed.** By standardizing on a
  monospace font for the label and numeric columns, character widths
  become predictable (`~0.6 * font_size`). Column widths are computed
  from max character counts. The comment/free-text column is rightmost
  and unbounded, so it can overflow without affecting layout.
- **Extensible.** Per-category colors, per-row styling, legend, title,
  and hover tooltips are all trivial SVG primitives.

**Cost:** introduces a second rendering pipeline alongside the Vega one.
That's fine — the abstract type hierarchy already anticipates this
(`HTMLVisualizerSpec` is the root; `VegaVisualizerSpec` is *one* branch).
We add a sibling branch for SVG-based specs.

### Decision

**Go with Option C (direct SVG).** Introduce an `SVGVisualizerSpec`
abstract type parallel to `VegaVisualizerSpec`. `SquareStackTableSpec` is the
first concrete subtype.

---

## Fit with the existing type hierarchy

Current state ([src/HTMLVisualizers.jl:12-13](../src/HTMLVisualizers.jl#L12-L13)):

```julia
abstract type HTMLVisualizerSpec end
abstract type VegaVisualizerSpec <: HTMLVisualizerSpec end
```

Proposed addition:

```julia
abstract type HTMLVisualizerSpec end
abstract type VegaVisualizerSpec <: HTMLVisualizerSpec end
abstract type SVGVisualizerSpec  <: HTMLVisualizerSpec end  # NEW
```

Contract for `SVGVisualizerSpec` subtypes:

| method                          | who defines it                                   |
| ------------------------------- | ------------------------------------------------ |
| `svg(spec::T)::String`          | the concrete subtype (e.g. `SquareStackTableSpec`)       |
| `html(spec::SVGVisualizerSpec)` | **generic**, lives in new `src/svg_general.jl`   |
| `open_in_browser(spec)`         | already generic on `HTMLVisualizerSpec`          |

The generic `html(::SVGVisualizerSpec)` wraps the subtype's SVG output
in a minimal HTML page (title, centered viewport, subtle shadow — mirror
the existing Vega wrapper's shell so both look consistent).

`html` is already declared as a bare `function html end` stub in
`HTMLVisualizers.jl`. `svg`, by contrast, only exists as a method on
`VegaVisualizerSpec` inside `vega_general.jl` — it should be promoted
to a bare `function svg end` declaration in `HTMLVisualizers.jl` so
both branches can add methods without include-order coupling.

---

## Data model

```julia
"""
    SquareStackTableRow(label, squares; extras=Any[])

One row of a SquareStackTable.

- `label::String` — right-aligned text in column 1.
- `squares::Vector{String}` — one entry per square, value = category name.
  Treated as a multiset by the renderer: at emit time, squares are
  grouped by category and laid out left-to-right in legend order, so
  the input order doesn't affect the rendered output. (Two rows with
  the same per-category counts always render identically.)
- `extras::Vector{Any}` — optional trailing column values (strings or
  numbers). Rows may have fewer extras than the spec declares; missing
  cells render blank.
"""
struct SquareStackTableRow
    label::String
    squares::Vector{String}
    extras::Vector{Any}
end

SquareStackTableRow(label, squares; extras=Any[]) = SquareStackTableRow(label, squares, extras)
```

Alternative shape considered and rejected: `squares::Vector{Pair{String,Int}}`
(category → count). The current `Vector{String}` form is more general
(you can have the same category appear in non-contiguous positions) and
trivially compatible — call sites that *do* want count-based input can
build the vector with `repeat`/`vcat`. Not worth a second API.

```julia
"""
    SquareStackTableColumn(header, align; font_family=nothing, char_width_ratio=nothing)

Describes one of the optional extra columns.

- `header::String` — column header text. Empty strings are allowed and
  render as a blank header cell (the header row itself is always present
  when `config.show_header` is true).
- `align::Symbol` — `:left`, `:right`, or `:center`. Numeric columns
  should generally be `:right`.
- `font_family::Union{String,Nothing}` — optional per-column font
  override. `nothing` inherits `config.font_family` (monospace by
  default). Use this to put, e.g., a comment/free-text column in a
  proportional font while keeping numeric columns monospace so digits
  line up. See "Mixing fonts" below.
- `char_width_ratio::Union{Float64,Nothing}` — optional per-column
  char-width-to-font-size ratio used for layout math. `nothing` inherits
  `config.char_width_ratio`. Only needed when `font_family` is set to a
  non-monospace font with a significantly different average width.
"""
struct SquareStackTableColumn
    header::String
    align::Symbol
    font_family::Union{String,Nothing}
    char_width_ratio::Union{Float64,Nothing}
end

SquareStackTableColumn(header, align; font_family=nothing, char_width_ratio=nothing) =
    SquareStackTableColumn(header, align, font_family, char_width_ratio)
```

**Mixing fonts.** Monospace is the safe default: character width is
exactly `font_size * char_width_ratio`, so column widths come out
pixel-correct. When a column opts into a proportional font, its width
is computed from the same ratio applied to the max character count —
this is an *approximation*, conservative for most Latin text but not
guaranteed. Two practical consequences:

1. **Numeric columns should stay on the default (monospace).** That's
   why the default font family is monospace — digits have equal width,
   so `211` and `32` right-align cleanly.
2. **Put proportional columns last.** If the rightmost column uses a
   proportional font (typical for a "comment" free-text column), a
   slight width over- or under-estimate just means the column overflows
   to the right, which is harmless. Putting a proportional column in
   the middle can cause later columns to shift slightly from where
   their text-anchor points say they should be.

For v1 we do not measure text. If callers need exact width for
proportional fonts, they can tune `char_width_ratio` per column; the
infrastructure is there. Note that the default `0.6` is tuned for
monospace — typical proportional Latin fonts (Helvetica, Inter, system
sans) average closer to `0.5`, and variable-width glyph sets have high
variance, so always override `char_width_ratio` when switching a
column to a proportional font.

```julia
Base.@kwdef struct SquareStackTableConfig
    # Typography — monospace is load-bearing for layout math
    font_family::String = "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
    font_size::Int = 14
    # Approx char width as a fraction of font_size. 0.6 is safe for the
    # fonts in font_family above. Exposed so callers can tune it if they
    # swap fonts.
    char_width_ratio::Float64 = 0.6

    # Row & square geometry. square_gap is deliberately non-zero so
    # readers can count individual squares easily — matches the ASCII
    # reference in the spec description.
    row_height::Int    = 22
    square_size::Int   = 14
    square_gap::Int    = 4
    column_gap::Int    = 20

    # Chrome
    padding::NamedTuple{(:top,:right,:bottom,:left), NTuple{4,Int}} =
        (top=20, right=20, bottom=20, left=20)
    background::String = "#ffffff"
    text_color::String = "#222222"
    header_color::String = "#555555"
    show_header::Bool  = true
    title_fontsize::Int = 20
    title_color::String = "#222222"

    # Legend
    show_legend::Bool        = true
    legend_swatch_size::Int  = 14
    legend_row_height::Int   = 20
    legend_gap::Int          = 8   # gap between swatch and label text
    legend_bottom_margin::Int = 12  # space between legend and header row

    # Color palette for auto-assigned category colors. Used only for
    # categories not present in SquareStackTableSpec.category_colors.
    palette::Vector{String} = [
        "#4e79a7", "#f28e2b", "#e15759", "#76b7b2", "#59a14f",
        "#edc949", "#af7aa1", "#ff9da7", "#9c755f", "#bab0ab",
    ]
end
```

```julia
"""
    SquareStackTableSpec(rows; title="", label_header="", histogram_header="",
                 columns=SquareStackTableColumn[],
                 category_colors=Dict{String,String}(),
                 legend_order=String[],
                 label_font_family=nothing,
                 config=SquareStackTableConfig())

A complete SquareStackTable plot.

- `rows` — the data.
- `label_header` — header text for the label column (column 1).
- `histogram_header` — header text for the square-histogram column
  (column 2). The histogram column itself has no text data, so no
  font override is needed here — the header text uses the config font.
- `columns` — schema for the extra columns (after label and histogram).
  Length = number of extras per row (rows are padded/truncated to match).
  Headers and fonts for these columns live on the
  `SquareStackTableColumn` entries.
- `category_colors` — explicit category→hex overrides. Categories not
  listed are assigned from `config.palette` in first-seen order.
- `legend_order` — optional explicit category order for the legend.
  Any categories present in the data but missing from this list are
  appended in first-seen order. Empty → pure first-seen order.
- `label_font_family` — optional override for the label column's font.
  `nothing` inherits `config.font_family`. Same trade-offs as the
  per-extras-column `font_family` (see "Mixing fonts" above).
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
```

Plus keyword-constructor convenience, matching the Sankey style.

---

## Layout algorithm

All coordinates in SVG user units (≈ pixels at 1:1 zoom).

### 1. Resolve colors and legend order

Walk `rows` in order, collecting distinct categories in first-seen order.
For each, look up `spec.category_colors` first; fall back to
`config.palette[mod1(i, length(palette))]` (Julia is 1-indexed —
`i % length(palette)` would hit index `0`). Entries in
`spec.category_colors` that don't correspond to any category seen in
the data are ignored (they neither widen the legend nor get emitted).
Result: a `Dict{String,String}` that the render pass can consult per
square.

Then build the **legend order**: start with `spec.legend_order`
(preserving the user's chosen sequence, dropping any entries that don't
actually appear in the data), then append any remaining data categories
in first-seen order. This is the list the legend walks; it is also the
list of distinct colors shown above the table.

### 2. Compute column widths

Each text column has its own effective char width, based on whichever
font it renders in:

```
cw_default   = config.font_size * config.char_width_ratio
cw_label     = cw_default   # v1: label column always uses config.char_width_ratio
                            # even when label_font_family overrides the font. If
                            # a proportional label font is used, widen manually
                            # via a longer label_header or add a
                            # label_char_width_ratio field later.
cw_extras[k] = config.font_size * coalesce(columns[k].char_width_ratio,
                                           config.char_width_ratio)
```

When `config.show_header` is true, include each column's header length
in its max-width calculation so long headers don't get clipped. When
`show_header` is false the header term is dropped entirely — headers
aren't drawn, so they shouldn't inflate column widths. All `maximum`
calls over `rows` take an `init=0` seed so empty-row specs don't throw.
Header text renders in the column's own font, so it uses the same
per-column `cw`.

Let `hlen(s) = show_header ? length(s) : 0`.

- `label_content = maximum((length(r.label) for r in rows); init=0)`
- `label_w       = max(hlen(label_header), label_content) * cw_label`

- `squares_content = maximum((length(r.squares) for r in rows); init=0)`
- `squares_w = max(
      hlen(histogram_header) * cw_default,
      squares_content == 0 ? 0 :
          squares_content * (config.square_size + config.square_gap) - config.square_gap)`

  The histogram column's header uses the default config font (the
  histogram column has no data-row text, so there's nothing to conflict
  with).

- For each extra column `k`:
  - `extras_content_k = maximum((length(string(row_value_or_empty(r, k))) for r in rows); init=0)`
  - `extras_w[k]      = max(hlen(columns[k].header), extras_content_k) * cw_extras[k]`

An extras column whose computed `extras_w[k]` is 0 (empty header under
`show_header=true` or header hidden, *and* no row has content for it)
is dropped entirely in step 4 — both the column and its leading
`column_gap` are skipped, so an empty column costs zero horizontal
space.

### 3. Compute legend dimensions

Only runs if `config.show_legend` is true and at least one category
exists.

```
legend_entries = <legend_order from step 1>
legend_label_w = maximum(length(cat) for cat in legend_entries) * cw_default
legend_w       = legend_swatch_size + legend_gap + legend_label_w
legend_h       = length(legend_entries) * legend_row_height + legend_bottom_margin
```

If `show_legend` is false or there are zero categories, `legend_h = 0`
and `legend_w = 0`.

### 4. Compute row/column origins

Each non-empty extras column has a **left edge** and a **right edge**.
The text anchor-x for that column's header and data cells then depends
on its `align` setting (see table below). Build the origins
iteratively so indexing stays unambiguous and empty extras columns are
cleanly skipped:

```
x0 = padding.left
label_x      = x0 + label_w              # right-aligned; label_x is the right edge
hist_x       = label_x + column_gap
cursor       = hist_x + squares_w

# Per-column origins for the non-empty extras columns only.
extras_left  = Dict{Int,Int}()           # k => left edge
extras_right = Dict{Int,Int}()           # k => right edge
for k in 1:length(columns)
    extras_w[k] == 0 && continue         # skip empty columns, no gap consumed
    cursor += column_gap
    extras_left[k]  = cursor
    cursor += extras_w[k]
    extras_right[k] = cursor
end
table_right  = cursor                    # equals hist_x + squares_w when no extras
total_width  = max(table_right, x0 + legend_w) + padding.right

title_h      = isempty(title) ? 0 : title_fontsize + 10
legend_y0    = padding.top + title_h                    # top of legend block
header_y     = legend_y0 + legend_h                     # header row baseline band
header_h     = show_header ? row_height : 0
y0           = header_y + header_h                      # first data row
row_y(i)     = y0 + (i-1) * row_height
total_height = y0 + length(rows) * row_height + padding.bottom
```

Per-column text anchor for extras column `k` — used identically for
the header cell and every data cell in that column:

| `align[k]` | `text-anchor` | anchor x                                      |
| ---------- | ------------- | --------------------------------------------- |
| `:left`    | `"start"`     | `extras_left[k]`                              |
| `:right`   | `"end"`       | `extras_right[k]`                             |
| `:center`  | `"middle"`    | `(extras_left[k] + extras_right[k]) ÷ 2`      |

Call this mapping `anchor_x(k)` in the SVG emit step below.

Legend does NOT participate in the table's column widths — it's a
free-standing block pinned to the left margin. It only affects
`total_width` if the longest legend entry exceeds the table's own width
(handled by the `max(...)` above).

#### Histogram wrap (`max_squares_per_row`)

`SquareStackTableConfig.max_squares_per_row::Union{Int,Nothing}` caps
the histogram column's *visible* width in squares. `nothing` (the
default) disables wrapping entirely; un-capped output is byte-for-byte
identical to the pre-wrap implementation. When set, any row whose
`length(squares)` exceeds the cap wraps onto additional sub-rows of
`row_height` pixels each — only the affected row grows taller, neighbours
are unchanged.

The layout pre-pass derives three values for the emit pass:

- `effective_per_row = min(max_squares_per_row, max_data_squares)` when
  the cap is set; equals `max_data_squares` (clamped to ≥ 1) when it
  isn't. Used as the wrap divisor and as the column-count input to
  `squares_w_from_data`. Clamping to `min(...)` means a cap larger than
  the longest row is a no-op, and clamping to `≥ 1` keeps the modulo
  arithmetic well-defined when there are no squares anywhere.
- `row_sub_rows[i] = max(1, cld(length(rows[i].squares), effective_per_row))`.
- `row_tops[i]` — cumulative `y0 + Σ row_sub_rows[1:i-1] * row_height`.
  Replaces the inline `y0 + (i-1)*row_height` formula in the emit loop.

Validation: `compute_layout` raises `ArgumentError` when
`max_squares_per_row` is set to a value `< 1`.

The square emit loop computes per-square placement as
`col = (j-1) % effective_per_row`,
`subrow = (j-1) ÷ effective_per_row`,
`sx = hist_x + col * (square_size + square_gap)`,
`sy = row_top + subrow * row_height + (row_height - square_size) ÷ 2`.

**Text alignment in tall rows.** The label and extras `<text>` elements
of a wrapped row sit at `row_top + row_height ÷ 2` — the centre of the
*first* sub-row, not the centre of the full (taller) band. This keeps
the text visually anchored to the top row of squares, which is the
behaviour the feature was specced for.

### 5. Emit SVG

Structure (in draw order, top to bottom):

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="W" height="H" viewBox="0 0 W H">
  <rect width="100%" height="100%" fill="{background}"/>   <!-- background -->

  <!-- 1. Title (optional) -->
  <text x="..." y="..." font-size="title_fontsize" fill="title_color">{title}</text>

  <!-- 2. Legend (optional) — one <g> per category -->
  <g font-family="mono" font-size="N">
    <g transform="translate(padding.left, legend_y0)">
      <rect x="0" y="0" width="sw" height="sw" fill="{color_for(cat)}"/>
      <text x="sw + legend_gap" y="sw/2" dominant-baseline="central"
            fill="text_color">{cat}</text>
    </g>
    <g transform="translate(padding.left, legend_y0 + legend_row_height)"> ... </g>
    ...
  </g>

  <!-- 3. Header row (when show_header is true) -->
  <g font-family="mono" font-size="N" fill="{header_color}">
    <text x="label_x"    y="header_y + row_height/2" text-anchor="end"
          dominant-baseline="central">{label_header}</text>
    <text x="hist_x"     y="header_y + row_height/2" text-anchor="start"
          dominant-baseline="central">{histogram_header}</text>
    <text x="anchor_x(k)" y="header_y + row_height/2"
          text-anchor="{start|end|middle}"
          dominant-baseline="central">{columns[k].header}</text>
    ...
  </g>

  <!-- 4. Data rows -->
  <g font-family="mono" font-size="N" fill="{text_color}">
    <g transform="translate(0, row_y(i))">
      <text x="label_x" y="row_height/2" text-anchor="end"
            dominant-baseline="central">{row.label}</text>

      <!-- For each square in sort_squares_for_render(row.squares, legend_order): -->
      <rect x="hist_x + j*(sq+gap)" y="(row_height - sq)/2"
            width="sq" height="sq" fill="{color_for(cat)}"/>
      ...

      <text x="anchor_x(k)" y="row_height/2"
            text-anchor="{start|end|middle}"
            dominant-baseline="central">{row.extras[k]}</text>
    </g>
    ...
  </g>
</svg>
```

**Square ordering.** The squares loop does NOT iterate `row.squares`
directly. Instead, the row's squares are first reordered by
`sort_squares_for_render(row.squares, legend_order)` so that all squares
of the same category are contiguous, with categories laid out in the
canonical legend order from §1. Two rows with the same per-category
counts render identically regardless of input ordering.

Header alignment per column matches the data column's alignment: label
is right-aligned (`text-anchor="end"`), histogram header is left-aligned
(`text-anchor="start"`, anchored at `hist_x`), extras follow their
`SquareStackTableColumn.align`. This keeps the header visually lined up with
the cells below it.

The header text uses `header_color` instead of `text_color` so it reads
as chrome, not data.

**Per-column fonts.** The outer `<g>` elements above show a single
`font-family` for illustration, but the real emit sets `font-family`
per `<text>` (or per inner `<g>` wrapping all texts of one column) so
that columns with an override render in their chosen font. Header
texts inherit their column's font, not the global default, so a
proportional extras column gets proportional headers too. The
histogram column has no text data and uses `config.font_family` for
its header.

Text baselines: with `dominant-baseline="central"` and `y = row_y(i) + row_height/2`, text sits vertically centered in its row. Same trick for square vertical centering: `y = row_y(i) + (row_height - sq_size) / 2`.

Portability note: `dominant-baseline="central"` is well-supported in
modern browsers but can render inconsistently in stricter SVG
consumers (older Inkscape, some SVG-to-PDF toolchains). If standalone
`.svg` output needs to look identical everywhere, fall back to an
explicit vertical offset: `y = row_y(i) + row_height/2 + font_size * 0.35`
and omit the `dominant-baseline` attribute. v1 uses `central` and
accepts modern-browser rendering; revisit if a consumer complains.

All emitted text must be HTML-escaped (`&` → `&amp;`, `<` → `&lt;`,
`>` → `&gt;`, `"` → `&quot;`). Build a small `escape_xml` helper in
`svg_general.jl` — both this spec and any future SVG specs will need it.

### 6. Wrap for HTML

`html(::SVGVisualizerSpec)` returns:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>{title or "Visualization"}</title>
  <style> body { ... same centered, shadowed card as vega_general.jl ... } </style>
</head>
<body>
  <div id="vis">{svg_string}</div>
</body>
</html>
```

No JS runtime. No CDN dependencies.

---

## File & export layout

New files:

- [src/svg_general.jl](../src/svg_general.jl) — generic
  `html(::SVGVisualizerSpec)`, `escape_xml`, maybe shared SVG element
  builders if they start repeating.
- [src/svg_square_stack_table.jl](../src/svg_square_stack_table.jl) —
  `SquareStackTableRow`, `SquareStackTableColumn`,
  `SquareStackTableConfig`, `SquareStackTableSpec`,
  `svg(::SquareStackTableSpec)`, and internal layout helpers.

Modified files:

- [src/HTMLVisualizers.jl](../src/HTMLVisualizers.jl):
  1. Add `abstract type SVGVisualizerSpec <: HTMLVisualizerSpec end`.
  2. Promote `function svg end` to a top-level stub in this file
     (currently it only exists as the Vega-specific method in
     `vega_general.jl`). `function html end` is already a top-level
     stub and doesn't need to change.
  3. `include("svg_general.jl")` and `include("svg_square_stack_table.jl")`
     after the Vega includes.
  4. Export `SquareStackTableSpec`, `SquareStackTableRow`, `SquareStackTableColumn`,
     `SquareStackTableConfig`. (Don't re-export `svg`/`html` — already exported.)

---

## Testing plan

New file: [test/svg_square_stack_table_test.jl](../test/svg_square_stack_table_test.jl),
added to [test/runtests.jl](../test/runtests.jl).

Unit tests:

1. **Construction**
   - `SquareStackTableRow`, `SquareStackTableColumn`, `SquareStackTableConfig`, `SquareStackTableSpec`
     build with sane defaults and kwargs.
   - Rows with fewer extras than `columns` length are accepted (missing
     cells render blank).

2. **Color resolution**
   - Explicit `category_colors` wins over the palette.
   - Unknown categories are assigned from the palette in first-seen
     order, deterministically.
   - Same category gets the same color across all rows.

3. **Legend order**
   - With no `legend_order`, categories appear in first-seen order from
     the data.
   - An explicit `legend_order` is honored, and data-only categories are
     appended after it.
   - Entries in `legend_order` that don't appear in the data are dropped
     (not rendered).

4. **Layout math** (test the helpers, not the SVG string)
   - Column widths scale with max-content length, and also grow to fit
     their header text.
   - Legend height = `n_categories * legend_row_height + legend_bottom_margin`
     when `show_legend` is true; zero when false.
   - Total width reflects `max(table_right, legend_w + padding.left)`.
   - Total width/height match the formulas above for a known fixture.
   - Empty extras vector → no extras columns, total width is just
     `label + gap + histogram + padding` (still growing for legend if
     needed).

5. **SVG output structure**
   - Result starts with `<svg` and ends with `</svg>`.
   - One `<rect>` per square across all rows (count them by a regex)
     plus one background rect plus one swatch rect per legend entry.
   - Every row's label text appears exactly once in the output
     (HTML-escaped if needed).
   - Title text appears iff `title` is nonempty.
   - Header texts (`label_header`, `histogram_header`, each
     `columns[k].header`) appear in the output when `show_header` is
     true, and not when it's false.
   - Legend swatches: one rect per distinct category actually used in
     `rows.squares`, in `legend_order` sequence.
   - **Squares within a row are grouped by category in legend order**
     (`sort_squares_for_render`): a row built from `["b","a","b","a"]`
     emits four `<rect>` fills as `[b, b, a, a]` (or `[a, a, b, b]` if
     legend order puts `a` first), never interleaved.
   - Special chars in labels / headers / category names (`<`, `&`) are
     escaped.

6. **Per-column fonts**
   - A column with a `font_family` override emits `font-family="..."`
     on its text elements (or an enclosing `<g>`), and the override
     value appears in the rendered SVG.
   - Columns without an override do not leak per-column `font-family`
     attributes and inherit the root `<g>` / default.
   - A `char_width_ratio` override widens the column in the layout
     calculation (assert width grows vs. the default ratio on a fixed
     fixture).

7. **HTML wrap**
   - `html(spec)` contains the full SVG string and a matching `<title>`.

Regression test (mirrors
[test/vega_sankey_regression_test.jl](../test/vega_sankey_regression_test.jl)):

8. A fixed `SquareStackTableSpec` fixture → byte-for-byte compare against a
   checked-in reference at `test/data/square_stack_table_basic.html`
   (and optionally `square_stack_table_basic.svg`). Because every
   layout quantity — column widths, cursor positions, square
   coordinates, legend offsets — is computed in `Int` arithmetic,
   byte-for-byte comparison is stable across platforms with no float
   rounding to chase. Regenerate on intentional rendering changes,
   same workflow as the Sankey regression.

Out of scope for v1 (note in the doc, don't block shipping):

- Interactive tooltips / hover states
- Horizontal legend layout (v1 is vertical, pinned above the header)
- Row sorting by histogram length
- Runtime text measurement for proportional fonts (v1 uses a
  per-column `char_width_ratio` approximation instead)
- `Printf`-style numeric formatting (v1 uses `string(x)` for extras)

---

## Open questions for revisit

1. **Square shape.** Same layout works with circles (`<circle>`) or
   rounded rects. v1 is square-only per user decision; revisit if a
   non-square variant is requested.
2. **Numeric formatting.** `string(x)` is sufficient for v1. If users
   later want locale-aware or fixed-precision formatting, add a
   `Printf` format string field per `SquareStackTableColumn`. The
   per-column font infrastructure already gives us the typographic
   half of the problem.
3. **Proportional-font label column.** The per-column font-override
   mechanism is wired through for extras columns; for v1 the label
   column inherits `config.char_width_ratio` even when
   `label_font_family` is set. If this ever matters in practice, add a
   `label_char_width_ratio` field symmetrically.
