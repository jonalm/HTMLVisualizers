
using Test
using Colors
using HTMLVisualizers
using HTMLVisualizers: cell_to_hex_dict, derive_orderings, vega_spec

@testset "SparseMatrixSpec tests" begin

    @testset "Construction from NamedTuple vector (bridge ctor)" begin
        cells = [
            (row="r1", column="c1", color=colorant"red", value=1.0),
            (column="c2", row="r1", color=colorant"green"),       # scrambled field order, no value
            (row="r2", column="c1", value="tag", color=colorant"blue"),
        ]
        spec = SparseMatrixSpec(cells)
        @test length(spec.cells) == 3
        @test spec.cells[1].row == "r1" && spec.cells[1].column == "c1"
        @test spec.cells[1].value == 1.0
        @test spec.cells[2].value === nothing
        @test spec.cells[3].value == "tag"
    end

    @testset "Construction from SparseMatrixCell vector" begin
        cells = [
            SparseMatrixCell(row="r1", column="c1", color=colorant"red"),
            SparseMatrixCell(row="r1", column="c2", color=colorant"green", value=42),
        ]
        spec = SparseMatrixSpec(cells)
        @test spec.cells[1] isa SparseMatrixCell
        @test spec.cells[2].value == 42
    end

    @testset "Value defaulting and preservation" begin
        c0 = SparseMatrixCell(row="r", column="c", color=colorant"red")
        @test c0.value === nothing
        c1 = SparseMatrixCell(row="r", column="c", color=colorant"red", value=1.5)
        @test c1.value == 1.5
    end

    @testset "NamedTuple missing :color fills from config.default_color" begin
        config = SparseMatrixConfig(default_color=colorant"orange")
        spec = SparseMatrixSpec([(row="a", column="x")]; config=config)
        hex = "#" * Colors.hex(config.default_color)
        @test cell_to_hex_dict(spec.cells[1])["color"] == hex
    end

    @testset "Default orderings match first-seen order" begin
        cells = [
            (row="B", column="y", color=colorant"red"),
            (row="A", column="x", color=colorant"red"),
            (row="B", column="x", color=colorant"red"),
        ]
        spec = SparseMatrixSpec(cells)
        @test spec.row_order == ["B", "A"]
        @test spec.column_order == ["y", "x"]
    end

    @testset "Override orderings: explicit first, then appended" begin
        cells = [
            (row="A", column="x", color=colorant"red"),
            (row="B", column="y", color=colorant"red"),
            (row="C", column="z", color=colorant"red"),
        ]
        spec = SparseMatrixSpec(cells;
                                row_order=["C", "A"],
                                column_order=["z"])
        @test spec.row_order == ["C", "A", "B"]
        @test spec.column_order == ["z", "x", "y"]
    end

    @testset "Unknown override names dropped silently" begin
        cells = [(row="A", column="x", color=colorant"red")]
        spec = SparseMatrixSpec(cells; row_order=["ghost", "A"],
                                        column_order=["nope"])
        @test spec.row_order == ["A"]
        @test spec.column_order == ["x"]
    end

    @testset "Empty cells vector produces valid spec" begin
        spec = SparseMatrixSpec(SparseMatrixCell[])
        @test isempty(spec.cells)
        @test spec.row_order == String[]
        @test spec.column_order == String[]
        v = vega_spec(spec)
        @test v isa Dict{String,Any}
    end

    @testset "Duplicate (row, column) — last cell wins with warning" begin
        cells = [
            (row="r", column="c", color=colorant"red",   value=1),
            (row="r", column="c", color=colorant"green", value=2),
        ]
        spec = @test_logs (:warn, r"Duplicate") SparseMatrixSpec(cells)
        @test length(spec.cells) == 1
        @test spec.cells[1].value == 2
        @test cell_to_hex_dict(spec.cells[1])["color"] == "#" * Colors.hex(colorant"green")
    end

    @testset "cell_to_hex_dict color conversions" begin
        d_named = cell_to_hex_dict(
            SparseMatrixCell(row="r", column="c", color=colorant"red"))
        @test d_named["color"] == "#FF0000"

        d_rgb = cell_to_hex_dict(
            SparseMatrixCell(row="r", column="c", color=RGB(0.0, 1.0, 0.0)))
        @test d_rgb["color"] == "#" * Colors.hex(RGB(0.0, 1.0, 0.0))

        d_rgba = cell_to_hex_dict(
            SparseMatrixCell(row="r", column="c", color=RGBA(0.2, 0.4, 0.6, 0.5)))
        @test startswith(d_rgba["color"], "#")
    end

    @testset "cell_to_hex_dict omits :value for sentinels" begin
        mk(v) = cell_to_hex_dict(
            SparseMatrixCell(row="r", column="c", color=colorant"red", value=v))
        @test !haskey(mk(nothing),  "value")
        @test !haskey(mk(missing),  "value")
        @test !haskey(mk(NaN),      "value")
        @test !haskey(mk(NaN32),    "value")
        # Present for real data
        @test mk(0.0)["value"] == 0.0
        @test mk(42)["value"] == 42
        @test mk("hi")["value"] == "hi"
        @test mk(Inf)["value"] == Inf          # Inf is a real number, not a sentinel
    end

    @testset "derive_orderings helper" begin
        cells = [
            SparseMatrixCell(row="r1", column="c1", color=colorant"red"),
            SparseMatrixCell(row="r2", column="c1", color=colorant"red"),
            SparseMatrixCell(row="r1", column="c2", color=colorant"red"),
        ]
        rows, cols = derive_orderings(cells, String[], String[])
        @test rows == ["r1", "r2"]
        @test cols == ["c1", "c2"]

        rows2, cols2 = derive_orderings(cells, ["r2"], ["c2", "ghost"])
        @test rows2 == ["r2", "r1"]
        @test cols2 == ["c2", "c1"]
    end

    @testset "vega_spec shape and drag wiring" begin
        cells = [
            (row="r1", column="c1", color=colorant"red",   value=1.0),
            (row="r2", column="c2", color=colorant"green"),
        ]
        spec = SparseMatrixSpec(cells; title="t")
        v = vega_spec(spec)

        # Top-level
        @test v isa Dict{String,Any}
        @test v["title"]["text"] == "t"

        # Signals
        sig_names = Set(s["name"] for s in v["signals"])
        for req in ("rowSrc","rowDest","rowActive",
                    "colSrc","colDest","colActive","anyDragging")
            @test req in sig_names
        end

        # rowActive listens to both label and cell events
        row_active = only(s for s in v["signals"] if s["name"] == "rowActive")
        events = [h["events"] for h in row_active["on"]]
        @test any(occursin("@rowLabels", e) for e in events)
        @test any(occursin("@cells",     e) for e in events)

        col_active = only(s for s in v["signals"] if s["name"] == "colActive")
        col_events = [h["events"] for h in col_active["on"]]
        @test any(occursin("@colLabels", e) for e in col_events)
        @test any(occursin("@cells",     e) for e in col_events)

        # Data tables
        data_names = Set(d["name"] for d in v["data"])
        @test "rowIndex" in data_names
        @test "colIndex" in data_names
        @test "cellData" in data_names

        # Both scales sort by i
        scale_names = Dict(s["name"] => s for s in v["scales"])
        @test scale_names["xScale"]["domain"]["sort"]["field"] == "i"
        @test scale_names["yScale"]["domain"]["sort"]["field"] == "i"

        # Cell mark named "cells" with tooltip referencing both anyDragging and
        # datum.value.
        cells_mark = only(m for m in v["marks"]
                          if get(m, "name", nothing) == "cells")
        tt = cells_mark["encode"]["update"]["tooltip"]["signal"]
        @test occursin("anyDragging", tt)
        @test occursin("datum.value", tt)
    end

end
