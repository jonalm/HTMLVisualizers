
using Test
using HTMLVisualizers: SquareStackTableRow, SquareStackTableColumn,
                       SquareStackTableConfig, SquareStackTableSpec,
                       SVGVisualizerSpec, HTMLVisualizerSpec, svg, html
using HTMLVisualizers: resolve_colors, resolve_legend_order,
                       compute_column_widths, compute_layout,
                       escape_xml, sort_squares_for_render

@testset "SquareStackTable" begin

    @testset "SquareStackTableRow construction" begin
        # Positional: label + squares, default empty extras.
        r = SquareStackTableRow("foo", ["a", "b", "a"])
        @test r.label == "foo"
        @test r.squares == ["a", "b", "a"]
        @test r.extras == Any[]

        # Keyword extras with mixed types.
        r2 = SquareStackTableRow("bar", ["x"]; extras=Any[31, "comment"])
        @test r2.label == "bar"
        @test r2.squares == ["x"]
        @test r2.extras == Any[31, "comment"]

        # Empty squares are allowed (a row with no histogram is legal).
        r3 = SquareStackTableRow("baz", String[])
        @test r3.squares == String[]
    end

    @testset "SquareStackTableConfig defaults" begin
        cfg = SquareStackTableConfig()
        # Typography is monospace + 0.6 char-width ratio (load-bearing for layout).
        @test occursin("monospace", cfg.font_family)
        @test cfg.font_size == 14
        @test cfg.char_width_ratio == 0.6
        # Geometry defaults.
        @test cfg.row_height == 22
        @test cfg.square_size == 14
        @test cfg.square_gap == 4
        @test cfg.column_gap == 20
        # Chrome.
        @test cfg.padding == (top=20, right=20, bottom=20, left=20)
        @test cfg.show_header == true
        @test cfg.show_legend == true
        # Palette is non-empty so auto-assigned colors don't crash on mod1.
        @test !isempty(cfg.palette)

        # Overriding individual fields via kwargs works (Base.@kwdef).
        cfg2 = SquareStackTableConfig(font_size=18, show_header=false)
        @test cfg2.font_size == 18
        @test cfg2.show_header == false
        @test cfg2.row_height == 22  # untouched fields keep defaults
    end

    @testset "SquareStackTableColumn construction" begin
        # Required positional args + default kwargs.
        c = SquareStackTableColumn("count", :right)
        @test c.header == "count"
        @test c.align == :right
        @test isnothing(c.font_family)
        @test isnothing(c.char_width_ratio)

        # Per-column font + ratio overrides.
        c2 = SquareStackTableColumn("comment", :left;
                                    font_family="Inter, sans-serif",
                                    char_width_ratio=0.5)
        @test c2.font_family == "Inter, sans-serif"
        @test c2.char_width_ratio == 0.5

        # Empty header is permitted.
        c3 = SquareStackTableColumn("", :center)
        @test c3.header == ""
        @test c3.align == :center
    end

    @testset "SquareStackTableSpec construction" begin
        rows = [
            SquareStackTableRow("foo", ["a", "a", "b"]),
            SquareStackTableRow("bar", ["a"]; extras=Any[31, "comment"]),
        ]
        cols = [SquareStackTableColumn("count", :right),
                SquareStackTableColumn("note", :left)]

        # Minimal: rows only, everything else default.
        spec_min = SquareStackTableSpec(rows)
        @test spec_min.rows === rows
        @test spec_min.label_header == ""
        @test spec_min.histogram_header == ""
        @test spec_min.columns == SquareStackTableColumn[]
        @test spec_min.category_colors == Dict{String,String}()
        @test spec_min.legend_order == String[]
        @test isnothing(spec_min.label_font_family)
        @test spec_min.title == ""
        @test spec_min.config isa SquareStackTableConfig

        # All kwargs threaded through.
        spec = SquareStackTableSpec(rows;
            title="My table",
            label_header="name",
            histogram_header="hist",
            columns=cols,
            category_colors=Dict("a" => "#111111"),
            legend_order=["b", "a"],
            label_font_family="Inter, sans-serif",
            config=SquareStackTableConfig(font_size=18),
        )
        @test spec.title == "My table"
        @test spec.label_header == "name"
        @test spec.histogram_header == "hist"
        @test spec.columns == cols
        @test spec.category_colors == Dict("a" => "#111111")
        @test spec.legend_order == ["b", "a"]
        @test spec.label_font_family == "Inter, sans-serif"
        @test spec.config.font_size == 18

        # Type hierarchy: SquareStackTableSpec is an SVGVisualizerSpec, which
        # is an HTMLVisualizerSpec.
        @test spec isa SVGVisualizerSpec
        @test spec isa HTMLVisualizerSpec
    end

    @testset "resolve_colors" begin
        # Use a tiny custom palette so we can predict assignments without
        # caring about the default palette length.
        cfg = SquareStackTableConfig(palette=["#aaa", "#bbb", "#ccc"])
        rows = [
            SquareStackTableRow("r1", ["x", "y", "x"]),  # first-seen: x, y
            SquareStackTableRow("r2", ["z", "y"]),       # then z
        ]

        # 1. Pure auto-assignment: x→#aaa, y→#bbb, z→#ccc.
        spec = SquareStackTableSpec(rows; config=cfg)
        colors = resolve_colors(spec)
        @test colors == Dict("x" => "#aaa", "y" => "#bbb", "z" => "#ccc")

        # 2. Explicit overrides win over the palette.
        spec2 = SquareStackTableSpec(rows;
            config=cfg,
            category_colors=Dict("y" => "#yellow", "z" => "#zulu"),
        )
        colors2 = resolve_colors(spec2)
        @test colors2["y"] == "#yellow"
        @test colors2["z"] == "#zulu"
        # x still falls back to the palette — and gets the FIRST palette
        # slot since it was the first auto-assigned (y was overridden, so
        # it consumes no palette slot).
        @test colors2["x"] == "#aaa"

        # 3. category_colors entries with no matching data category are ignored.
        spec3 = SquareStackTableSpec(rows;
            config=cfg,
            category_colors=Dict("x" => "#xxx", "ghost" => "#000"),
        )
        colors3 = resolve_colors(spec3)
        @test !haskey(colors3, "ghost")
        @test colors3["x"] == "#xxx"

        # 4. Palette wraps via mod1 when there are more categories than colors.
        many_rows = [SquareStackTableRow("r", ["a", "b", "c", "d", "e"])]
        spec4 = SquareStackTableSpec(many_rows; config=cfg)
        colors4 = resolve_colors(spec4)
        @test colors4["a"] == "#aaa"
        @test colors4["b"] == "#bbb"
        @test colors4["c"] == "#ccc"
        @test colors4["d"] == "#aaa"  # wraps
        @test colors4["e"] == "#bbb"
    end

    @testset "resolve_legend_order" begin
        rows = [
            SquareStackTableRow("r1", ["x", "y"]),
            SquareStackTableRow("r2", ["z", "y"]),
        ]

        # 1. No explicit order → first-seen order from the data.
        spec = SquareStackTableSpec(rows)
        @test resolve_legend_order(spec) == ["x", "y", "z"]

        # 2. Explicit legend_order is honored. Categories present in the
        #    data but missing from legend_order are appended in first-seen
        #    order.
        spec2 = SquareStackTableSpec(rows; legend_order=["y"])
        @test resolve_legend_order(spec2) == ["y", "x", "z"]

        # 3. Entries in legend_order that don't appear in the data are
        #    dropped (not rendered).
        spec3 = SquareStackTableSpec(rows; legend_order=["ghost", "z", "y"])
        @test resolve_legend_order(spec3) == ["z", "y", "x"]

        # 4. Empty rows → empty legend.
        spec4 = SquareStackTableSpec(SquareStackTableRow[])
        @test resolve_legend_order(spec4) == String[]
    end

    @testset "compute_column_widths" begin
        # Use a config with round numbers so the asserted widths are
        # easy to read: cw_default = 10 * 0.5 = 5, square stride = 12.
        cfg = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            square_size=10, square_gap=2,
        )

        rows = [
            SquareStackTableRow("foo", ["a", "b", "a"]),
            SquareStackTableRow("bargle", ["a"]; extras=Any[42]),
        ]
        cols = [SquareStackTableColumn("count", :right)]

        # 1. Basic case. label content (6) wins over header "x" (1).
        spec = SquareStackTableSpec(rows;
            columns=cols, label_header="x", config=cfg)
        w = compute_column_widths(spec)
        @test w.label_w == 30                # max(1, 6) * 5
        @test w.squares_w == 34              # 3 squares: 3*12 - 2
        @test w.extras_w == [25]             # max("count"=5, "42"=2) * 5

        # 2. show_header=false drops the header term — long header is ignored.
        cfg_nh = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            square_size=10, square_gap=2,
            show_header=false,
        )
        spec_nh = SquareStackTableSpec(rows;
            columns=cols, label_header="very-long-header", config=cfg_nh)
        w_nh = compute_column_widths(spec_nh)
        @test w_nh.label_w == 30             # header ignored, content still 6

        # 3. Long header dominates content when show_header=true.
        spec_lh = SquareStackTableSpec(rows;
            columns=cols, label_header="very-long-header", config=cfg)
        @test compute_column_widths(spec_lh).label_w == 80   # 16 * 5

        # 4. Empty rows → widths come purely from headers.
        spec_empty = SquareStackTableSpec(SquareStackTableRow[];
            columns=cols, label_header="x", config=cfg)
        w_empty = compute_column_widths(spec_empty)
        @test w_empty.label_w == 5           # just "x" * 5
        @test w_empty.squares_w == 0         # no header, no rows
        @test w_empty.extras_w == [25]       # just "count" * 5

        # 5. Empty extras column (no header, no row content) → 0.
        cols_blank = [SquareStackTableColumn("", :left)]
        rows_no_extras = [SquareStackTableRow("foo", ["a"])]
        spec_e = SquareStackTableSpec(rows_no_extras;
            columns=cols_blank, config=cfg)
        @test compute_column_widths(spec_e).extras_w == [0]

        # 6. Per-column char_width_ratio override widens that column.
        cols_wide = [SquareStackTableColumn("ab", :left; char_width_ratio=1.0)]
        spec_wide = SquareStackTableSpec(rows_no_extras;
            columns=cols_wide, config=cfg)
        # cw = 10 * 1.0 = 10, header "ab" len 2 → 20
        @test compute_column_widths(spec_wide).extras_w == [20]

        # 7. Histogram header dominates when no rows have squares.
        rows_no_sq = [SquareStackTableRow("foo", String[])]
        spec_h = SquareStackTableSpec(rows_no_sq;
            histogram_header="hist", config=cfg)
        # hlen("hist") * 5 = 4 * 5 = 20
        @test compute_column_widths(spec_h).squares_w == 20
    end

    @testset "compute_layout" begin
        # Predictable round-number config.
        # cw_default = 10 * 0.5 = 5; square stride = 12; column_gap = 10.
        cfg = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            square_size=10, square_gap=2,
            column_gap=10, row_height=20,
            padding=(top=8, right=8, bottom=8, left=8),
            legend_swatch_size=10, legend_row_height=12,
            legend_gap=2, legend_bottom_margin=4,
        )

        rows = [
            SquareStackTableRow("foo", ["a", "b"]),
            SquareStackTableRow("bargle", ["a"]; extras=Any[42]),
        ]
        cols = [SquareStackTableColumn("count", :right)]
        spec = SquareStackTableSpec(rows;
            columns=cols, label_header="x", config=cfg)

        L = compute_layout(spec)

        # widths come from compute_column_widths.
        @test L.widths.label_w == 30
        @test L.widths.squares_w == 22       # 2*12 - 2
        @test L.widths.extras_w == [25]      # max(5,2)*5

        # Horizontal origins.
        @test L.x0 == 8
        @test L.label_x == 38                # 8 + 30
        @test L.hist_x == 48                 # 38 + 10
        @test L.extras_left[1]  == 80        # 48 + 22 + 10
        @test L.extras_right[1] == 105       # 80 + 25
        @test L.table_right == 105

        # Legend: two distinct categories, each 1 char wide.
        @test L.legend_entries == ["a", "b"]
        @test L.legend_w == 17               # swatch 10 + gap 2 + label 5
        @test L.legend_h == 28               # 2*12 + 4

        # total_width: table_right (105) > x0 + legend_w (8+17) → table wins.
        @test L.total_width == 113           # 105 + padding.right

        # No title → title_h = 0; legend & header sit under padding.top.
        @test L.title_h == 0
        @test L.legend_y0 == 8
        @test L.header_y == 36               # 8 + 28
        @test L.header_h == 20
        @test L.y0 == 56                     # 36 + 20

        # Two data rows of height 20, plus padding.bottom.
        @test L.total_height == 104          # 56 + 40 + 8
    end

    @testset "compute_layout: show_legend=false hides legend block" begin
        cfg = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            row_height=20,
            padding=(top=8, right=8, bottom=8, left=8),
            show_legend=false,
        )
        spec = SquareStackTableSpec(
            [SquareStackTableRow("foo", ["a", "b"])];
            config=cfg,
        )
        L = compute_layout(spec)
        @test L.legend_w == 0
        @test L.legend_h == 0
        # legend_y0 sits at padding.top; header_y has no legend gap to clear.
        @test L.header_y == L.legend_y0
    end

    @testset "compute_layout: empty rows produce empty legend" begin
        cfg = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            row_height=20,
            padding=(top=8, right=8, bottom=8, left=8),
        )
        L = compute_layout(SquareStackTableSpec(SquareStackTableRow[]; config=cfg))
        @test isempty(L.legend_entries)
        @test L.legend_h == 0
        @test L.total_height == L.y0 + cfg.padding.bottom
    end

    @testset "compute_layout: legend wider than table grows total_width" begin
        cfg = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            square_size=10, square_gap=2,
            column_gap=10, row_height=20,
            padding=(top=8, right=8, bottom=8, left=8),
            legend_swatch_size=10, legend_row_height=12,
            legend_gap=2, legend_bottom_margin=4,
        )
        # Tiny table content but very long category name.
        rows = [SquareStackTableRow("x", ["aaaaaaaaaaaaaaaaaaaa"])]   # 20 chars
        spec = SquareStackTableSpec(rows; config=cfg)
        L = compute_layout(spec)
        # legend_w = 10 + 2 + 20*5 = 112; x0 + legend_w = 120
        # table_right = label_w(5) + col_gap(10) + label_x_part... let's
        # just check the invariant rather than the exact number.
        @test L.total_width >= L.x0 + L.legend_w + cfg.padding.right
    end

    @testset "compute_layout: empty extras column is skipped" begin
        cfg = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            square_size=10, square_gap=2,
            column_gap=10, row_height=20,
            padding=(top=8, right=8, bottom=8, left=8),
        )
        cols = [SquareStackTableColumn("", :left)]   # blank header, no row content
        rows = [SquareStackTableRow("foo", ["a"])]
        spec = SquareStackTableSpec(rows; columns=cols, config=cfg)
        L = compute_layout(spec)
        @test isempty(L.extras_left)
        @test isempty(L.extras_right)
        # No extras column means no trailing column_gap is consumed.
        @test L.table_right == L.hist_x + L.widths.squares_w
    end

    @testset "compute_layout: title adds title_h to vertical layout" begin
        cfg = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            row_height=20, title_fontsize=20,
            padding=(top=8, right=8, bottom=8, left=8),
            show_legend=false,
        )
        spec = SquareStackTableSpec(
            [SquareStackTableRow("foo", ["a"])];
            title="hello", config=cfg,
        )
        L = compute_layout(spec)
        @test L.title_h == 30                 # title_fontsize + 10
        @test L.legend_y0 == 8 + 30
    end

    @testset "sort_squares_for_render groups by legend order" begin
        # Basic: interleaved input → grouped output, in legend order.
        @test sort_squares_for_render(["b", "a", "b", "a"], ["a", "b"]) ==
              ["a", "a", "b", "b"]

        # Three categories, mixed.
        @test sort_squares_for_render(["c", "a", "b", "a", "c"], ["a", "b", "c"]) ==
              ["a", "a", "b", "c", "c"]

        # Custom legend order is honored over first-seen.
        @test sort_squares_for_render(["a", "b", "a"], ["b", "a"]) ==
              ["b", "a", "a"]

        # Empty input stays empty regardless of legend order.
        @test sort_squares_for_render(String[], ["a", "b"]) == String[]

        # A single category collapses to itself.
        @test sort_squares_for_render(["a", "a", "a"], ["a"]) == ["a", "a", "a"]
    end

    @testset "svg: squares within a row are grouped by category" begin
        # Disable the legend so the only rects in the output are the
        # background plus the 4 data squares — easy to assert on.
        rows = [SquareStackTableRow("foo", ["b", "a", "b", "a"])]
        spec = SquareStackTableSpec(rows;
            category_colors=Dict("a" => "#aaaaaa", "b" => "#bbbbbb"),
            config=SquareStackTableConfig(show_legend=false))
        out = svg(spec)
        fills = [m.captures[1] for m in eachmatch(r"<rect[^>]*fill=\"(#[a-fA-F0-9]+)\"", out)]
        @test fills[1] == "#ffffff"  # background
        # Categories appear in legend order ("b","a" — first-seen from
        # the data), with all squares of one category contiguous.
        @test fills[2:end] == ["#bbbbbb", "#bbbbbb", "#aaaaaa", "#aaaaaa"]
    end

    @testset "escape_xml" begin
        @test escape_xml("plain") == "plain"
        @test escape_xml("a & b") == "a &amp; b"
        @test escape_xml("<tag>") == "&lt;tag&gt;"
        @test escape_xml("\"q\"") == "&quot;q&quot;"
        # & must be escaped first so the replacements don't double-escape.
        @test escape_xml("&amp;") == "&amp;amp;"
        @test escape_xml("") == ""
    end

    @testset "compute_layout: show_header=false drops header band" begin
        cfg = SquareStackTableConfig(
            font_size=10, char_width_ratio=0.5,
            row_height=20,
            padding=(top=8, right=8, bottom=8, left=8),
            show_header=false, show_legend=false,
        )
        spec = SquareStackTableSpec(
            [SquareStackTableRow("foo", ["a"])];
            config=cfg,
        )
        L = compute_layout(spec)
        @test L.header_h == 0
        @test L.y0 == L.header_y              # no band between header_y and y0
    end

    @testset "svg(::SquareStackTableSpec) emit structure" begin
        # Use defaults for everything geometric — we're checking emit
        # structure (counts, presence of strings, escaping), not pixel
        # numbers.
        rows = [
            SquareStackTableRow("foo", ["a", "b", "a"]),
            SquareStackTableRow("bar", ["c"]; extras=Any[42, "note"]),
        ]
        cols = [
            SquareStackTableColumn("count", :right),
            SquareStackTableColumn("note", :left),
        ]
        spec = SquareStackTableSpec(rows;
            title="My table",
            label_header="name",
            histogram_header="hist",
            columns=cols,
        )
        out = svg(spec)

        # Document framing.
        @test startswith(strip(out), "<svg")
        @test occursin("</svg>", out)
        @test occursin("xmlns=\"http://www.w3.org/2000/svg\"", out)
        @test occursin("viewBox=", out)

        # One <rect> per square + one background rect + one swatch per
        # legend entry.
        n_squares = sum(length(r.squares) for r in rows)             # 3 + 1 = 4
        n_legend  = length(unique(reduce(vcat, [r.squares for r in rows])))  # 3
        n_rects   = count(_ -> true, eachmatch(r"<rect\b", out))
        @test n_rects == n_squares + 1 + n_legend                    # = 8

        # Every row label appears in the output.
        @test occursin(">foo<", out)
        @test occursin(">bar<", out)

        # Title appears.
        @test occursin(">My table<", out)

        # Headers appear when show_header=true (the default).
        @test occursin(">name<", out)
        @test occursin(">hist<", out)
        @test occursin(">count<", out)
        @test occursin(">note<", out)

        # Numeric extras render as their string form.
        @test occursin(">42<", out)
    end

    @testset "svg: title and headers omitted when blank/disabled" begin
        # No title → no title text element. show_header=false → no header texts.
        cfg = SquareStackTableConfig(show_header=false)
        spec = SquareStackTableSpec(
            [SquareStackTableRow("foo", ["a"])];
            label_header="should-not-appear",
            histogram_header="also-not",
            config=cfg,
        )
        out = svg(spec)
        @test !occursin(">should-not-appear<", out)
        @test !occursin(">also-not<", out)
        # And the row label still appears.
        @test occursin(">foo<", out)
    end

    @testset "svg: legend disabled emits no swatches" begin
        cfg = SquareStackTableConfig(show_legend=false)
        spec = SquareStackTableSpec(
            [SquareStackTableRow("foo", ["a", "b"])];
            config=cfg,
        )
        out = svg(spec)
        # Background rect + 2 square rects = 3.
        @test count(_ -> true, eachmatch(r"<rect\b", out)) == 3
    end

    @testset "svg: per-column font overrides land in the output" begin
        rows = [SquareStackTableRow("foo", ["a"]; extras=Any["hello"])]
        cols = [SquareStackTableColumn("note", :left; font_family="Inter, sans-serif")]
        spec = SquareStackTableSpec(rows; columns=cols)
        out = svg(spec)
        # Override appears.
        @test occursin("font-family=\"Inter, sans-serif\"", out)
        # Default monospace stack still drives the histogram header / label.
        @test occursin("monospace", out)
    end

    @testset "svg: label_font_family override applies to label cells" begin
        rows = [SquareStackTableRow("foo", ["a"])]
        spec = SquareStackTableSpec(rows;
            label_header="hdr",
            label_font_family="Georgia, serif",
        )
        out = svg(spec)
        @test occursin("font-family=\"Georgia, serif\"", out)
    end

    @testset "svg: char_width_ratio override widens the column in the SVG" begin
        rows = [SquareStackTableRow("foo", ["a"]; extras=Any["xy"])]
        cfg = SquareStackTableConfig(font_size=10, char_width_ratio=0.5)
        # Same content, two configurations: default ratio vs. 1.0 override.
        narrow = SquareStackTableSpec(rows;
            columns=[SquareStackTableColumn("h", :left)],
            config=cfg)
        wide = SquareStackTableSpec(rows;
            columns=[SquareStackTableColumn("h", :left; char_width_ratio=1.0)],
            config=cfg)
        @test compute_layout(wide).total_width >
              compute_layout(narrow).total_width
    end

    @testset "svg: special chars are escaped" begin
        rows = [SquareStackTableRow("a < b & c", ["x>y"])]
        cols = [SquareStackTableColumn("h<r>", :left)]
        spec = SquareStackTableSpec(rows;
            title="t&t",
            label_header="l<l",
            columns=cols,
        )
        out = svg(spec)
        # Raw <, >, & must not appear in text content.
        @test occursin("a &lt; b &amp; c", out)
        @test occursin("h&lt;r&gt;", out)
        @test occursin("l&lt;l", out)
        @test occursin("t&amp;t", out)
        # And the unescaped versions don't leak through as text.
        @test !occursin(">a < b & c<", out)
    end

    @testset "html(::SquareStackTableSpec) wraps the SVG in a minimal HTML page" begin
        rows = [SquareStackTableRow("foo", ["a"])]
        spec = SquareStackTableSpec(rows; title="My table")
        out = html(spec)
        svg_out = svg(spec)

        @test startswith(out, "<!DOCTYPE html>")
        @test occursin("<html", out)
        @test occursin("</html>", out)
        @test occursin("<title>My table</title>", out)
        # The full SVG document is embedded inline.
        @test occursin(svg_out, out)
        # No JS / CDN dependencies.
        @test !occursin("<script", out)
        @test !occursin("cdn.jsdelivr.net", out)
    end

    @testset "html: blank title falls back to Visualization, escaped" begin
        spec = SquareStackTableSpec([SquareStackTableRow("foo", ["a"])])
        out = html(spec)
        @test occursin("<title>Visualization</title>", out)

        # Title with XML metacharacters is escaped.
        spec2 = SquareStackTableSpec([SquareStackTableRow("foo", ["a"])];
            title="A & B <C>")
        out2 = html(spec2)
        @test occursin("<title>A &amp; B &lt;C&gt;</title>", out2)
    end

    @testset "max_squares_per_row wrapping" begin
        # Round-number config so the asserted pixel coordinates are easy
        # to read: cw_default = 5, square stride = 12, row_height = 20.
        base_cfg(; kwargs...) = SquareStackTableConfig(;
            font_size=10, char_width_ratio=0.5,
            square_size=10, square_gap=2,
            column_gap=10, row_height=20,
            padding=(top=8, right=8, bottom=8, left=8),
            legend_swatch_size=10, legend_row_height=12,
            legend_gap=2, legend_bottom_margin=4,
            kwargs...,
        )

        @testset "config field defaults to nothing" begin
            cfg = SquareStackTableConfig()
            @test isnothing(cfg.max_squares_per_row)
            cfg2 = SquareStackTableConfig(max_squares_per_row=4)
            @test cfg2.max_squares_per_row == 4
        end

        @testset "compute_column_widths: cap shrinks squares_w" begin
            rows = [SquareStackTableRow("r", fill("a", 8))]
            uncapped = SquareStackTableSpec(rows; config=base_cfg())
            capped   = SquareStackTableSpec(rows; config=base_cfg(max_squares_per_row=4))
            wu = compute_column_widths(uncapped)
            wc = compute_column_widths(capped)
            # 8 squares: 8*12 - 2 = 94
            @test wu.squares_w == 94
            @test wu.effective_per_row == 8
            # 4 squares wide: 4*12 - 2 = 46
            @test wc.squares_w == 46
            @test wc.effective_per_row == 4
        end

        @testset "compute_column_widths: cap larger than data is a no-op" begin
            rows = [SquareStackTableRow("r", fill("a", 3))]
            spec = SquareStackTableSpec(rows; config=base_cfg(max_squares_per_row=10))
            w = compute_column_widths(spec)
            @test w.effective_per_row == 3      # min(10, 3)
            @test w.squares_w == 34             # 3*12 - 2
        end

        @testset "compute_column_widths: empty rows yield effective_per_row >= 1" begin
            spec = SquareStackTableSpec(SquareStackTableRow[];
                config=base_cfg(max_squares_per_row=4))
            w = compute_column_widths(spec)
            # No data → no histogram width, but the wrap divisor must
            # still be ≥ 1 so the emit-pass modulo is well-defined.
            @test w.squares_w == 0
            @test w.effective_per_row == 1
        end

        @testset "compute_layout: cap unset → 1 sub-row per data row" begin
            rows = [
                SquareStackTableRow("foo", ["a", "b"]),
                SquareStackTableRow("bar", ["a"]),
            ]
            spec = SquareStackTableSpec(rows; config=base_cfg())
            L = compute_layout(spec)
            @test L.row_sub_rows == [1, 1]
            @test L.row_tops == [L.y0, L.y0 + 20]
            @test L.effective_per_row == 2      # max squares_content
        end

        @testset "compute_layout: cap=4 wraps a 7-square row into 2 sub-rows" begin
            rows = [
                SquareStackTableRow("long",  fill("a", 7)),
                SquareStackTableRow("short", fill("a", 2)),
            ]
            spec = SquareStackTableSpec(rows; config=base_cfg(max_squares_per_row=4))
            L = compute_layout(spec)
            @test L.effective_per_row == 4
            @test L.row_sub_rows == [2, 1]
            @test L.row_tops[1] == L.y0
            @test L.row_tops[2] == L.y0 + 2 * 20
            # 3 sub-rows total of 20 px each, plus padding.bottom (8).
            @test L.total_height == L.y0 + 3 * 20 + 8
            # squares_w sized to the cap (4 columns), not the data (7).
            @test L.widths.squares_w == 4 * 12 - 2
        end

        @testset "compute_layout: empty squares row still gets 1 sub-row" begin
            rows = [
                SquareStackTableRow("a", String[]),
                SquareStackTableRow("b", fill("x", 6)),
            ]
            spec = SquareStackTableSpec(rows; config=base_cfg(max_squares_per_row=3))
            L = compute_layout(spec)
            # 6 squares wrap to 2 sub-rows; the empty row collapses to 1.
            @test L.row_sub_rows == [1, 2]
            @test L.row_tops[2] == L.y0 + 20
        end

        @testset "compute_layout: max_squares_per_row=0 raises" begin
            spec = SquareStackTableSpec(
                [SquareStackTableRow("r", ["a"])];
                config=base_cfg(max_squares_per_row=0),
            )
            @test_throws ArgumentError compute_layout(spec)
            spec_neg = SquareStackTableSpec(
                [SquareStackTableRow("r", ["a"])];
                config=base_cfg(max_squares_per_row=-3),
            )
            @test_throws ArgumentError compute_layout(spec_neg)
        end

        @testset "svg: wrapped row emits squares on multiple sub-rows" begin
            # 7 squares of "a", cap=4 → expect 4 squares on the first
            # sub-row and 3 on the second. Use a single category and
            # disable the legend so all <rect>s are easy to count.
            rows = [SquareStackTableRow("long", fill("a", 7))]
            cfg  = base_cfg(max_squares_per_row=4, show_legend=false)
            spec = SquareStackTableSpec(rows;
                category_colors=Dict("a" => "#aaaaaa"),
                config=cfg)
            out = svg(spec)
            L = compute_layout(spec)

            # Pull every square <rect> (skip the background, which has
            # the white fill).
            sqs = [(parse(Int, m["x"]), parse(Int, m["y"]))
                   for m in eachmatch(
                       r"<rect x=\"(?<x>\d+)\" y=\"(?<y>\d+)\"[^>]*fill=\"#aaaaaa\"",
                       out)]
            @test length(sqs) == 7

            # First 4 squares share the top sub-row's y; their x values
            # restart from hist_x and step by stride.
            stride = cfg.square_size + cfg.square_gap   # = 12
            sq_offset = (cfg.row_height - cfg.square_size) ÷ 2
            top_y    = L.row_tops[1] + sq_offset
            wrap_y   = L.row_tops[1] + cfg.row_height + sq_offset
            @test [s[2] for s in sqs[1:4]] == fill(top_y, 4)
            @test [s[1] for s in sqs[1:4]] == [L.hist_x + i*stride for i in 0:3]
            # Wrapped sub-row: 3 squares, y advanced by row_height,
            # x restarting from hist_x.
            @test [s[2] for s in sqs[5:7]] == fill(wrap_y, 3)
            @test [s[1] for s in sqs[5:7]] == [L.hist_x + i*stride for i in 0:2]
        end

        @testset "svg: label and extras text align with the top sub-row" begin
            rows = [SquareStackTableRow("long", fill("a", 7); extras=Any[42])]
            cols = [SquareStackTableColumn("count", :right)]
            cfg  = base_cfg(max_squares_per_row=4, show_legend=false)
            spec = SquareStackTableSpec(rows; columns=cols, config=cfg)
            out = svg(spec)
            L = compute_layout(spec)

            # The label "long" and the extras "42" should both sit at
            # row_tops[1] + row_height ÷ 2 — the centre of the FIRST
            # sub-row, not the centre of the (taller) full band.
            top_text_y = L.row_tops[1] + cfg.row_height ÷ 2

            label_m = match(r"<text x=\"\d+\" y=\"(?<y>\d+)\"[^>]*>long</text>", out)
            @test label_m !== nothing
            @test parse(Int, label_m["y"]) == top_text_y

            extras_m = match(r"<text x=\"\d+\" y=\"(?<y>\d+)\"[^>]*>42</text>", out)
            @test extras_m !== nothing
            @test parse(Int, extras_m["y"]) == top_text_y
        end

        @testset "svg: cap unset matches a control spec byte-for-byte" begin
            # Sanity check the un-wrapped path is untouched: explicit
            # nothing must produce identical output to the default.
            rows = [
                SquareStackTableRow("foo", ["a", "b", "a"]),
                SquareStackTableRow("bar", ["b"]),
            ]
            control = SquareStackTableSpec(rows;
                config=SquareStackTableConfig())
            explicit = SquareStackTableSpec(rows;
                config=SquareStackTableConfig(max_squares_per_row=nothing))
            @test svg(control) == svg(explicit)
        end
    end

end
