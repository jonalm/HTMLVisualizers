
"""
    colormap_cell_color(value; colormap, value_low, value_high,
                               color_low, color_high, color_nan) -> Colorant

Pick a color for `value` by:
- returning `color_nan` when `value` is `NaN`,
- clipping to `color_low` / `color_high` outside `[value_low, value_high]`,
- otherwise mapping `t = (value - value_low) / (value_high - value_low)` through
  the caller-supplied `colormap` (any `t::Float64 -> Colors.Colorant` callable).
"""
function colormap_cell_color(value::Float64;
                             colormap,
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

"""
    matrix_cells_from_values(triples; colormap, value_low, value_high,
                                      color_low, color_high, color_nan,
                                      color_nothing=color_nan,
                                      color_missing=color_nan)
        -> Vector{SparseMatrixCell}

Build `SparseMatrixCell`s from an iterable of `(row, column, value)` triples
(`value` may be `Float64`, `nothing`, or `missing`). Sentinel values receive
their dedicated color; the raw `value` is preserved on the resulting cell.
"""
function matrix_cells_from_values(triples;
                                  colormap,
                                  value_low::Float64,
                                  value_high::Float64,
                                  color_low::Colors.Colorant,
                                  color_high::Colors.Colorant,
                                  color_nan::Colors.Colorant,
                                  color_nothing::Colors.Colorant = color_nan,
                                  color_missing::Colors.Colorant = color_nan)
    cells = SparseMatrixCell[]
    for t in triples
        v = t.value
        c = v === nothing ? color_nothing :
            v === missing ? color_missing :
                            colormap_cell_color(v;
                                colormap, value_low, value_high,
                                color_low, color_high, color_nan)
        push!(cells, SparseMatrixCell(t.row, t.column, c, v))
    end
    return cells
end
