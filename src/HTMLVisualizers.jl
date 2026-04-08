module HTMLVisualizers

using JSON

export html, view, vega_spec,
       Edge, Node, SankeyConfig, SankeySpec

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
    view(spec::HTMLVisualizerSpec)

Generates and open the visualization in the system browser.
"""
function view(spec::HTMLVisualizerSpec)
    filepath = tempname() * ".html"
    write(filepath, html(spec))
    open_file(filepath)
    return filepath
end


include("vega_general.jl")
include("vega_sankey.jl")



end # module HTMLVisualizers
