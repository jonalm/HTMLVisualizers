

"""
    vega_spec(spec::VegaVisualizerSpec)::Dict{Any, String}

returns vega spec into a dict.
"""
function vega_spec end


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
    config_json = JSON.json(vspec)

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
