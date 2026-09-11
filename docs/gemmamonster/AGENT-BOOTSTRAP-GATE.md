# GEMMAMONSTER Agent Bootstrap Gate

Status: repository policy and enforcement design.

## Goal

Every coding/research agent working in this repository should consume the same authority and negative constraints before it is allowed to mutate or test product behavior.

The canonical repository contract is `AGENTS.md`.

The canonical supporting documents are:

- `docs/gemmamonster/AGENT-AUTHORITY-INDEX.md`
- `docs/gemmamonster/AGENT-NEGATIVE-CONTRACT.md`

Agent-specific files must remain thin adapters. They must not grow independent copies of the authority map or negative contract, because duplicated constitutions drift.

## Enforcement hierarchy

### Level 1 — repository instruction discovery

Use root `AGENTS.md` as the canonical bootstrap file for agents that discover repository instructions automatically.

This is the minimum acceptable layer, but it is not mechanically sufficient for every agent/runtime.

### Level 2 — agent-specific always-on adapters

Adapters should contain only a mandatory redirect to `AGENTS.md` plus the rule that no repository tool may be used before the canonical bootstrap is consumed.

Current adapter surfaces:

- `GEMINI.md`
- `CLAUDE.md`
- `.cursor/rules/00-gemmamonster-authority.mdc`
- `.github/copilot-instructions.md`

Do not duplicate the full authority data into these files.

### Level 3 — mechanical pre-tool gate

For a harness under our control, repository Markdown is not enough. The stronger architecture is:

```text
agent starts
  -> only bootstrap/read capability is available
  -> harness requires AGENTS.md + authority index + negative contract to be read
  -> harness records resolved repository/branch/HEAD
  -> only then expose Git/shell/edit/build/test/network tools
```

This is the preferred enforcement for NovaClaw/OpenCode/Codex-style orchestration when the launcher can control tool exposure.

The gate should fail closed if:

- `AGENTS.md` cannot be read;
- either canonical supporting document cannot be read;
- repository/branch/HEAD cannot be resolved for a repository task;
- the agent attempts to mutate product source before bootstrap completion.

The gate must not silently substitute cached prompt text for the repository files. Repository state is the authority.

## Non-goals

This repository-policy commit does not implement a harness-specific launcher gate. Launcher enforcement requires changing the owning harness after its exact bootstrap/tool-registration path is identified and tested.

Do not modify OVMS/Gemmamonster runtime code to enforce agent bootstrap. Agent bootstrap belongs in the agent/harness control plane, not the model server data plane.

## Verification contract for a future mechanical gate

A harness implementation should have a negative test proving that the first prohibited tool request is rejected before bootstrap, plus a positive test proving tools become available only after all three canonical files were consumed and live repo/HEAD was resolved.

Recommended observable state:

```text
BOOTSTRAP_UNREAD
  -> CANONICAL_DOCS_READ
  -> REPO_STATE_RESOLVED
  -> TOOLS_ENABLED
```

No transition may skip a state.
