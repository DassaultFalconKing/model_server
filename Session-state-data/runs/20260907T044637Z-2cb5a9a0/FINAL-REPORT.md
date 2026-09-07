# Gemma4 exact-head automatic acceptance report

## Verdict

**NOT_ACCEPTED.** The exact-head build and protocol/parser path work, but the model-facing tool-use contract is not reliable enough for acceptance. The strongest failure signals are named choice `0/30`, auto success `4/100`, ungrounded invention `150/316`, and four empty named second turns in the separate 50-request campaign.

No production source was changed. All generated evidence is under this run directory.

## Frozen provenance

- Source: `C:\git\model_server-gemma4-google-template-session-state`
- Branch: `fix/gemma4-google-template-session-state`
- HEAD: `2cb5a9a0e8d22732de2d1c89f52795c2de612a57`
- Binary: `C:\git\model_server-gemma4-google-template-session-state\bazel-bin\src\ovms.exe`
- SHA256: `38067689F79AE6F6BE2D951A7827C84768265F74FF35142A5F847BCC563668D4`
- Version: `OpenVINO Model Server 2026.4.0.2cb5a9a0`
- Build flags: `--config=win_mp_on_py_on`
- Model: `gemma4-26-heretic`

Build verdict: PASS. Focused build tests: 2/2. Reliability harness unit tests: 4/4.

## Results

### Reliability campaign (316 trials)

| Segment | Passed | Material outcomes |
|---|---:|---|
| Campaign A | 54/180 (30.0%) | 91 invented ungrounded values; 35 truncated |
| Thinking | 42/100 (42.0%) | 56 invented ungrounded values; 2 truncated |
| Campaign B | 16/36 (44.4%) | 8 corrupted grounded values; 3 invented values; 9 wrong tools |

Key contract rates:

- named success: 0/30
- required success: 50/50
- auto success: 4/100
- API-visible parser recognition conditional on an attempted call: 279/279
- exact grounded-value fidelity conditional on intended parsed call: 262/279
- ungrounded hallucination: 150/316

Interpretation: the parser successfully recognizes every API-visible attempted call. The dominant defects are generation/tool-selection and semantic grounding, not parser recognition. The parser should not be broadened as a first response to these failures.

### Exactly 50 additional explicit requests

- 18 two-step chains = 36 requests, sent in batches of 1, 2, and 3: 14 chains PASS, 4 FAIL.
- Wire/API suite = 14 requests: 14/14 PASS for its declared wire contracts.
- Total: 50 explicit requests, with each raw request and response stored in its case directory.

All four chain failures occurred on the named second tool turn: HTTP 200, empty content, empty `tool_calls`, `finish_reason=length`, 1024 completion tokens. Named choice is therefore stochastic in the generated campaign (2 named chains passed, 4 failed), while the larger frozen reliability cell failed 30/30.

The wire suite proves JSON/SSE transport, reconstruction, expected validation errors, `none`, parameterless calls, truncation handling, and marker containment. It does **not** prove semantic correctness. For example, the streaming nested case passed its wire contract while the generated `binary` value was corrupted from a drive path to `:/git/...`.

### Restart/resume

PASS on deterministic retry. Session `gemma4-v2-restart-resume-fixed` retained the same seed and advanced from turn 1 to turn 2 across a real OVMS restart. The second turn emitted `publish_review_evidence` with the exact source SHA. The session store contains manifest, raw request, effective request, and generation config for both turns.

The first checkpoint attempt is deliberately retained as a semantic failure: the model corrupted the requested ref to `": "`. It was not overwritten or promoted to PASS.

## OVMS log monitoring

Active inference logs (`launch-attempt-4` and `launch-attempt-5-restart`) contain no matching `ERROR`, `FATAL`, `CL_OUT_OF_RESOURCES`, or XGrammar error. The wire server logged two graph reinitializations after intentional 4xx negative cases; these were expected. An earlier launch failed before testing because inherited Python settings were invalid; the failure log is retained at the run root.

