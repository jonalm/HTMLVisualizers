

"""
    SankeyEdge(source, destination, value)

A weighted edge in the Sankey diagram.

# Arguments
- `source::String`: Source node id
- `destination::String`: Destination node id
- `value::Number`: Edge weight (determines thickness of flow)
"""
struct SankeyEdge
    source::String
    destination::String
    value::Number
end
SankeyEdge(tuple) = SankeyEdge(tuple...)

"""
    SankeyNode(id, stack; sort=nothing, labels=nothing, gap=nothing)

A node in the Sankey diagram. Only needed for fine-grained control over layout.

# Arguments
- `id::String`: Unique identifier for the node
- `stack::Int`: Column/layer number (1-indexed, left to right)
- `sort::Union{Int,Nothing}`: Vertical sort order within stack (lower = higher on screen)
- `labels::Union{String,Nothing}`: Label position ("left" or "right")
- `gap::Union{Int,Nothing}`: Extra gap above this node (percentage of domain)
"""
struct SankeyNode
    id::String
    stack::Int
    sort::Union{Int,Nothing}
    labels::Union{String,Nothing}
    gap::Union{Int,Nothing}
end

SankeyNode(id::String, stack::Int; sort=nothing, labels=nothing, gap=nothing) =
    SankeyNode(id, stack, sort, labels, gap)

"""
    SankeyConfig

Styling configuration for a Sankey diagram. Safe to share across multiple
plots — contains no per-plot content (the diagram title lives on `SankeySpec`).
"""
Base.@kwdef struct SankeyConfig
    width::Int = 1000
    height::Int = 800
    title_color::String = "#005ca5"
    title_fontsize::Int = 32
    background::String = "#fafafa"
    color_scheme::String = "category20"
    standard_gap::Int = 14
    padding::NamedTuple{(:top,:right,:bottom,:left), NTuple{4,Int}} = (top=40, right=30, bottom=20, left=20)
end

"""
    SankeySpec(edges::Vector{SankeyEdge}; title="", config=SankeyConfig())
    SankeySpec(nodes::Vector{SankeyNode}, edges::Vector{SankeyEdge}; title="", config=SankeyConfig())

A complete Sankey diagram specification. Pass to `html` or `open_in_browser` to render.
When `nodes` are omitted, they are derived from the edges automatically via
longest-path layering.
"""
struct SankeySpec <: VegaVisualizerSpec
    nodes::Vector{SankeyNode}
    edges::Vector{SankeyEdge}
    title::String
    config::SankeyConfig
end

SankeySpec(nodes::Vector{SankeyNode}, edges::Vector{SankeyEdge};
           title::String="", config::SankeyConfig=SankeyConfig()) =
    SankeySpec(nodes, edges, title, config)

SankeySpec(nodes::Vector{SankeyNode}, edges::Vector{Tuple{String,String,T}};
           title::String="", config::SankeyConfig=SankeyConfig()) where T <: Number =
    SankeySpec(nodes, SankeyEdge.(edges), title, config)

SankeySpec(edges::Vector{SankeyEdge};
           title::String="", config::SankeyConfig=SankeyConfig()) =
    SankeySpec(nodes_from_edges(edges), edges, title, config)

SankeySpec(edges::Vector{Tuple{String,String,T}};
           title::String="", config::SankeyConfig=SankeyConfig()) where {T<:Number} =
    SankeySpec(SankeyEdge.(edges); title, config)


# =============================================================================
# Core internal functions
# =============================================================================

function node_to_dict(node::SankeyNode)
    d = Dict{String,Any}("category" => node.id, "stack" => node.stack)
    !isnothing(node.sort) && (d["sort"] = node.sort)
    !isnothing(node.labels) && (d["labels"] = node.labels)
    !isnothing(node.gap) && (d["gap"] = node.gap)
    return d
end

function edge_to_dict(edge::SankeyEdge)
    Dict{String,Any}(
        "source" => edge.source,
        "destination" => edge.destination,
        "value" => edge.value
    )
end

function generate_vega_data(nodes::Vector{SankeyNode}, edges::Vector{SankeyEdge})
    vcat(node_to_dict.(nodes), edge_to_dict.(edges))
end

