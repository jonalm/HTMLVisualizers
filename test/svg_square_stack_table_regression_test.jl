
using Test
using HTMLVisualizers: SquareStackTableRow, SquareStackTableColumn,
                       SquareStackTableConfig, SquareStackTableSpec,
                       svg, html

const SST_DATA_DIR = joinpath(@__DIR__, "data")

# Fixture mirroring the ASCII reference from the design doc, plus a
# free-text comment column to exercise per-column font overrides.
function build_square_stack_table_basic_spec()
    rows = [
        SquareStackTableRow("foo",   ["a", "a", "b", "a", "a"];                          extras=Any[31, ""]),
        SquareStackTableRow("bar",   ["a", "b", "a", "b", "a", "b", "a", "b"];           extras=Any[211, "comment here bla bla"]),
        SquareStackTableRow("baz",   ["a", "a"];                                         extras=Any[32, ""]),
        SquareStackTableRow("bamma", ["b"];                                              extras=Any[53, ""]),
    ]

    cols = [
        SquareStackTableColumn("count", :right),
        SquareStackTableColumn("note",  :left;
            font_family="Georgia, serif", char_width_ratio=0.5),
    ]

    SquareStackTableSpec(rows;
        title="Square stack table — basic",
        label_header="name",
        histogram_header="histogram",
        columns=cols,
        category_colors=Dict("a" => "#4e79a7", "b" => "#f28e2b"),
    )
end

@testset "SquareStackTable HTML regression" begin
    spec = build_square_stack_table_basic_spec()

    @testset "basic fixture" begin
        reference_path = joinpath(SST_DATA_DIR, "square_stack_table_basic.html")
        @test html(spec) == read(reference_path, String)
    end

    @testset "basic fixture SVG only" begin
        reference_path = joinpath(SST_DATA_DIR, "square_stack_table_basic.svg")
        @test svg(spec) == read(reference_path, String)
    end
end

# Fixture exercising max_squares_per_row: one row overshoots the cap and
# wraps onto multiple sub-rows, while shorter rows stay one sub-row tall.
function build_square_stack_table_wrapped_spec()
    rows = [
        SquareStackTableRow("foo",   ["a", "a", "b", "a", "a"];                  extras=Any[5,  ""]),
        SquareStackTableRow("bar",   vcat(fill("a", 7), fill("b", 6));           extras=Any[13, "wraps onto three sub-rows"]),
        SquareStackTableRow("baz",   ["a", "a"];                                  extras=Any[2,  ""]),
        SquareStackTableRow("bamma", ["b"];                                       extras=Any[1,  ""]),
    ]

    cols = [
        SquareStackTableColumn("count", :right),
        SquareStackTableColumn("note",  :left;
            font_family="Georgia, serif", char_width_ratio=0.5),
    ]

    SquareStackTableSpec(rows;
        title="Square stack table — wrapped",
        label_header="name",
        histogram_header="histogram",
        columns=cols,
        category_colors=Dict("a" => "#4e79a7", "b" => "#f28e2b"),
        config=SquareStackTableConfig(max_squares_per_row=5),
    )
end

@testset "SquareStackTable HTML regression — wrapped" begin
    spec = build_square_stack_table_wrapped_spec()

    @testset "wrapped fixture" begin
        reference_path = joinpath(SST_DATA_DIR, "square_stack_table_wrapped.html")
        @test html(spec) == read(reference_path, String)
    end

    @testset "wrapped fixture SVG only" begin
        reference_path = joinpath(SST_DATA_DIR, "square_stack_table_wrapped.svg")
        @test svg(spec) == read(reference_path, String)
    end
end
