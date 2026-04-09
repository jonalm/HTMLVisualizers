## Julia work: prefer kaimon MCP when available

When working with Julia code in any project, prefer kaimon MCP tools (`mcp__kaimon__*`) over Read/Edit/Bash/Grep when a kaimon session is connected. If no session is connected, silently fall back to the standard tools — do not prompt the user about it.

**Why:** kaimon exposes a live Julia REPL plus Julia-native introspection (type reflection, method search, semantic code search via qdrant) that is more accurate and token-efficient than shelling out to `julia` or grepping source. But kaimon isn't always running, so the rule is soft.

**How to apply:**
- At the start of any Julia-related task, call `mcp__kaimon__ping` to check for a connected session. If one exists, use kaimon for the rest of the task.
- On the first Julia task of a conversation where kaimon is available, also call `mcp__kaimon__usage_instructions` once (authoritative, may change over time) and `mcp__kaimon__investigate_environment` on the session.
- If `ping` shows no sessions, fall back to Read/Edit/Bash/Grep without mentioning kaimon unless the user asks or a task would clearly benefit from starting a session.

**Stable gotchas (cached so I don't have to re-fetch `usage_instructions` mid-task):**
- `ex` strips stdout — `println` output is never returned. To see a value, pass `q=false` with the value as the final expression (e.g. `ex(e="length(data)", q=false)`).
- Default to `q=true` for assignments, imports, and definitions. Only use `q=false` when the return value is needed to make a decision.
- Prefer `qdrant_search_code`, `type_info`, `search_methods`, `list_names`, `goto_definition` over grep for Julia code discovery.
- Use `pkg_add` (MCP tool) instead of running `Pkg.add()` inside `ex`. Never call `Pkg.activate()` — don't change the project.
- Don't call `Revise.revise()` — Revise auto-tracks `src/`. If changes feel stale, restart via `manage_repl(command="restart")` rather than fighting world-age errors.
- Every `ex` call returns an `eval_id`; use `check_eval` to poll long-running or timed-out calls (history keeps last 64).

**Terminology:** `ex`, `ping`, `usage_instructions`, etc. are MCP tool names, not Julia functions. Only the string passed as the `e` argument to `ex` is actual Julia code that runs in the REPL.
