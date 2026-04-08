

"""
    vega_spec(spec::VegaVisualizerSpec)::Dict{String, Any}

returns vega spec into a dict.
"""
function vega_spec end


"""
    svg(spec::VegaVisualizerSpec)::String

Render `spec` to an SVG string by piping its Vega JSON through the external
`vg2svg` command (from the `vega-cli` npm package — install with
`npm install -g vega-cli`). Throws if `vg2svg` is not on `PATH`.
"""
function svg(spec::VegaVisualizerSpec)::String
    vspec_json = JSON.json(vega_spec(spec))
    read(pipeline(`vg2svg`, stdin=IOBuffer(vspec_json)), String)
end


"""
    html(spec::VegaVisualizerSpec)::String

Render any Vega-based spec to a self-contained HTML page that embeds the
compiled Vega chart via `vega-embed`. The page `<title>` is pulled from the
vega spec's `title.text` field, falling back to `"Visualization"`.
"""
function html(spec::VegaVisualizerSpec)::String
    vspec = vega_spec(spec)
    page_title = get(get(vspec, "title", Dict()), "text", "")
    isempty(page_title) && (page_title = "Visualization")
    page_title = replace(page_title, "&" => "&amp;", "<" => "&lt;")
    # Escape `</` as `<\/` so a string inside the JSON payload can't terminate
    # the surrounding <script> block. `<\/` parses identically to `</` in JSON.
    config_json = replace(JSON.json(vspec), "</" => "<\\/")

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>$(page_title)</title>
      <script src="https://cdn.jsdelivr.net/npm/vega@5"></script>
      <script src="https://cdn.jsdelivr.net/npm/vega-embed@6"></script>
      <style>
        body {
          font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
          margin: 0;
          padding: 20px;
          background: #f5f5f5;
          display: flex;
          justify-content: center;
          align-items: center;
          min-height: 100vh;
        }
        #vis {
          background: white;
          border-radius: 8px;
          box-shadow: 0 2px 10px rgba(0,0,0,0.1);
          padding: 20px;
        }
      </style>
    </head>
    <body>
      <div id="vis"></div>
      <script>
        const spec = $(config_json);
        vegaEmbed('#vis', spec, {
          renderer: 'svg',
          actions: { export: true, source: false, compiled: false, editor: true }
        }).catch(console.error);
      </script>
    </body>
    </html>
    """
end
