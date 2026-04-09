"""
    longest_path_layers(nodes::Vector{T}, edges) where T -> Dict{T,Int}

Assign each node to a layer (1-indexed) based on the longest path from a source node
in a directed acyclic graph. Source nodes (those with no incoming edges) are placed
at layer 1. For any edge `(u, v)`, the resulting layers satisfy `layer[v] >= layer[u] + 1`.

# Arguments
- `nodes::Vector{T}`: All node identifiers. Determines the return key set and the order
  in which roots are visited.
- `edges`: Iterable of `(src, dst)` pairs (`Tuple` or `Pair`) where both endpoints appear
  in `nodes`. The graph must be a DAG; cycles are detected and emit a `@warn`, with
  affected nodes left at layer 1.

# Returns
- `Dict{T,Int}` mapping each node id to its layer number.
"""
function longest_path_layers(nodes::Vector{T}, edges) where T
    id_to_idx = Dict(id => i for (i, id) in enumerate(nodes))
    n = length(nodes)

    adj = [Int[] for _ in 1:n]
    indegree = zeros(Int, n)
    for (src, dst) in edges
        u, v = id_to_idx[src], id_to_idx[dst]
        push!(adj[u], v)
        indegree[v] += 1
    end

    dist = ones(Int, n)
    queue = [i for i in 1:n if indegree[i] == 0]

    while !isempty(queue)
        u = pop!(queue)
        for v in adj[u]
            dist[v] = max(dist[v], dist[u] + 1)
            indegree[v] -= 1
            indegree[v] == 0 && push!(queue, v)
        end
    end

    unresolved = findall(>(0), indegree)
    if !isempty(unresolved)
        cycle_ids = [nodes[i] for i in unresolved]
        @warn "longest_path_layers: graph contains a cycle; affected nodes left at layer 1" cycle_nodes=cycle_ids
    end

    Dict(id => dist[i] for (i, id) in enumerate(nodes))
end



"""
    open_file(filepath::String)

Open a file with the system's default application.
"""
function open_file(filepath::String)
    @static if Sys.isapple()
        run(`open $filepath`)
    elseif Sys.iswindows()
        run(`cmd /c start "" $filepath`)
    else
        run(`xdg-open $filepath`)
    end
end
