# Generic SVG-spec helpers shared by all `SVGVisualizerSpec` subtypes.

"""
    escape_xml(s::AbstractString) -> String

Escape the five XML special characters (`&`, `<`, `>`, `"`, `'`) so that
`s` can be safely interpolated into SVG `<text>` content or attribute
values. `&` is replaced first so subsequent escapes don't double-escape.
"""
function escape_xml(s::AbstractString)
    out = replace(s, "&" => "&amp;")
    out = replace(out, "<" => "&lt;")
    out = replace(out, ">" => "&gt;")
    out = replace(out, "\"" => "&quot;")
    out = replace(out, "'" => "&#39;")
    return out
end

"""
    page_title(spec::SVGVisualizerSpec) -> String

Return the `<title>` text used by the generic `html(::SVGVisualizerSpec)`
wrapper. Default is empty; concrete subtypes that carry a title field
should override this.
"""
page_title(::SVGVisualizerSpec) = ""

"""
    html(spec::SVGVisualizerSpec) -> String

Wrap the subtype's SVG output in a minimal, self-contained HTML page.
The page mirrors the centered, shadowed card style used by the Vega
wrapper, but without any JS runtime or CDN dependencies.
"""
function html(spec::SVGVisualizerSpec)
    title = page_title(spec)
    isempty(title) && (title = "Visualization")
    title_html = escape_xml(title)
    svg_string = svg(spec)

    """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>$(title_html)</title>
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
      <div id="vis">$(svg_string)</div>
    </body>
    </html>
    """
end