function vega_spec(spec::SankeySpec)
    config = spec.config
    input_data = generate_vega_data(spec.nodes, spec.edges)

    Dict{String,Any}(
        "\$schema" => "https://vega.github.io/schema/vega/v5.json",
        "description" => "Sankey Diagram",
        "width" => config.width,
        "height" => config.height,
        "padding" => Dict(
            "top" => config.padding.top,
            "right" => config.padding.right,
            "bottom" => config.padding.bottom,
            "left" => config.padding.left
        ),
        "title" => Dict(
            "text" => spec.title,
            "color" => config.title_color,
            "fontSize" => config.title_fontsize,
            "dy" => 0,
            "fontWeight" => "bold",
            "offset" => 30
        ),
        "background" => config.background,
        "signals" => [
            Dict("name" => "standardGap", "value" => config.standard_gap, "description" => "Gap as a percentage of full domain"),
            Dict("name" => "base", "value" => "center", "description" => "How to stack (center or zero)")
        ],
        "data" => generate_data_transforms(input_data),
        "scales" => generate_scales(config),
        "marks" => generate_marks(),
        "config" => Dict(
            "view" => Dict("stroke" => "transparent"),
            "text" => Dict("fontSize" => 13, "fill" => "#333333")
        )
    )
end

function generate_data_transforms(input_data::Vector)
    [
        Dict{String,Any}("name" => "input", "values" => input_data),
        Dict{String,Any}(
            "name" => "stacks",
            "source" => "input",
            "transform" => [
                Dict("type" => "filter", "expr" => "datum.source != null"),
                Dict("type" => "formula", "as" => "end", "expr" => "['source','destination']"),
                Dict("type" => "formula", "as" => "name", "expr" => "[datum.source, datum.destination]"),
                Dict("type" => "project", "fields" => ["end", "name", "value"]),
                Dict("type" => "flatten", "fields" => ["end", "name"]),
                Dict("type" => "lookup", "from" => "input", "key" => "category",
                     "values" => ["stack", "sort", "gap", "labels"], "fields" => ["name"],
                     "as" => ["stack", "sort", "gap", "labels"]),
                Dict("type" => "aggregate", "fields" => ["value", "stack", "sort", "gap", "labels"],
                     "groupby" => ["end", "name"], "ops" => ["sum", "max", "max", "max", "max"],
                     "as" => ["value", "stack", "sort", "gap", "labels"]),
                Dict("type" => "aggregate", "fields" => ["value", "stack", "sort", "gap", "labels"],
                     "groupby" => ["name"], "ops" => ["max", "max", "max", "max", "max"],
                     "as" => ["value", "stack", "sort", "gap", "labels"]),
                Dict("type" => "formula", "as" => "gap", "expr" => "datum.gap ? datum.gap : 0")
            ]
        ),
        Dict{String,Any}(
            "name" => "maxValue",
            "source" => ["stacks"],
            "transform" => [
                Dict("type" => "aggregate", "fields" => ["value"], "groupby" => ["stack"],
                     "ops" => ["sum"], "as" => ["value"]),
                Dict("type" => "aggregate", "fields" => ["value"], "ops" => ["max"], "as" => ["value"])
            ]
        ),
        Dict{String,Any}(
            "name" => "plottedStacks",
            "source" => ["stacks"],
            "transform" => [
                Dict("type" => "formula", "as" => "spacer",
                     "expr" => "(data('maxValue')[0].value/100)*(standardGap+datum.gap)"),
                Dict("type" => "formula", "as" => "type", "expr" => "['data','spacer']"),
                Dict("type" => "formula", "as" => "spacedValue", "expr" => "[datum.value, datum.spacer]"),
                Dict("type" => "flatten", "fields" => ["type", "spacedValue"]),
                Dict("type" => "stack", "groupby" => ["stack"],
                     "sort" => Dict("field" => "sort", "order" => "descending"),
                     "field" => "spacedValue", "offset" => Dict("signal" => "base")),
                Dict("type" => "formula", "expr" => "((datum.value)/2)+datum.y0", "as" => "yc")
            ]
        ),
        Dict{String,Any}(
            "name" => "finalTable",
            "source" => ["plottedStacks"],
            "transform" => [Dict("type" => "filter", "expr" => "datum.type == 'data'")]
        ),
        Dict{String,Any}(
            "name" => "linkTable",
            "source" => ["input"],
            "transform" => [
                Dict("type" => "filter", "expr" => "datum.source != null"),
                Dict("type" => "lookup", "from" => "finalTable", "key" => "name",
                     "values" => ["y0", "y1", "stack", "sort"], "fields" => ["source"],
                     "as" => ["sourceStacky0", "sourceStacky1", "sourceStack", "sourceSort"]),
                Dict("type" => "lookup", "from" => "finalTable", "key" => "name",
                     "values" => ["y0", "y1", "stack", "sort"], "fields" => ["destination"],
                     "as" => ["destinationStacky0", "destinationStacky1", "destinationStack", "destinationSort"]),
                Dict("type" => "stack", "groupby" => ["source"],
                     "sort" => Dict("field" => "destinationSort", "order" => "descending"),
                     "field" => "value", "offset" => "zero", "as" => ["syi0", "syi1"]),
                Dict("type" => "formula", "expr" => "datum.syi0+datum.sourceStacky0", "as" => "sy0"),
                Dict("type" => "formula", "expr" => "datum.sy0+datum.value", "as" => "sy1"),
                Dict("type" => "stack", "groupby" => ["destination"],
                     "sort" => Dict("field" => "sourceSort", "order" => "descending"),
                     "field" => "value", "offset" => "zero", "as" => ["dyi0", "dyi1"]),
                Dict("type" => "formula", "expr" => "datum.dyi0+datum.destinationStacky0", "as" => "dy0"),
                Dict("type" => "formula", "expr" => "datum.dy0+datum.value", "as" => "dy1"),
                Dict("type" => "formula", "expr" => "((datum.value)/2)+datum.sy0", "as" => "syc"),
                Dict("type" => "formula", "expr" => "((datum.value)/2)+datum.dy0", "as" => "dyc"),
                Dict("type" => "linkpath", "orient" => "horizontal", "shape" => "diagonal",
                     "sourceY" => Dict("expr" => "scale('y', datum.syc)"),
                     "sourceX" => Dict("expr" => "scale('x', toNumber(datum.sourceStack)) + bandwidth('x')"),
                     "targetY" => Dict("expr" => "scale('y', datum.dyc)"),
                     "targetX" => Dict("expr" => "scale('x', datum.destinationStack)")),
                Dict("type" => "formula", "expr" => "range('y')[0]-scale('y', datum.value)", "as" => "strokeWidth")
            ]
        )
    ]
