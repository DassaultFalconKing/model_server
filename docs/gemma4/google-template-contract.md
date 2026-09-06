# Gemma4 canonical template contract and diff review

## Authority

The deployment baseline for Gemma4 agent/tool-calling tests is the Google canonical template from:

- repository: `google/gemma-4-12B-it`
- file: `chat_template.jinja`
- pinned revision: `711c1368e39f1712f48ff0eb7bcdbbb760d52db0`
- canonical header date: `2026-07-09`
- upstream context: fixes for tool-calling loops, turn closures and thinking ordering; the pinned main revision also carries null handling, reasoning preservation, turn-tag balance and input validation fixes.

Protocol/documentation authority:

- https://ai.google.dev/gemma/docs/capabilities/text/function-calling-gemma4
- https://ai.google.dev/gemma/docs/core/prompt-formatting-gemma4
- https://huggingface.co/google/gemma-4-12B-it/blob/711c1368e39f1712f48ff0eb7bcdbbb760d52db0/chat_template.jinja

The template is pinned by commit, not downloaded from floating `main`.

## Model template under test

Production acceptance currently targets:

`Wondernutts/gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov`

The published OpenVINO model contains its own `chat_template.jinja` (about 23.1 kB in the published revision). Its model card explicitly identifies the `<|turn>...<turn|>` / `<|channel>...<channel|>` protocol and warns against grammar-constrained JSON mode because of Gemma4 repetition collapse.

The model descends from the llmfan46 Heretic line. That lineage template already implements Gemma4-native declarations, recursive argument formatting and `<|tool_response>response:name{...}<tool_response|>`, but its reasoning/history policy is not byte-for-byte the current Google canonical template.

## Semantic diff review

This review is intentionally semantic. The launch helper backs up the exact local pre-implant file, so the live machine can additionally produce a literal file diff against the pinned Google revision.

| Contract | Heretic lineage / existing model template | Google pinned canonical | GEMMAMONSTER decision |
|---|---|---|---|
| Turn framing | `<|turn>role\n...<turn|>` | same native family | Google canonical |
| Tool declaration grammar | native Gemma4 declaration format | native Gemma4 declaration format | Google canonical |
| Tool-call output | `<|tool_call>call:name{...}<tool_call|>` | same canonical envelope | Google canonical |
| Tool response | native `response:name{...}` block | same canonical family | Google canonical |
| String delimiter | `<|\"|>` | `<|\"|>` | unchanged |
| Recursive objects/arrays | supported | supported | canonical implementation |
| null / bool / number formatting | native typed values | explicit current handling | Google canonical |
| Historical reasoning | Heretic lineage gates reasoning strongly around tool-call turns | pinned Google template preserves recent reasoning and preserves tool-call reasoning according to `preserve_thinking` | Google canonical |
| Content/tool-call ordering | lineage-specific continuation logic | current Google ordering/turn-closure rules | Google canonical |
| Input validation | lineage-specific | current canonical validation | Google canonical |
| Generation prompt / preclosed thought | model card uses preclosed thought for fast non-thinking manual prompts | canonical template owns standard generation-prompt behavior | use canonical template in OVMS; manual raw-prompt experiments must be separate |

### Important reasoning difference

The Heretic lineage template observed in the published source line uses a gate equivalent to:

```text
(recent_turn OR preserve_thinking) AND message_has_tool_calls
```

for emitting stored reasoning. The pinned Google canonical template uses a gate equivalent to:

```text
recent_turn OR (preserve_thinking AND message_has_tool_calls)
```

This means the canonical template can preserve recent non-tool reasoning while still retaining tool-call reasoning history according to policy. For agent loops, the Google rule is the authority.

## Deployment ownership

OVMS itself already prioritizes `chat_template.jinja` from the model directory. Therefore the template is **not compiled into the C++ parser**.

Deployment helper ownership:

`DassaultFalconKing/OpenVino-For-Gemma-4/ovms/gemma4-diagnostic-pack/launch.ps1`

The helper:

1. pins the exact Google revision above;
2. skips network if a sidecar revision + SHA-256 matches the installed canonical file;
3. downloads only when missing/stale or when `-RefreshCanonicalTemplate` is requested;
4. checks canonical Gemma4 markers before installation;
5. backs up a differing local template before replacement;
6. verifies installed SHA-256;
7. writes `.gemmamonster-chat-template.json` beside the model;
8. allows explicit `-SkipCanonicalTemplate` for controlled experiments.

This preserves a clean responsibility split:

```text
deployment pack -> chooses/pins/installs template
OVMS input path -> applies template
Gemma4 generator -> chooses generation constraints
model -> generates native protocol
Gemma4 parser -> parses/validates model output
```

## Live diff evidence required

On the Arc acceptance host, retain the automatically created:

```text
chat_template.jinja.pre-gemmamonster-YYYYMMDD-HHMMSS.bak
.gemmamonster-chat-template.json
```

and record:

```powershell
Compare-Object `
  (Get-Content -LiteralPath .\chat_template.jinja.pre-gemmamonster-*.bak) `
  (Get-Content -LiteralPath .\chat_template.jinja)
```

For a durable machine-readable diff, use Git if the model directory is a checkout or any line-diff tool available on the host. The acceptance report must record both pre-implant and installed SHA-256 values.

## What the parser may tolerate beyond the template

Generator/template output should target only canonical syntax. Parser v2 may additionally accept empirically observed variants when strongly anchored:

- `<|tool_call>:name{...}`
- `<|tool_call>call:name(...)`
- `<channel|>call:name{...}` immediately after reasoning

These are compatibility inputs, not alternate serialization targets. The parser must never teach the generator/template to emit them.
