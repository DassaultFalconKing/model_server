# Gemma4 live tool execution review

## Provenance

- Binary: `bazel-bin/src/ovms.exe`
- Review commit: `798e99e04d53fba2b1c87bd6b88260f0d6c3ca83`
- Model: `gemma4-26-heretic`
- Endpoint: `/v3/chat/completions`
- Tool policy: required, read-only inspection, no network

## Executed task

Gemma was asked to inspect `C:\git\g4-final-review` at the exact review SHA,
including status, committed diff, generated artifacts, and remote provenance.

The model generated a valid `inspect_repository_state` call with the exact SHA
and the requested safety constraints. The call was executed independently by
the harness using read-only Git/filesystem operations.

## Verified tool result

- Exact HEAD: `798e99e04d53fba2b1c87bd6b88260f0d6c3ca83`
- Worktree: dirty due to local runtime/evidence and Bazel output directories
- Committed scope: 20 expected review files
- Generated artifacts: `bazel-bin`, `bazel-out`, `bazel-testlogs`,
  `bazel-g4-final-review`, and `ab-evidence`
- Remote: `origin` points to `DassaultFalconKing/model_server`
- No source mutation or network access was used by the executor

## Findings

- PASS: first tool call was syntactically valid and semantically matched the
  requested read-only task.
- PASS: the tool executor observed the correct exact SHA and repository state.
- FINDING: when asked to chain into `publish_review_evidence`, Gemma returned
  an empty assistant message with no tool call.
- FINDING: a later natural-language summary reproduced the SHA incorrectly,
  although the original tool call contained the correct SHA.

Raw evidence is in `ab-evidence/live-tool-task/`:

- `request1-response.json` — generated tool call
- `tool1-result.json` — independently executed tool result
- `request2-response.json` — failed second tool-call attempt
- `request3-response.json` — follow-up summary with SHA transcription error