end

function generate_scales(config::SankeyConfig)
    [
        Dict{String,Any}(
            "name" => "x", "type" => "band", "range" => "width",
            "domain" => Dict("data" => "finalTable", "field" => "stack"),
            "paddingInner" => 0.88
        ),
        Dict{String,Any}(
            "name" => "y", "type" => "linear", "range" => "height",
            "domain" => Dict("data" => "finalTable", "field" => "y1"),
            "reverse" => false
        ),
        Dict{String,Any}(
            "name" => "color", "type" => "ordinal",
            "range" => Dict("scheme" => config.color_scheme),
            "domain" => Dict("data" => "stacks", "field" => "name")
        )
    ]
end

function generate_marks()
    [
        # Node rectangles
        Dict{String,Any}(
            "type" => "rect",
            "from" => Dict("data" => "finalTable"),
            "encode" => Dict(
                "update" => Dict(
                    "x" => Dict("scale" => "x", "field" => "stack"),
                    "width" => Dict("scale" => "x", "band" => 1),
                    "y" => Dict("scale" => "y", "field" => "y0"),
                    "y2" => Dict("scale" => "y", "field" => "y1"),
                    "fill" => Dict("scale" => "color", "field" => "name"),
                    "fillOpacity" => Dict("value" => 0.75),
                    "strokeWidth" => Dict("value" => 0),
                    "stroke" => Dict("scale" => "color", "field" => "name")
                ),
                "hover" => Dict(
                    "tooltip" => Dict("signal" => "{'Name': datum.name, 'Value': format(datum.value, ',.2f')}"),
                    "fillOpacity" => Dict("value" => 1)
                )
            )
        ),
        # Flow paths
        Dict{String,Any}(
            "type" => "path",
            "name" => "links",
            "from" => Dict("data" => "linkTable"),
            "clip" => true,
            "encode" => Dict(
                "update" => Dict(
                    "strokeWidth" => Dict("field" => "strokeWidth"),
                    "path" => Dict("field" => "path"),
                    "strokeOpacity" => Dict("signal" => "0.3"),
                    "stroke" => Dict("field" => "destination", "scale" => "color")
                ),
                "hover" => Dict(
                    "strokeOpacity" => Dict("value" => 1),
                    "tooltip" => Dict("signal" => "{'Source': datum.source, 'Destination': datum.destination, 'Value': format(datum.value, ',.2f')}")
                )
            )
        ),
        # Label groups
        Dict{String,Any}(
            "type" => "group",
            "name" => "labelText",
            "zindex" => 1,
            "from" => Dict(
                "facet" => Dict(
                    "data" => "finalTable",
                    "name" => "labelFacet",
                    "groupby" => ["name", "stack", "yc", "value", "labels"]
                )
            ),
            "clip" => false,
            "encode" => Dict(
                "update" => Dict(
                    "strokeWidth" => Dict("value" => 1),
                    "stroke" => Dict("value" => "red"),
                    "x" => Dict("signal" => "datum.labels=='left' ? scale('x', datum.stack)-8 : scale('x', datum.stack) + bandwidth('x') + 8"),
                    "yc" => Dict("scale" => "y", "signal" => "datum.yc"),
                    "width" => Dict("signal" => "0"),
                    "height" => Dict("signal" => "0"),
                    "fillOpacity" => Dict("signal" => "0.1")
                )
            ),
            "marks" => [
                Dict{String,Any}(
                    "type" => "text",
                    "name" => "heading",
                    "from" => Dict("data" => "labelFacet"),
                    "encode" => Dict(
                        "update" => Dict(
                            "x" => Dict("value" => 0),
                            "y" => Dict("value" => -2),
                            "text" => Dict("field" => "name"),
                            "align" => Dict("signal" => "datum.labels=='left' ? 'right' : 'left'"),
                            "fontWeight" => Dict("value" => "normal")
                        )
                    )
                ),
                Dict{String,Any}(
                    "type" => "text",
                    "name" => "amount",
                    "from" => Dict("data" => "labelFacet"),
                    "encode" => Dict(
                        "update" => Dict(
                            "x" => Dict("value" => 0),
                            "y" => Dict("value" => 12),
                            "text" => Dict("signal" => "format(datum.value, ',.2f')"),
                            "align" => Dict("signal" => "datum.labels=='left' ? 'right' : 'left'")
                        )
                    )
                )
            ]
        ),
        # Label background rectangles
        Dict{String,Any}(
            "type" => "rect",
            "from" => Dict("data" => "labelText"),
            "encode" => Dict(
                "update" => Dict(
                    "x" => Dict("field" => "bounds.x1", "offset" => -2),
                    "x2" => Dict("field" => "bounds.x2", "offset" => 2),
                    "y" => Dict("field" => "bounds.y1", "offset" => -2),
                    "y2" => Dict("field" => "bounds.y2", "offset" => 2),
                    "fill" => Dict("value" => "white"),
                    "opacity" => Dict("value" => 0.8),
                    "cornerRadius" => Dict("value" => 4)
                )
            )
        )
    ]
