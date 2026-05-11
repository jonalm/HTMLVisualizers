
using Test
using Colors
using HTMLVisualizers: SparseMatrixCell, SparseMatrixSpec, vega_spec,
                       colormap_cell_color, matrix_cells_from_values

# Intentionally trivial — dependency-free and easy to reason about.
gradient(t) = RGB(Float64(t), 0.0, 1.0 - Float64(t))    # 0 → blue, 1 → red

const TRIPLES = [
    (row="r1", column="c1", value = 0.0),
    (row="r1", column="c2", value = 1.0),
    (row="r1", column="c3", value = 0.5),
    (row="r2", column="c1", value = -0.5),
    (row="r2", column="c2", value =  1.5),
    (row="r2", column="c3", value = NaN),
    (row="r3", column="c1", value = nothing),
    (row="r3", column="c2", value = missing),
]

const PALETTE = (
    color_low     = colorant"black",
    color_high    = colorant"white",
    color_nan     = colorant"magenta",
    color_nothing = colorant"gray50",
    color_missing = colorant"gray80",
)

@testset "sparse_matrix_helpers" begin

    @testset "colormap_cell_color branch coverage" begin
        kw = (; colormap = gradient,
                value_low = 0.0, value_high = 1.0,
                color_low = PALETTE.color_low,
                color_high = PALETTE.color_high,
                color_nan = PALETTE.color_nan)
        @test colormap_cell_color(NaN;  kw...) === PALETTE.color_nan
        @test colormap_cell_color(-0.5; kw...) === PALETTE.color_low
        @test colormap_cell_color(1.5;  kw...) === PALETTE.color_high
        # Boundaries go through the colormap, not through color_low/high.
        @test colormap_cell_color(0.0; kw...) == RGB(0.0, 0.0, 1.0)
        @test colormap_cell_color(1.0; kw...) == RGB(1.0, 0.0, 0.0)
        @test colormap_cell_color(0.5; kw...) == RGB(0.5, 0.0, 0.5)
    end

    @testset "matrix_cells_from_values batch with full palette" begin
        cells = matrix_cells_from_values(TRIPLES;
            colormap = gradient,
            value_low = 0.0, value_high = 1.0,
            color_low = PALETTE.color_low,
            color_high = PALETTE.color_high,
            color_nan = PALETTE.color_nan,
            color_nothing = PALETTE.color_nothing,
            color_missing = PALETTE.color_missing)

        @test cells isa Vector{SparseMatrixCell}
        @test length(cells) == 8

        expected_colors = [
            gradient(0.0),             # 0.0
            gradient(1.0),             # 1.0
            gradient(0.5),             # 0.5
            PALETTE.color_low,         # -0.5
            PALETTE.color_high,        # 1.5
            PALETTE.color_nan,         # NaN
            PALETTE.color_nothing,     # nothing
            PALETTE.color_missing,     # missing
        ]
        for (i, c) in enumerate(cells)
            @test c.color == expected_colors[i]
            @test c.row == TRIPLES[i].row
            @test c.column == TRIPLES[i].column
        end

        # Value preservation — use appropriate equality per type.
        @test cells[1].value == 0.0
        @test cells[2].value == 1.0
        @test cells[3].value == 0.5
        @test cells[4].value == -0.5
        @test cells[5].value == 1.5
        @test isnan(cells[6].value)                # NaN != NaN
        @test cells[7].value === nothing
        @test cells[8].value === missing
    end

    @testset "Defaulting of color_nothing / color_missing to color_nan" begin
        cells = matrix_cells_from_values(
            [(row="r", column="c", value=nothing),
             (row="r", column="c2", value=missing)];
            colormap = gradient,
            value_low = 0.0, value_high = 1.0,
            color_low = PALETTE.color_low,
            color_high = PALETTE.color_high,
            color_nan = PALETTE.color_nan)
        @test cells[1].color == PALETTE.color_nan
        @test cells[2].color == PALETTE.color_nan
    end

    @testset "End-to-end with SparseMatrixSpec / vega_spec" begin
        cells = matrix_cells_from_values(TRIPLES;
            colormap = gradient,
            value_low = 0.0, value_high = 1.0,
            color_low = PALETTE.color_low,
            color_high = PALETTE.color_high,
            color_nan = PALETTE.color_nan,
            color_nothing = PALETTE.color_nothing,
            color_missing = PALETTE.color_missing)
        spec = SparseMatrixSpec(cells; title="colormap end-to-end")
        v = vega_spec(spec)

        cells_data = only(d for d in v["data"] if d["name"] == "cellData")["values"]
        by_key = Dict((d["row"], d["column"]) => d for d in cells_data)

        # Float/finite values → "value" key present, equal to input
        for t in TRIPLES[1:5]
            d = by_key[(t.row, t.column)]
            @test d["value"] == t.value
        end
        # Sentinels → no "value" key
        for t in TRIPLES[6:8]
            d = by_key[(t.row, t.column)]
            @test !haskey(d, "value")
        end

        # Hex strings on each cell match the expected palette color
        expected_colors = [gradient(0.0), gradient(1.0), gradient(0.5),
                           PALETTE.color_low, PALETTE.color_high,
                           PALETTE.color_nan, PALETTE.color_nothing,
                           PALETTE.color_missing]
        for (i, t) in enumerate(TRIPLES)
            d = by_key[(t.row, t.column)]
            @test d["color"] == "#" * Colors.hex(expected_colors[i])
        end

        # Cells mark tooltip encoding references both anyDragging and datum.value
        cells_mark = only(m for m in v["marks"]
                          if get(m, "name", nothing) == "cells")
        tt = cells_mark["encode"]["update"]["tooltip"]["signal"]
        @test occursin("anyDragging", tt)
        @test occursin("datum.value", tt)
    end

    @testset "Non-default value_low / value_high normalization" begin
        kw = (; colormap = gradient,
                value_low = -10.0, value_high = 10.0,
                color_low = PALETTE.color_low,
                color_high = PALETTE.color_high,
                color_nan = PALETTE.color_nan)
        # 0.0 sits at t = 0.5 when the range is [-10, 10]
        @test colormap_cell_color(0.0; kw...) == RGB(0.5, 0.0, 0.5)
        @test colormap_cell_color(-10.0; kw...) == RGB(0.0, 0.0, 1.0)
        @test colormap_cell_color(10.0; kw...)  == RGB(1.0, 0.0, 0.0)
        @test colormap_cell_color(-10.001; kw...) === PALETTE.color_low
    end

end
