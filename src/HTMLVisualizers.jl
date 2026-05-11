module HTMLVisualizers

using JSON

export html, svg, open_in_browser, vega_spec,
       SankeyEdge, SankeyNode, SankeyConfig, SankeySpec,
       SparseMatrixCell, SparseMatrixConfig, SparseMatrixSpec,
       SquareStackTableRow, SquareStackTableColumn,
       SquareStackTableConfig, SquareStackTableSpec

include("utils.jl")

# Main API

abstract type HTMLVisualizerSpec end
abstract type VegaVisualizerSpec <: HTMLVisualizerSpec end
abstract type SVGVisualizerSpec  <: HTMLVisualizerSpec end


"""
    html(spec::HTMLVisualizerSpec)::String

returns the html code of the plot described by `spec` as a `String`.
"""
function html end

"""
    svg(spec::HTMLVisualizerSpec)::String

returns an SVG document for the plot described by `spec` as a `String`.
"""
function svg end

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
include("vega_sparse_matrix.jl")
include("sparse_matrix_helpers.jl")
include("svg_general.jl")
include("svg_square_stack_table.jl")

end # module HTMLVisualizers