end

# =============================================================================
# Node computation from edges
# =============================================================================

"""
    compute_stacks(node_ids::Vector{String}, edges::Vector{SankeyEdge}) -> Dict{String,Int}

Compute stack (layer) assignments for nodes based on longest path from sources.
Returns a Dict mapping node id to stack number (1-indexed).
"""
function compute_stacks(node_ids::Vector{String}, edges::Vector{SankeyEdge})
    longest_path_layers(node_ids, ((e.source, e.destination) for e in edges))
end

"""
    nodes_from_edges(edges::Vector{SankeyEdge}) -> Vector{SankeyNode}

Create `SankeyNode` objects from edges with automatically computed stacks via longest path.
Within each stack, nodes are sort-ordered by the order in which they first appear
in `edges` (sources before destinations). Nodes on stack 1 get left-aligned labels.
"""
function nodes_from_edges(edges::Vector{SankeyEdge})
    node_ids = unique(vcat([e.source for e in edges], [e.destination for e in edges]))
    stacks = compute_stacks(node_ids, edges)

    sort_in_stack = Dict{String,Int}()
    stack_counts = Dict{Int,Int}()
    for id in node_ids
        s = stacks[id]
        stack_counts[s] = get(stack_counts, s, 0) + 1
        sort_in_stack[id] = stack_counts[s]
    end

    [SankeyNode(id, stacks[id];
          sort=sort_in_stack[id],
          labels=(stacks[id] == 1 ? "left" : nothing))
     for id in node_ids]
end
