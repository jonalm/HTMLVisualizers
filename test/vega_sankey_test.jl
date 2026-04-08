
using Test
using HTMLVisualizers: Edge, Node, compute_stacks, nodes_from_edges

@testset "Sankey Module Tests" begin

    @testset "Edge construction" begin
        e = Edge("A", "B", 100.5)
        @test e.source == "A"
        @test e.destination == "B"
        @test e.value == 100.5
    end

    @testset "Node construction" begin
        n = Node("Test", 1)
        @test n.id == "Test"
        @test n.stack == 1
        @test isnothing(n.sort)

        n2 = Node("Test2", 2; sort=1, labels="left", gap=10)
        @test n2.sort == 1
        @test n2.labels == "left"
        @test n2.gap == 10
    end

    @testset "compute_stacks delegates to longest_path_layers" begin
        # Thin wrapper: one sanity check is enough — the layering algorithm
        # itself is exercised in utils_test.jl.
        edges = [Edge("A", "B", 1), Edge("A", "C", 1), Edge("B", "D", 1), Edge("C", "D", 1)]
        stacks = compute_stacks(["A", "B", "C", "D"], edges)
        @test stacks == Dict("A" => 1, "B" => 2, "C" => 2, "D" => 3)
    end

    @testset "nodes_from_edges" begin
        edges = [Edge("X", "Y", 10), Edge("Y", "Z", 10)]
        nodes = nodes_from_edges(edges)
        @test length(nodes) == 3

        node_dict = Dict(n.id => n for n in nodes)
        @test node_dict["X"].stack == 1
        @test node_dict["Y"].stack == 2
        @test node_dict["Z"].stack == 3
        @test node_dict["X"].labels == "left"  # First stack gets left labels
    end

end
