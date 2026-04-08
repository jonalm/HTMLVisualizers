
using Test
using HTMLVisualizers: Edge, Node, SankeyConfig, SankeySpec, html

const DATA_DIR = joinpath(@__DIR__, "data")

# Reproduce the Microsoft FY23 Q2 Income Statement Sankey
function create_microsoft_sankey()
    nodes = [
        # Stack 1: Revenue sources (left labels)
        Node("Server Products & Cloud", 1; sort=1, labels="left"),
        Node("Enterprise Services", 1; sort=2, labels="left", gap=20),
        Node("Office Products", 1; sort=3, labels="left"),
        Node("LinkedIn", 1; sort=4, labels="left"),
        Node("Other", 1; sort=5, labels="left"),
        Node("Windows", 1; sort=6, labels="left"),
        Node("Gaming", 1; sort=7, labels="left"),
        Node("Search & News Advertising", 1; sort=8, labels="left"),
        Node("Devices", 1; sort=9, labels="left"),
        # Stack 2: Segments
        Node("Intelligent Cloud", 2; sort=1),
        Node("Productivity", 2; sort=2),
        Node("Personal Computing", 2; sort=3),
        # Stack 3: Total Revenue
        Node("Revenue", 3),
        # Stack 4: Gross split
        Node("Gross Profit", 4; sort=1, gap=30),
        Node("Cost of Revenue", 4; sort=2, gap=30),
        # Stack 5: Operating split
        Node("Operating Profit", 5; sort=1, gap=60),
        Node("Operating Expenses", 5; sort=2, gap=30),
        Node("Product Costs", 5; sort=3, gap=20),
        Node("Service Costs", 5; sort=4, gap=20),
        # Stack 6: Final breakdown
        Node("Net Profit", 6; sort=1, gap=0),
        Node("Tax", 6; sort=2, gap=0),
        Node("R&D", 6; sort=3, gap=20),
        Node("S&M", 6; sort=4, gap=0),
        Node("G&A", 6; sort=5, gap=0),
    ]

    edges = [
        # Sources -> Segments
        Edge("Server Products & Cloud", "Intelligent Cloud", 19.6),
        Edge("Enterprise Services", "Intelligent Cloud", 1.9),
        Edge("Office Products", "Productivity", 11.8),
        Edge("LinkedIn", "Productivity", 3.9),
        Edge("Other", "Productivity", 1.3),
        Edge("Windows", "Personal Computing", 4.8),
        Edge("Gaming", "Personal Computing", 4.8),
        Edge("Search & News Advertising", "Personal Computing", 3.2),
        Edge("Devices", "Personal Computing", 1.4),
        # Segments -> Revenue
        Edge("Intelligent Cloud", "Revenue", 21.5),
        Edge("Productivity", "Revenue", 17.0),
        Edge("Personal Computing", "Revenue", 14.2),
        # Revenue -> Gross split
        Edge("Revenue", "Gross Profit", 35.2),
        Edge("Revenue", "Cost of Revenue", 17.5),
        # Gross Profit -> Operating
        Edge("Gross Profit", "Operating Profit", 20.4),
        Edge("Gross Profit", "Operating Expenses", 14.8),
        # Cost of Revenue -> Costs breakdown
        Edge("Cost of Revenue", "Product Costs", 5.7),
        Edge("Cost of Revenue", "Service Costs", 11.8),
        # Operating Profit -> Final
        Edge("Operating Profit", "Net Profit", 16.4),
        Edge("Operating Profit", "Tax", 3.9),
        # Operating Expenses -> Expense categories
        Edge("Operating Expenses", "R&D", 6.8),
        Edge("Operating Expenses", "S&M", 5.7),
        Edge("Operating Expenses", "G&A", 2.3),
    ]

    return nodes, edges
end

@testset "Sankey golden HTML regression" begin
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
            Edge("Income", "Savings", 30),
            Edge("Income", "Expenses", 70),
            Edge("Expenses", "Rent", 40),
            Edge("Expenses", "Food", 20),
            Edge("Expenses", "Other", 10),
        ]
        spec = SankeySpec(simple_edges; title="Simple Budget")

        reference_path = joinpath(DATA_DIR, "sankey_simple.html")
        @test html(spec) == read(reference_path, String)
    end
end