The operational launcher requires:

- `PYTHONHOME=C:\opt\Python312`
- `PYTHONPATH=C:\llm\ovms\python;C:\opt\Python312\Lib\site-packages`
- PATH entries for OVMS Python, OpenVINO, TBB, OpenCV, Python, and the exact-head binary directory.

## File-content samples

Provenance file (`provenance.json`):

```json
{
  "git_sha": "2cb5a9a0e8d22732de2d1c89f52795c2de612a57",
  "binary_sha256": "38067689F79AE6F6BE2D951A7827C84768265F74FF35142A5F847BCC563668D4",
  "binary_version": "OpenVINO Model Server 2026.4.0.2cb5a9a0"
}
```

Representative successful chain summary (`generated-campaign\r1-b1-c1-named\summary.json`):

```json
{
  "verdict": "PASS",
  "session_id": "gen-r1-b1-c1-named",
  "second_tool_choice": "named",
  "request2": {
    "http": 200,
    "tool": "publish_review_evidence",
    "commit_sha": "2cb5a9a0e8d22732de2d1c89f52795c2de612a57",
    "exact_sha_pass": true
  }
}
```

Representative named failure (`generated-campaign\r1-b3-c1-named\request2-response.json`):

```json
{
  "choices": [{
    "finish_reason": "length",
    "message": {"content": "", "role": "assistant", "tool_calls": []}
  }],
  "usage": {"prompt_tokens": 886, "completion_tokens": 1024, "total_tokens": 1910}
}
```

Restarted session manifest (`C:\llm\ovms-session-store-reliability-v2\gemma4-v2-restart-resume-fixed\manifest.json`):

```json
{"schema_version":1,"session_id":"gemma4-v2-restart-resume-fixed","seed":42,"next_turn":3,"model":"gemma4-26-heretic"}
```

## Backup record

- Original doubtful/generated path: `C:\git\model_server-gemma4-google-template-session-state\bazel-model_server-gemma4-google-template-session-state`
- Backup: `C:\git\Session-state-data\backups\bazel-model_server-gemma4-google-template-session-state-junction-backup`
- Type: directory junction
- Target sample: `C:\opt\cdpbe2vg\execroot\ovms`
- Manifest: `C:\git\Session-state-data\backups\bazel-junction-backup-manifest.json`

The build recreated the original untracked Bazel junction; it remains the only source-worktree status entry. No tracked source file was modified.

## Fix plan

1. Enforce named tool choice at generation time. Add a live regression where a named second turn must either emit exactly that structured call or return a bounded explicit error; HTTP 200 plus empty output and `finish_reason=length` must fail.
2. Address grounding independently of parsing. Add adversarial tool-result fixtures for renamed keys, same-name distractors, scalar/array JSON, malformed JSON, fake SHA prose, and conflicting tools; require byte-exact transfer of authoritative values.
3. Tighten auto/required policy in the JINJA/generation contract. Preserve the strong required result while testing that auto calls when the user clearly requests an action and refrains when no action is requested.
4. Keep the parser strict initially. Recognition is 279/279; changing it risks accepting malformed/truncated output without fixing selection or grounding.
5. Add semantic assertions to the wire harness. A structurally valid JSON/SSE tool call with a corrupted drive path must not be labelled as an overall semantic PASS.
6. Normalize and validate base URLs in the reliability harness so a supplied `/v3` prefix cannot become `/v3/v3`.
7. Make launcher Python/OpenVINO environment setup explicit and self-checking before process start.
8. Serialize version-stamp/build steps so concurrent invocations cannot temporarily produce a placeholder-stamped binary.

After fixes, rerun the same frozen 316-trial matrix plus the 50-request batch campaign and restart/resume gate. Acceptance should require zero empty named completions, zero wrong-tool outcomes, zero grounded-value corruption, and a separately stated tolerance for genuinely ambiguous auto behavior.
