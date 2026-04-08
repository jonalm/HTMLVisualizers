
using Test
using HTMLVisualizers: SankeyEdge, SankeyNode, SankeyConfig, SankeySpec, html

const DATA_DIR = joinpath(@__DIR__, "data")

# Reproduce the Microsoft FY23 Q2 Income Statement Sankey
function create_microsoft_sankey()
    nodes = [
        # Stack 1: Revenue sources (left labels)
        SankeyNode("Server Products & Cloud", 1; sort=1, labels="left"),
        SankeyNode("Enterprise Services", 1; sort=2, labels="left", gap=20),
        SankeyNode("Office Products", 1; sort=3, labels="left"),
        SankeyNode("LinkedIn", 1; sort=4, labels="left"),
        SankeyNode("Other", 1; sort=5, labels="left"),
        SankeyNode("Windows", 1; sort=6, labels="left"),
        SankeyNode("Gaming", 1; sort=7, labels="left"),
        SankeyNode("Search & News Advertising", 1; sort=8, labels="left"),
        SankeyNode("Devices", 1; sort=9, labels="left"),
        # Stack 2: Segments
        SankeyNode("Intelligent Cloud", 2; sort=1),
        SankeyNode("Productivity", 2; sort=2),
        SankeyNode("Personal Computing", 2; sort=3),
        # Stack 3: Total Revenue
        SankeyNode("Revenue", 3),
        # Stack 4: Gross split
        SankeyNode("Gross Profit", 4; sort=1, gap=30),
        SankeyNode("Cost of Revenue", 4; sort=2, gap=30),
        # Stack 5: Operating split
        SankeyNode("Operating Profit", 5; sort=1, gap=60),
        SankeyNode("Operating Expenses", 5; sort=2, gap=30),
        SankeyNode("Product Costs", 5; sort=3, gap=20),
        SankeyNode("Service Costs", 5; sort=4, gap=20),
        # Stack 6: Final breakdown
        SankeyNode("Net Profit", 6; sort=1, gap=0),
        SankeyNode("Tax", 6; sort=2, gap=0),
        SankeyNode("R&D", 6; sort=3, gap=20),
        SankeyNode("S&M", 6; sort=4, gap=0),
        SankeyNode("G&A", 6; sort=5, gap=0),
    ]

    edges = [
        # Sources -> Segments
        SankeyEdge("Server Products & Cloud", "Intelligent Cloud", 19.6),
        SankeyEdge("Enterprise Services", "Intelligent Cloud", 1.9),
        SankeyEdge("Office Products", "Productivity", 11.8),
        SankeyEdge("LinkedIn", "Productivity", 3.9),
        SankeyEdge("Other", "Productivity", 1.3),
        SankeyEdge("Windows", "Personal Computing", 4.8),
        SankeyEdge("Gaming", "Personal Computing", 4.8),
        SankeyEdge("Search & News Advertising", "Personal Computing", 3.2),
        SankeyEdge("Devices", "Personal Computing", 1.4),
        # Segments -> Revenue
        SankeyEdge("Intelligent Cloud", "Revenue", 21.5),
        SankeyEdge("Productivity", "Revenue", 17.0),
        SankeyEdge("Personal Computing", "Revenue", 14.2),
        # Revenue -> Gross split
        SankeyEdge("Revenue", "Gross Profit", 35.2),
        SankeyEdge("Revenue", "Cost of Revenue", 17.5),
        # Gross Profit -> Operating
        SankeyEdge("Gross Profit", "Operating Profit", 20.4),
        SankeyEdge("Gross Profit", "Operating Expenses", 14.8),
        # Cost of Revenue -> Costs breakdown
        SankeyEdge("Cost of Revenue", "Product Costs", 5.7),
        SankeyEdge("Cost of Revenue", "Service Costs", 11.8),
        # Operating Profit -> Final
        SankeyEdge("Operating Profit", "Net Profit", 16.4),
        SankeyEdge("Operating Profit", "Tax", 3.9),
        # Operating Expenses -> Expense categories
        SankeyEdge("Operating Expenses", "R&D", 6.8),
        SankeyEdge("Operating Expenses", "S&M", 5.7),
        SankeyEdge("Operating Expenses", "G&A", 2.3),
    ]

    return nodes, edges
end

@testset "Sankey  HTML regression" begin
    # Each case generates output into the system tempdir and compares it
    # byte-for-byte to a reference file checked in under test/data/.
    # If a rendering change is intentional, regenerate the reference file
    # from the same inputs and commit it.

    @testset "Microsoft FY23 Q2 (explicit nodes)" begin
        nodes, edges = create_microsoft_sankey()
        config = SankeyConfig(
            width=1000,
            height=800,
            title_color="#005ca5",
            title_fontsize=32,
            background="#fafafa",
        )
        spec = SankeySpec(nodes, edges;
                          title="Microsoft's FY23 Q2 Income Statement",
                          config=config)

        reference_path = joinpath(DATA_DIR, "sankey_generated.html")
        @test html(spec) == read(reference_path, String)
    end

    @testset "Simple budget (edges only)" begin
        simple_edges = [
            SankeyEdge("Income", "Savings", 30),
            SankeyEdge("Income", "Expenses", 70),
            SankeyEdge("Expenses", "Rent", 40),
            SankeyEdge("Expenses", "Food", 20),
            SankeyEdge("Expenses", "Other", 10),
        ]
        spec = SankeySpec(simple_edges; title="Simple Budget")

        reference_path = joinpath(DATA_DIR, "sankey_simple.html")
        @test html(spec) == read(reference_path, String)
    end
end
