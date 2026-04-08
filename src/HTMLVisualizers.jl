module HTMLVisualizers

using JSON

export html, svg, open_in_browser, vega_spec,
       SankeyEdge, SankeyNode, SankeyConfig, SankeySpec

include("utils.jl")

# Main API

abstract type HTMLVisualizerSpec end
abstract type VegaVisualizerSpec <: HTMLVisualizerSpec end


"""
    html(spec::HTMLVisualizerSpec)::String

returns the html code of the plot described by `spec` as a `String`.
"""
function html end

"""
    open_in_browser(spec::HTMLVisualizerSpec)

Generates and opens the visualization in the system browser.
"""
function open_in_browser(spec::HTMLVisualizerSpec)
    filepath = tempname() * ".html"
    write(filepath, html(spec))
    open_file(filepath)
    return filepath
end


include("vega_general.jl")
include("vega_sankey.jl")

export 
    html, 
    open_in_browser,
    svg, 
    SankeySpec,
    SankeyNode,
    SankeyEdge,
    SankeyConfig

end # module HTMLVisualizers
