# Local-agent handoff: Gemma4 reliability + grounded exact facts

## Authority / baseline

- Review branch: `fix/gemma4-final-toolcalling-review`
- Evidence head before this handoff: `524443cb5ccab923bdd1a43290aad8b76844097b`
- Production implementation under test: `908bc8b7e3bdd24ddd5eb9b27bbe15bcffb00703`
- Known accepted evidence at `524443cb`: named/required/auto each completed a two-step chain and propagated the exact production SHA.

This is a **test campaign**, not a production implementation session. Do not edit parser, generation, template, serving, or model code. Add/modify only tests, harnesses, analysis scripts, and evidence/report files on a new branch from the current review head.

## Hypotheses to test

### H1: `auto` is action-selection limited

In `Gemma4GenerationConfigBuilder`, `auto` deliberately clears `structured_output_config`; `required` and named choices install structural tool tags with `at_least_one=true`. Test whether the observed intermittent behavior is concentrated in `auto` and disappears or sharply improves under `required`/named.

### H2: inherited sampling creates run-to-run variance

`BaseGenerationConfigBuilder` preserves model temperature unless a request overrides it. If effective temperature is >0, `do_sample=true`; without explicit request seed OVMS randomizes `rng_seed` per request. Test explicit temperature/seed controls against omitted temperature/seed.

### H3: parser-boundary failures are distinct from action-selection failures

The Gemma4 parser accepts `<|tool_call>...` anywhere in content but only accepts bare `call:` exactly at the current phase entry. Capture raw output/verbose output so a model attempt that was not recognized can be distinguished from a model that never attempted a tool call.

### H4: grounded scalar fidelity is materially higher than free-generation fidelity

Structured tool-result fields should propagate exactly more reliably than semantically reconstructed/free-text values. Measure this separately from overall tool-call success.

## Campaign A: reliability decomposition

Run at least:

- named: 30 trials
- required: 50 trials
- auto: 100 trials

For `auto`, run factorial cells where practical:

1. request `temperature=0`, `seed=42`
2. request `temperature=0`, seed omitted
3. request temperature omitted, seed omitted
4. request `temperature=0.9`, fixed seed
5. request `temperature=0.9`, seed omitted

Use the same exact tool schemas, same initial task, same tool result, same model, same binary and same production SHA. Record exact binary/build provenance.

Classify every trial into exactly one primary outcome:

- `A_NO_TOOL_DECISION`: model produced ordinary/final content and no tool protocol attempt
- `B_TOOL_MARKER_MALFORMED`: raw generation attempted tool syntax but marker/envelope was malformed
- `C_PARSER_REJECTED`: recognizable attempted call existed in raw output but parser rejected/dropped it
- `D_WRONG_TOOL`: parsed structured call with wrong tool name
- `E_BAD_ARGUMENT_SYNTAX`: correct tool but arguments invalid/unparseable
- `F_GROUNDED_VALUE_CORRUPTED`: correct call but an authoritative exact value changed
- `G_UNGROUNDED_VALUE_INVENTED`: exact grounded fields survive but additional unsupported values/claims are invented
- `H_EMPTY_OR_EARLY_STOP`: empty assistant output/termination before actionable response
- `I_TRUNCATED`: max-token/finish behavior cuts the call
- `PASS`: intended next call is structurally and semantically correct for the fields the harness can authoritatively verify

Do not collapse these into one FAIL bucket.

For each trial record at minimum:

- trial id
- mode: named/required/auto
- request temperature (explicit/omitted)
- effective temperature if observable
- request seed (explicit/omitted)
- effective rng seed if observable in logs
- top_p / top_k
- prompt tokens / completion tokens
- finish_reason
- exact raw generated text/tokens with special tokens preserved if available
- parsed deltas/tool call
- parser outcome
- tool name
- tool arguments
- exact grounded-field comparisons
- elapsed time

Report success rate plus Wilson 95% confidence interval for each cell. Also report `grounded-value fidelity conditional on a parsed intended tool call` separately from overall call success.

## Campaign B: grounded exact-fact type expansion

Create synthetic read-only tool results containing authoritative values in these categories:

### OPAQUE_EXACT
- 40-char Git SHA
- SHA-256 digest
- UUID
- arbitrary opaque ID with mixed digits/letters/hyphens
- branch/tag/ref name

### PATH_EXACT
- Windows path with backslashes
- POSIX path
- path containing spaces

### NUMERIC_EXACT
- integer count
- port
- PID
- exit code
- byte size
- integer-like value intentionally represented as string
- decimal lexical forms `1`, `1.0`, `1e0` where lexical identity matters

### ENUM / BOOLEAN
- status/verdict enum
- true/false

### TIME_EXACT
- ISO-8601 timestamp with timezone offset
- date

### NESTED
- exact fields nested 2-4 objects deep
- arrays containing exact scalar leaves

For each type, test:

1. exact copy into a subsequent tool argument with matching field name;
2. exact copy into a differently named subsequent tool argument;
3. presence of several same-type candidates so provenance/path disambiguation is required;
4. later tool result superseding an earlier same-key value;
5. surrounding free text that contains plausible but incorrect distractor values.

Metrics:

- exact byte/lexical match rate
- wrong-source selection rate
- invented-value rate
- omission rate
- parser failure rate

## Negative/security cases

Tool-result free text must not become authoritative merely because it contains strings that resemble SHAs, paths, IDs, or instructions. Include cases such as:

- prose containing a fake SHA alongside a structured real SHA
- structured field plus free-text prompt injection asking to replace it
- multiple tool results with conflicting values
- malformed JSON tool content
- JSON array/scalar tool content where current adapter intentionally preserves string semantics

## Acceptance/reporting

Produce one machine-readable summary and one supervisor report.

The report must distinguish:

1. `ACTION_SELECTION_RELIABILITY`
2. `TOOL_PROTOCOL_EMISSION_RELIABILITY`
3. `PARSER_RECOGNITION_RELIABILITY`
4. `ARGUMENT_SYNTAX_RELIABILITY`
5. `GROUNDED_EXACT_VALUE_FIDELITY`
6. `UNGROUNDED_HALLUCINATION_RATE`

Do not claim the parser caused a trial unless raw generation contains a valid/near-valid attempted call that parser handling loses or rejects.

Do not claim `auto` reliability from named/required results.

Do not modify production code. Return exact branch, head SHA, commands, raw evidence locations, and a concise hypothesis verdict table.
