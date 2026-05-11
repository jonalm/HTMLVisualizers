## Julia work: prefer kaimon MCP when available

When working with Julia code in any project, prefer kaimon MCP tools (`mcp__kaimon__*`) over Read/Edit/Bash/Grep when a kaimon session is connected.

**Why:** kaimon exposes a live Julia REPL plus Julia-native introspection (type reflection, method search, semantic code search via qdrant) that is more accurate and token-efficient than shelling out to `julia` or grepping source. But kaimon isn't always running, so the rule is soft.

**How to apply:**
- At the start of any Julia-related task, check the deferred-tool registry for `mcp__kaimon__*` entries (a `ToolSearch` for `kaimon` is sufficient). If no such entries exist at all, **warn the user** that the kaimon MCP server is not loaded in this session and ask whether to proceed with standard tools or wait for them to start it. Do not silently fall back.
- If the tools exist, call `mcp__kaimon__ping` to check for a connected session. If `ping` reports no sessions, **warn the user** and ask whether to proceed with standard tools or wait for a session to connect. Again, do not silently fall back.
- On the first Julia task of a conversation where kaimon is both loaded and has an active session, also call `mcp__kaimon__usage_instructions` once (authoritative, may change over time) and `mcp__kaimon__investigate_environment` on the session.

**Project activation.** `investigate_environment` reports which project is
active in the kaimon session. Kaimon's own `usage_instructions` says **never
change project with `Pkg.activate()`** — the session is expected to be started
already pointed at the right project. If the active project doesn't match the
repo you're working in, **stop and ask the user to restart the kaimon session
with the correct project** (e.g. launched with `--project=.` from the repo
root) rather than calling `Pkg.activate` from inside. Don't fall back to
shelling out `julia --project=.` through Bash either; that loses Revise,
spawns a cold process per call, and is exactly the thing kaimon exists to
replace.

**Running the test suite.** Prefer `run_tests` (which spawns a test subprocess
rooted at the active project) over `Pkg.test()` via `ex` or `julia -e 'Pkg.test()'`
through Bash.

**Stable gotchas (cached so I don't have to re-fetch `usage_instructions` mid-task):**
- `ex` strips stdout — `println` output is never returned. To see a value, pass `q=false` with the value as the final expression (e.g. `ex(e="length(data)", q=false)`).
- Default to `q=true` for assignments, imports, and definitions. Only use `q=false` when the return value is needed to make a decision.
- Prefer `qdrant_search_code`, `type_info`, `search_methods`, `list_names`, `goto_definition` over grep for Julia code discovery.
- Use `pkg_add` (MCP tool) instead of `Pkg.add()` inside `ex`.
- Don't call `Revise.revise()` — Revise auto-tracks `src/`. If changes feel stale, restart via `manage_repl(command="restart")` rather than fighting world-age errors.
- Every `ex` call returns an `eval_id`; use `check_eval` to poll long-running or timed-out calls (history keeps last 64).

**Terminology:** `ex`, `ping`, `usage_instructions`, etc. are MCP tool names, not Julia functions. Only the string passed as the `e` argument to `ex` is actual Julia code that runs in the REPL.
