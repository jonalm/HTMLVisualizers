
using Test
using HTMLVisualizers: longest_path_layers

@testset "utils" begin

    @testset "longest_path_layers - linear chain" begin
        # A -> B -> C -> D
        nodes = ["A", "B", "C", "D"]
        edges = [("A", "B"), ("B", "C"), ("C", "D")]
        layers = longest_path_layers(nodes, edges)
        @test layers["A"] == 1
        @test layers["B"] == 2
        @test layers["C"] == 3
        @test layers["D"] == 4
    end

    @testset "longest_path_layers - diamond" begin
        # A -> B, A -> C, B -> D, C -> D
        nodes = ["A", "B", "C", "D"]
        edges = [("A", "B"), ("A", "C"), ("B", "D"), ("C", "D")]
        layers = longest_path_layers(nodes, edges)
        @test layers["A"] == 1
        @test layers["B"] == 2
        @test layers["C"] == 2
        @test layers["D"] == 3
    end

    @testset "longest_path_layers - longest path wins" begin
        # Short path A -> D (length 1) vs long path A -> B -> C -> D (length 3).
        # D must land on the longer path's layer.
        nodes = ["A", "B", "C", "D"]
        edges = [("A", "D"), ("A", "B"), ("B", "C"), ("C", "D")]
        layers = longest_path_layers(nodes, edges)
        @test layers["A"] == 1
        @test layers["B"] == 2
        @test layers["C"] == 3
        @test layers["D"] == 4
    end

    @testset "longest_path_layers - multiple sources" begin
        # S1 -> M, S2 -> M -> T, plus a standalone source S3 -> T
        nodes = ["S1", "S2", "S3", "M", "T"]
        edges = [("S1", "M"), ("S2", "M"), ("M", "T"), ("S3", "T")]
        layers = longest_path_layers(nodes, edges)
        @test layers["S1"] == 1
        @test layers["S2"] == 1
        @test layers["S3"] == 1
        @test layers["M"] == 2
        @test layers["T"] == 3  # longer path S1/S2 -> M -> T wins over S3 -> T
    end

    @testset "longest_path_layers - isolated nodes" begin
        # X has no edges at all, Y has one incoming edge.
        nodes = ["X", "A", "Y"]
        edges = [("A", "Y")]
        layers = longest_path_layers(nodes, edges)
        @test layers["X"] == 1   # isolated node defaults to layer 1
        @test layers["A"] == 1
        @test layers["Y"] == 2
    end

    @testset "longest_path_layers - no edges" begin
        nodes = ["A", "B", "C"]
        layers = longest_path_layers(nodes, Tuple{String,String}[])
        @test layers["A"] == 1
        @test layers["B"] == 1
        @test layers["C"] == 1
    end

    @testset "longest_path_layers - integer node ids" begin
        # Confirm the generic parameter T works for non-String ids.
        nodes = [1, 2, 3, 4]
        edges = [(1, 2), (2, 3), (1, 4), (4, 3)]
        layers = longest_path_layers(nodes, edges)
        @test layers[1] == 1
        @test layers[2] == 2
        @test layers[4] == 2
        @test layers[3] == 3
    end

    @testset "longest_path_layers - accepts Pair edges" begin
        # Iterator of Pairs should be accepted alongside tuples.
        nodes = ["A", "B", "C"]
        edges = ["A" => "B", "B" => "C"]
        layers = longest_path_layers(nodes, edges)
        @test layers["A"] == 1
        @test layers["B"] == 2
        @test layers["C"] == 3
    end

    @testset "longest_path_layers - result covers every node" begin
        nodes = ["A", "B", "C", "D", "E"]
        edges = [("A", "B"), ("B", "C")]
        layers = longest_path_layers(nodes, edges)
        @test Set(keys(layers)) == Set(nodes)
        @test all(v >= 1 for v in values(layers))
    end

end
