# New visualization: `SparseMatrixSpec` (reorderable sparse matrix)

## Context

Add a new visualization to the `HTMLVisualizers` package: a sparse matrix
rendered with row and column labels, where each label is
drag-reorderable at runtime — in the style of the Vega
[reorderable-matrix example](https://vega.github.io/vega/examples/reorderable-matrix/),
but with **independent row and column axes** (the entities on the two
axes may differ, and dragging a label reorders only its own axis).

The user supplies sparse cell data as an `AbstractVector` of either
`SparseMatrixCell` structs or bare `NamedTuple`s carrying
`row::String`, `column::String`, an optional `color::Colors.Colorant`
(defaulting from `config.default_color`), and an optional `value` of
any type — one entry per drawn cell. Rows and columns are derived from
the cells; initial orderings can be overridden via kwargs.

Backend: **Vega** (reuses the existing `VegaVisualizerSpec` branch and
its `html`/`svg`/`open_in_browser` generics). Drag-to-reorder is
natural in Vega via event-scoped signals and `modify` data transforms;
the existing `SankeySpec` is the closest template.

---

## Data and type model

**Cell type** — parametric struct with optional `value::T` (default `nothing`):

```julia
Base.@kwdef struct SparseMatrixCell{T}
    row::String
    column::String
    color::Colors.Colorant
    value::T = nothing
end

# bridge constructor — accepts any NamedTuple with the required fields
# (plus optional :value); field order doesn't matter (field access, not dispatch)
SparseMatrixCell(nt::NamedTuple) =
    SparseMatrixCell(nt.row, nt.column, nt.color, get(nt, :value, nothing))
```

`T` is inferred per cell, so a homogeneous input (all `Float64`, say) gives a
concretely-typed `Vector{SparseMatrixCell{Float64}}`; mixed inputs fall back to
`Vector{SparseMatrixCell}` with an abstract element type — acceptable, this
isn't a hot path. The bridge constructor preserves the NamedTuple-literal call
style from the previous plan revision.

**Config** (styling, mirrors `SankeyConfig`):

```julia
Base.@kwdef struct SparseMatrixConfig
    width::Int = 600
    height::Int = 600
    band_padding::Float64 = 0.05          # band-scale paddingInner
    label_font_size::Int = 12
    label_gap::Int = 8
    title_color::String = "#005ca5"
    title_fontsize::Int = 24
    background::String = "#fafafa"
    default_color::Colors.Colorant = colorant"steelblue"  # used for cells whose
                                                          # NamedTuple input omits :color
    hover_color::String = "#ffd54f"
    hover_opacity::Float64 = 0.25
    cell_stroke::String = "#ffffff"
    cell_stroke_width::Float64 = 1.0
    chart_padding::NamedTuple{(:top,:right,:bottom,:left),NTuple{4,Int}} =
        (top=80, right=20, bottom=20, left=120)  # room for top/left labels
end
```

**Spec**:

```julia
struct SparseMatrixSpec <: VegaVisualizerSpec
    cells::Vector{SparseMatrixCell}
    row_order::Vector{String}        # resolved (first-seen if not overridden)
    column_order::Vector{String}     # resolved
    title::String
    config::SparseMatrixConfig
end
```

Primary constructor signature:

```julia
SparseMatrixSpec(cells::AbstractVector;
                 title::AbstractString = "",
                 row_order::AbstractVector{<:AbstractString} = String[],
                 column_order::AbstractVector{<:AbstractString} = String[],
                 config::SparseMatrixConfig = SparseMatrixConfig())
```

The constructor normalizes each element:
- Pass-through if already a `SparseMatrixCell`.
- Otherwise, for `NamedTuple` inputs, fill in `color = config.default_color`
  when `:color` is absent before handing off to `SparseMatrixCell(nt)`.
  This is the one place `config.default_color` is applied — directly-
  constructed `SparseMatrixCell` values must still supply `color`.

It then calls `derive_orderings` to resolve the ordering vectors,
de-duplicates on `(row, column)` with last-wins semantics (emitting
`@warn` on collision), and stores the result. Elements that are neither
`SparseMatrixCell` nor a `NamedTuple` with the required fields error out
with a clear `ArgumentError`.

**Storage subtlety.** Parametric `Vector` types are invariant —
`Vector{SparseMatrixCell{Float64}}` is *not* a subtype of
`Vector{SparseMatrixCell}`. A comprehension like
`[SparseMatrixCell(c) for c in cells]` whose elements are all
`SparseMatrixCell{Float64}` will produce a concrete-eltype vector that
won't fit the `cells::Vector{SparseMatrixCell}` field. Build with the
abstract eltype explicitly:
```julia
SparseMatrixCell[c isa SparseMatrixCell ? c : SparseMatrixCell(c) for c in cells]
```

---

## Ordering resolution

Helper `derive_orderings(cells, row_override, column_override)` returns
`(rows::Vector{String}, cols::Vector{String})` using the same
"override-first-then-append-in-first-seen-order" pattern already
implemented in `resolve_legend_order`
([src/svg_square_stack_table.jl:218](../src/svg_square_stack_table.jl#L218)).
Override names not present in the data are dropped silently (matches
existing precedent).

Edge cases:
- **Empty `cells`** → both orderings are `String[]`; `vega_spec` still
  returns a valid spec that renders an empty matrix.
- **Duplicate `(row, column)`** → last-wins, `@warn` emitted once per
  duplicate key at spec-construction time (inside `dedupe_cells`, called
  from the outer `SparseMatrixSpec` constructor).
- **Override contains unknown names** → dropped.

---

## Vega spec design — the drag wiring

Independent-axis reordering needs **two parallel, non-interacting swap
machines**. The single most important correctness invariant: every
`on` handler uses a named-mark selector (`@rowLabels:…` or
`@colLabels:…`), never a generic `mousedown`/`mouseover`, so a gesture
on one axis cannot mutate the other axis's ordering data.

### Signals (six + one derived)

- `rowSrc` — `null`; set to `datum.name` on `@rowLabels:mousedown`;
  on `@rowLabels:mouseover` (while `rowSrc != null`) re-set to
  `datum.name` so chained swaps work during a single drag; reset to
  `null` on `window:mouseup`.
- `rowDest` — `null`; on `@rowLabels:mouseover` set to `datum.name` if
  `rowSrc != null`; reset on `window:mouseup`.
- `rowActive` — hover-highlight target; set to `datum.name` on
  `@rowLabels:mouseover` and to `datum.row` on `@cells:mouseover`
  (cell-hover crosshair); reset to `null` on `@rowLabels:mouseout`
  and `@cells:mouseout`.
- `colSrc`, `colDest`, `colActive` — identical, bound to `@colLabels:…`
  events; `colActive` additionally updated to `datum.column` on
  `@cells:mouseover` and cleared on `@cells:mouseout`.
- `anyDragging` — `rowSrc != null || colSrc != null`, drives cursor and
  suppresses the cell tooltip during drag.

### Data tables

Three tables:

1. `cells` — user data, with `color` field already converted to
   `"#rrggbb"` via `"#" * Colors.hex(c)`.
2. `rowIndex` — `[{name, i}]`, one row per resolved row name, `i`
   initialized to the 0-based position. Has an `on` block:
   ```
   trigger: rowSrc && rowDest && rowSrc != rowDest
   modify:  rowIndex
   values:  <swap i of the rows where name==rowSrc / name==rowDest>
   ```
3. `colIndex` — analogous, triggered only by `colSrc`/`colDest`.

Because `rowIndex.on` examines only `rowSrc`/`rowDest`, and `colIndex.on`
only `colSrc`/`colDest`, the two mutation machines are fully independent.

### Scales

Two band scales whose domains come from the index tables, sorted by
`i`:

```julia
Dict("name"=>"xScale", "type"=>"band", "range"=>"width",
     "domain"=>Dict("data"=>"colIndex", "field"=>"name",
                    "sort"=>Dict("field"=>"i", "order"=>"ascending")),
     "paddingInner"=>config.band_padding)
# yScale — same shape, from rowIndex, range "height"
```

When a swap mutates `i` values, the band scale's sorted domain updates
automatically → all cells and labels rebind to new positions.

### Marks

- **Cells** (`rect`, `name="cells"`, from `cells`): `x=scale('xScale',datum.column)`,
  `y=scale('yScale',datum.row)`, `width/height=bandwidth(...)`, `fill`
  is the pre-converted hex string. Guard with
  `indata('rowIndex','name',datum.row) && indata('colIndex','name',datum.column)`.
  Tooltip encoding — shows the raw `value` when present, suppressed
  during drag and on cells without a value:
  ```julia
  "tooltip" => Dict("signal" =>
      "!anyDragging && datum.value != null ? datum.value : null")
  ```
  The `name="cells"` also enables the `@cells:mouseover`/`mouseout`
  events that drive the row/column crosshair highlighting (see
  `rowActive`/`colActive` above).
- **Row hover bar** (`rect`): full-width, at
  `y=scale('yScale',rowActive)`; shown only when `rowActive != null`;
  `fill=config.hover_color`, `opacity=config.hover_opacity`.
- **Column hover bar** (`rect`): analogous.
- **Row labels** (`text`, `name="rowLabels"`, from `rowIndex`):
  `x = -config.label_gap`, `y = scale('yScale',datum.name) + bandwidth/2`,
  `align="right"`, cursor `grab`/`grabbing` driven by `anyDragging`.
- **Column labels** (`text`, `name="colLabels"`, from `colIndex`):
  `x = scale('xScale',datum.name) + bandwidth/2`,
  `y = -config.label_gap`, `angle=-90`, `align="left"`,
  `baseline="middle"`.

---

## File layout

### New: `src/vega_sparse_matrix.jl`

Public:
- `struct SparseMatrixCell{T}` (`Base.@kwdef`, `value::T = nothing`) +
  bridge constructor `SparseMatrixCell(::NamedTuple)`
- `struct SparseMatrixConfig` (Base.@kwdef)
- `struct SparseMatrixSpec <: VegaVisualizerSpec` + outer constructor
- `vega_spec(spec::SparseMatrixSpec)::Dict{String,Any}`

Internal (unexported):
- `derive_orderings(cells, row_override, column_override)` — reuses
  pattern from `resolve_legend_order` at
  [src/svg_square_stack_table.jl:218](../src/svg_square_stack_table.jl#L218).
- `dedupe_cells(cells)` — last-wins with `@warn`.
- `cell_to_hex_dict(cell)` — `"#" * Colors.hex(cell.color)` + row/column
  strings; the `"value"` key is emitted only when the value is a real
  datum. Specifically, it is **omitted** when:
  ```julia
  cell.value === nothing || cell.value === missing ||
      (cell.value isa AbstractFloat && isnan(cell.value))
  ```
  This keeps the tooltip signal (`!anyDragging && datum.value != null ?
  datum.value : null`) automatically suppressed for sentinel values.
- `generate_signals()`, `generate_data_transforms(cells_hex, rows, cols)`,
  `generate_scales(config)`, `generate_marks(config)` — decomposition
  matches the Sankey file ([src/vega_sankey.jl](../src/vega_sankey.jl)).

### New: `src/sparse_matrix_helpers.jl`

Unexported convenience helpers for the common use case of coloring a
sparse matrix of `Float64` values via a caller-supplied colormap, with
clipping at `value_low`/`value_high` and distinct sentinel colors for
`NaN`/`nothing`/`missing`.

```julia
# Atomic: Float64 → Colorant
function colormap_cell_color(value::Float64;
                              colormap,                 # t∈[0,1] → Colors.Colorant
                              value_low::Float64,
                              value_high::Float64,
                              color_low::Colors.Colorant,
                              color_high::Colors.Colorant,
                              color_nan::Colors.Colorant)::Colors.Colorant
    isnan(value)       && return color_nan
    value < value_low  && return color_low
    value > value_high && return color_high
    return colormap((value - value_low) / (value_high - value_low))
end

# Batch: (row, column, value::Union{Float64,Nothing,Missing}) triples
#        → Vector{SparseMatrixCell}
function matrix_cells_from_values(triples; colormap,
                                   value_low::Float64, value_high::Float64,
                                   color_low::Colors.Colorant,
                                   color_high::Colors.Colorant,
                                   color_nan::Colors.Colorant,
                                   color_nothing::Colors.Colorant = color_nan,
                                   color_missing::Colors.Colorant = color_nan)
    map(triples) do t
        v = t.value
        c = v === nothing ? color_nothing :
            v === missing ? color_missing :
                            colormap_cell_color(v;
                                colormap, value_low, value_high,
                                color_low, color_high, color_nan)
        SparseMatrixCell(t.row, t.column, c, v)
    end
end
```

Design notes:
- HTMLVisualizers stays **colormap-library-agnostic**. `colormap` is
  any `t → Colors.Colorant` callable. Users bring `ColorSchemes.jl`
  (e.g. `t -> get(ColorSchemes.viridis, t)`), a hand-rolled gradient,
  or anything else. `ColorSchemes` is **not** added as a dep.
- `color_nothing` and `color_missing` default to `color_nan`, so users
  who don't need to distinguish the three sentinels can pass a single
  "sentinel color" and be done.
- The atomic `colormap_cell_color` is kept `Float64`-only; all
  `nothing`/`missing` branching lives in the batch helper.
- The raw `value` (including `NaN`/`nothing`/`missing`) is preserved
  on the resulting `SparseMatrixCell`. `cell_to_hex_dict` then
  suppresses the tooltip for sentinel values (see above).

### Modify: `src/HTMLVisualizers.jl`

- Add `include("vega_sparse_matrix.jl")` after existing includes.
- Add `include("sparse_matrix_helpers.jl")` after that.
- Extend exports: `SparseMatrixCell, SparseMatrixConfig, SparseMatrixSpec`.
  (The two helper functions remain unexported — accessed via
  `HTMLVisualizers.matrix_cells_from_values` etc.)

### Modify: `Project.toml`

Add `Colors` to `[deps]`:
```toml
Colors = "5ae59095-9a9b-59fe-a467-6f913c188581"
```
and a `[compat]` entry (e.g. `Colors = "0.12, 0.13"` — pin to whatever
the current registry offers when implementing).

### Modify: `test/runtests.jl`

Append:
```julia
include("vega_sparse_matrix_test.jl")
include("vega_sparse_matrix_regression_test.jl")
include("sparse_matrix_helpers_test.jl")
```

### New: `test/vega_sparse_matrix_test.jl` — unit tests

- Construction from a `Vector{NamedTuple}` (bridge constructor path),
  with fields written in varying orders.
- Construction from a `Vector{SparseMatrixCell}` directly.
- Cells with and without `value`: default `value=nothing`; explicit
  `value=1.5` preserved.
- NamedTuple input without `:color` → filled from `config.default_color`
  (verify hex in output matches the configured default).
- Default `row_order` / `column_order` equal first-seen order.
- Override kwargs: explicit-first-then-appended behavior; unknown
  names dropped.
- Empty cells vector → empty orderings, valid spec.
- Duplicate `(row, column)` → last cell wins; `@test_logs (:warn, ...)`.
- `cell_to_hex_dict` against `colorant"red"`, `RGB(0,1,0)`, `RGBA(...)`;
  `"value"` key is omitted when `cell.value` is `nothing`, `missing`,
  or a `NaN` float, and included for all other values (integers,
  strings, finite floats, etc.).
- `vega_spec` shape: returns `Dict{String,Any}`; contains signals
  `rowSrc`/`colSrc`/`rowActive`/`colActive`/`anyDragging` etc.;
  `rowActive` and `colActive` `on` handlers include both label and
  `@cells:` event entries; both `rowIndex` and `colIndex` data entries
  exist; both scale domains carry `sort` by `i`; cell mark has
  `name="cells"` and a `tooltip` signal that references both
  `anyDragging` and `datum.value`.

### New: `test/vega_sparse_matrix_regression_test.jl` — golden HTML

Three fixtures, each compared byte-for-byte against a file in
`test/data/`:
- `sparse_matrix_basic.html` — ~3×4 sparse, no overrides.
- `sparse_matrix_dense.html` — 5×5 every-cell grid.
- `sparse_matrix_row_order_only.html` — only `row_order` specified.

Generate the golden files once during implementation by calling
`html(spec)` on each fixture and committing the output.

### New: `test/sparse_matrix_helpers_test.jl` — colormap-helper tests

Uses an intentionally trivial two-color linear gradient so tests stay
deterministic and dependency-free:

```julia
using Colors
gradient(t) = RGB(Float64(t), 0.0, 1.0 - Float64(t))    # 0 → blue, 1 → red
```

Fixture covering every branch:

```julia
triples = [
    (row="r1", column="c1", value = 0.0),      # at low   → gradient(0)  == RGB(0,0,1)
    (row="r1", column="c2", value = 1.0),      # at high  → gradient(1)  == RGB(1,0,0)
    (row="r1", column="c3", value = 0.5),      # midpoint → gradient(0.5)
    (row="r2", column="c1", value = -0.5),     # below    → color_low
    (row="r2", column="c2", value =  1.5),     # above    → color_high
    (row="r2", column="c3", value = NaN),      # NaN      → color_nan
    (row="r3", column="c1", value = nothing),  #          → color_nothing
    (row="r3", column="c2", value = missing),  #          → color_missing
]
```

Palette used in assertions:
```julia
color_low     = colorant"black"
color_high    = colorant"white"
color_nan     = colorant"magenta"
color_nothing = colorant"gray50"
color_missing = colorant"gray80"
```

Cases:

1. **`colormap_cell_color` branch coverage** — with `value_low=0.0`,
   `value_high=1.0`, and the gradient above:
   - `colormap_cell_color(NaN; …) === color_nan`
   - `colormap_cell_color(-0.5; …) === color_low`
   - `colormap_cell_color(1.5; …) === color_high`
   - `colormap_cell_color(0.0; …) == RGB(0.0, 0.0, 1.0)` (boundary
     goes through the colormap, not `color_low`)
   - `colormap_cell_color(1.0; …) == RGB(1.0, 0.0, 0.0)` (likewise)
   - `colormap_cell_color(0.5; …) == RGB(0.5, 0.0, 0.5)`

2. **`matrix_cells_from_values` batch** — passes the eight-element
   fixture above with the full palette. Assertions:
   - Output is a `Vector{SparseMatrixCell}` of length 8.
   - Cell `color` matches the expected branch for each row (using the
     branch map from case 1, plus `color_nothing`/`color_missing`).
   - Cell `value` is preserved verbatim: for the `nothing`/`missing`
     slots, `cells[i].value === triples[i].value`; for the `NaN` slot,
     `isnan(cells[i].value)` (using `==` would return `false` for the
     NaN case — `isnan` is the idiomatic check). All other slots
     compare with `==`.
   - `cells[i].row == triples[i].row`, same for column.

3. **Defaulting for the two sentinel kwargs** — call
   `matrix_cells_from_values` without `color_nothing` / `color_missing`
   and assert the `nothing`- and `missing`-valued cells both receive
   `color_nan`.

4. **End-to-end with `SparseMatrixSpec` + `vega_spec`** — take the
   batch from case 2, build a spec, and inspect the generated JSON:
   - In the `"cells"` data entry, cells with real float `value` have
     the `"value"` key; NaN/nothing/missing cells have **no**
     `"value"` key.
   - Hex strings on each cell match `"#" * Colors.hex(expected_color)`.
   - Tooltip encoding on the `cells` mark is present and uses the
     `!anyDragging && datum.value != null ? datum.value : null`
     signal.

5. **Non-default `value_low`/`value_high`** — re-run the branch test
   with `value_low=-10.0`, `value_high=10.0` and a value of `0.0` →
   assert it maps to `gradient(0.5) == RGB(0.5, 0, 0.5)` (verifies the
   normalization is correct, not hard-coded to `[0,1]`).

---

## Reuse summary

- `html(::VegaVisualizerSpec)` and `svg(::VegaVisualizerSpec)` in
  [src/vega_general.jl](../src/vega_general.jl) — unchanged.
- `open_in_browser` in [src/HTMLVisualizers.jl:38](../src/HTMLVisualizers.jl#L38) — unchanged.
- Ordering-resolution pattern from `resolve_legend_order` in
  [src/svg_square_stack_table.jl:218](../src/svg_square_stack_table.jl#L218) — transliterated.
- File decomposition mirrors [src/vega_sankey.jl](../src/vega_sankey.jl).

---

## Verification

1. `julia --project -e 'using Pkg; Pkg.test()'` — unit and regression
   tests must pass.
2. Interactive smoke test:
   ```julia
   using HTMLVisualizers, Colors
   cells = [
     (row="A", column="x", color=colorant"red",    value=1.0),
     (row="B", column="y", color=colorant"green",  value=2.5),
     (row="A", column="z"),                                   # no color, no value → uses config.default_color
     (row="C", column="x", color=colorant"orange", value="tag"),
   ]
   spec = SparseMatrixSpec(cells; title="demo")
   open_in_browser(spec)
   ```
   In the browser:
   - Matrix renders with 4 colored cells at the expected (row, col) positions.
   - Drag a row label up/down → that row moves; columns don't shift.
   - Drag a column label left/right → that column moves; rows don't shift.
   - Hovering a label highlights the corresponding row/column band.
   - Hovering a cell highlights both its row and column (crosshair).
   - Cells with a `value` show the raw value on hover; cells without a
     value show no tooltip. No tooltip appears while a drag is in progress.
3. SVG export: `svg(spec)` pipes through `vg2svg` (existing generic) and
   produces a static snapshot of the current ordering.
4. Colormap-helper smoke test (exercises the helpers end-to-end):
   ```julia
   using HTMLVisualizers, Colors
   using HTMLVisualizers: matrix_cells_from_values

   gradient(t) = RGB(Float64(t), 0.0, 1.0 - Float64(t))   # blue → red

   triples = [
       (row="r1", column="c1", value = 0.2),
       (row="r1", column="c2", value = 0.8),
       (row="r2", column="c1", value = -0.3),    # below range
       (row="r2", column="c2", value =  1.4),    # above range
       (row="r3", column="c1", value = NaN),
       (row="r3", column="c2", value = nothing),
       (row="r3", column="c3", value = missing),
   ]

   cells = matrix_cells_from_values(triples;
       colormap     = gradient,
       value_low    = 0.0,     value_high    = 1.0,
       color_low    = colorant"black",
       color_high   = colorant"white",
       color_nan    = colorant"magenta",
       color_nothing = colorant"gray50",
       color_missing = colorant"gray80",
   )

   open_in_browser(SparseMatrixSpec(cells; title="colormap demo"))
   ```
   In the browser:
   - In-range cells are colored on the blue→red gradient.
   - `-0.3` renders black, `1.4` renders white (clipping).
   - NaN/nothing/missing cells render magenta / gray50 / gray80.
   - Hovering an in-range cell shows its numeric value.
   - Hovering a NaN/nothing/missing cell shows **no tooltip**
     (sentinels are suppressed).

## Assumptions (call out if any should change)

- "Independent" means the axes are not linked during reorder — the row
  and column entities may overlap in name, but dragging a row label
  doesn't renumber columns even if a column with the same name exists.
- Duplicate `(row, column)` cells: last-wins + warning. (Alternative:
  error. Chosen last-wins for dict-assignment intuition and
  pipeline-friendliness; easy to flip later if desired.)
- Override names absent from the data are dropped silently (matches
  `resolve_legend_order`).
