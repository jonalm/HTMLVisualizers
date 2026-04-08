
using Test
using HTMLVisualizers: SankeyEdge, SankeySpec, svg

@testset "vega_general" begin

    @testset "svg pipes through vg2svg" begin
        if isnothing(Sys.which("vg2svg"))
            @test_skip "vg2svg not on PATH (install via `npm install -g vega-cli`)"
        else
            spec = SankeySpec([SankeyEdge("A", "B", 1), SankeyEdge("B", "C", 2)]; title="smoke")
            out = svg(spec)
            @test startswith(strip(out), "<svg")
            @test occursin("</svg>", out)
        end
    end

end
