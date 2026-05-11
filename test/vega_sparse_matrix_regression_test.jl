
using Test
using Colors
using HTMLVisualizers: SparseMatrixCell, SparseMatrixConfig, SparseMatrixSpec, html

const DATA_DIR = joinpath(@__DIR__, "data")

# Deterministic palette so the JSON embedded in the HTML doesn't shift.
const BASIC_CELLS = [
    (row="A", column="x", color=colorant"red",    value=1.0),
    (row="A", column="y", color=colorant"orange", value=2.0),
    (row="B", column="x", color=colorant"green"),
    (row="C", column="z", color=colorant"blue",   value="tag"),
]

function make_dense_cells()
    rows = ["r1", "r2", "r3", "r4", "r5"]
    cols = ["c1", "c2", "c3", "c4", "c5"]
    palette = [colorant"red", colorant"orange", colorant"gold",
               colorant"green", colorant"blue"]
    cells = NamedTuple[]
    for (i, r) in enumerate(rows), (j, c) in enumerate(cols)
        push!(cells, (row=r, column=c, color=palette[mod1(i + j, length(palette))],
                      value=Float64(i * 10 + j)))
    end
    return cells
end

@testset "Sparse matrix HTML regression" begin

    @testset "basic (no overrides)" begin
        spec = SparseMatrixSpec(BASIC_CELLS; title="sparse basic")
        reference = joinpath(DATA_DIR, "sparse_matrix_basic.html")
        @test html(spec) == read(reference, String)
    end

    @testset "dense 5x5 grid" begin
        spec = SparseMatrixSpec(make_dense_cells(); title="sparse dense 5x5")
        reference = joinpath(DATA_DIR, "sparse_matrix_dense.html")
        @test html(spec) == read(reference, String)
    end

    @testset "row_order only" begin
        spec = SparseMatrixSpec(BASIC_CELLS;
                                title="sparse row_order only",
                                row_order=["C", "A", "B"])
        reference = joinpath(DATA_DIR, "sparse_matrix_row_order_only.html")
        @test html(spec) == read(reference, String)
    end

end
