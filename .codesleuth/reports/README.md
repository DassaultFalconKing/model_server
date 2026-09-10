# CodeSleuth analytical reports

This folder is the durable, assistant-readable report store for this worktree.

- **Writer:** OpenCode's primary `build` agent (via `/repo-review`, `/repo-docs`, `/repo-report`).
- **Readers:** later CodeSleuth/OpenCode sessions, Cursor, Claude, Codex, Copilot, and humans working in this worktree by default.
- **Do not** invent a second CodeSleuth supervisor prompt. Reports are ordinary markdown files.

## Files

| Path | Git | Purpose |
|---|---|---|
| `README.md` | may be tracked | convention that can be intentionally shared |
| `INDEX.md` | locally excluded by default | catalog of reports in this worktree |
| `YYYY-MM-DDTHHMMZ-<slug>.md` | locally excluded by default | one analysis report |

Report bodies are excluded from Git by default because they may contain secrets, source excerpts, or credentials. CodeSleuth uses the repository-local Git exclude file (`.git/info/exclude`) and does not rewrite the project's tracked `.gitignore` for this purpose. Inspect and sanitize material before intentionally adding or publishing it. Fresh clones only receive reports or guidance that a maintainer deliberately commits.

## Required report sections

1. Title, UTC date, target (`HEAD`, dirty, scope)
2. Summary
3. Findings (severity, `path:line-line`, evidence, recommendation)
4. Paths inspected
5. Checks/tests actually run
6. Recommendations
7. Limitations / not reviewed
8. Link to `.opencode/state/reviews/<id>/` when a durable review exists

See `.opencode/CODESLEUTH-REPORTS.md` for the full template.
