# Gemma4 Google-template + persistent session state design

## Status

Approved for implementation on 2026-09-06.

Base branch/head at design start:

- branch: `fix/gemma4-final-toolcalling-review`
- exact base: `7300995129f5686fe7ec6999905031399698745e`

Implementation branch:

- `fix/gemma4-google-template-session-state`

## Goal

Build a reproducible Gemma4 agent-serving line with four properties:

1. Wondernutts is used only as the OpenVINO IR/weights source; its `chat_template.jinja` is not authoritative.
2. Deployment overlays the current official Google Gemma4 chat template and records exact template provenance.
3. Multi-turn requests may opt into a persistent OVMS session whose seed is fixed for the entire session, whose raw/effective request payloads and effective generation config are journaled to disk, and whose hot manifest state is cached in bounded RAM.
4. Gemma4 tool parsing safely recovers observed bare native calls of the form `call:tool_name{...}` when, and only when, the name is one of the request-declared tools and the argument container is valid.

`TriggeredTags` guided generation is explicitly out of scope for this implementation line. It remains a later A/B experiment after the new baseline is measured.

## Runtime/template authority

### Runtime

The acceptance environment must use the newest mutually compatible Windows OpenVINO + OpenVINO GenAI runtime available at test time. Runtime provenance is part of acceptance evidence, not an informal machine assumption.

The deployment/acceptance tooling must record at least:

- OpenVINO version;
- OpenVINO GenAI version;
- `OpenVINO_DIR`;
- SHA256 for the relevant OpenVINO/GenAI DLLs loaded by the tested `ovms.exe` when practical;
- OVMS Git SHA;
- OVMS binary SHA256.

### Google chat template

The model directory used by OVMS must not use the Wondernutts `chat_template.jinja`.

A preparation script resolves the current revision of `google/gemma-4-26B-A4B-it`, downloads `chat_template.jinja` from that exact revision, places it in the runtime model overlay, and writes a provenance manifest containing:

- source repo/model id;
- resolved Google revision;
- source URL;
- template SHA256;
- timestamp;
- source weights directory;
- overlay directory.

A `-GoogleRevision` override is supported only for exact reproduction of an already-recorded run. Omitting it means “resolve latest at preparation time, then pin and record what was resolved”.

The source Wondernutts directory is never modified in place.

## Session-state API contract

### Session identity

Session behavior is opt-in through an HTTP header:

`X-OVMS-Session-ID: <session-id>`

Requests without this header retain ordinary OpenAI-compatible request behavior.

Session IDs are validated before use in a filesystem path. Allowed characters are ASCII letters, digits, `.`, `_`, and `-`, with length 1..128. Invalid IDs fail closed.

### Store configuration

The persistent store is enabled by environment variable:

`OVMS_SESSION_STORE_DIR=<path>`

When the variable is absent or empty, session persistence is disabled even if a session header is supplied; the request follows legacy behavior and a warning is logged.

Additional environment variables:

- `OVMS_SESSION_CACHE_ENTRIES` default `64`, minimum `1`;
- `OVMS_SESSION_MAX_BYTES` default `1073741824` (1 GiB), minimum `1048576`;
- `OVMS_SESSION_MAX_REQUEST_BYTES` default `8388608` (8 MiB), minimum `1024`.

The store must never silently grow beyond `OVMS_SESSION_MAX_BYTES`. If the next atomic record would exceed the configured bound, that session write/request fails with an explicit resource-exhausted/internal error rather than filling the disk.

### One seed per session

On the first request for a session:

- if the OpenAI body contains explicit `seed`, that value becomes the session seed;
- if `seed` is omitted, OVMS generates one non-zero `uint32_t` seed exactly once, persists it in the session manifest, and injects it into the effective request before OpenAI request parsing/generation-config building.

On later requests:

- if `seed` is omitted, the persisted session seed is injected;
- if the request supplies the same seed, it is accepted;
- if the request supplies a different seed, the request fails with a session-seed-conflict error.

The model itself is not treated as holding a seed across turns. Every HTTP turn receives an explicit effective seed from the session layer.

### Durable journal

Disk layout:

```text
<OVMS_SESSION_STORE_DIR>/
  <session-id>/
    manifest.json
    turns/
      000000000001/
        raw-request.json
        effective-request.json
        generation-config.json
      000000000002/
        ...
```

`manifest.json` contains at minimum:

- schema version;
- session id;
- session seed;
- next turn index;
- last-access timestamp;
- optional model string from the most recent request.

For each turn:

- `raw-request.json` is the exact HTTP JSON body before seed injection;
- `effective-request.json` is the exact JSON body after session-seed resolution/injection and before `OpenAIApiHandler` parsing;
- `generation-config.json` is a compact serialization of effective generation fields after the full builder pipeline has run.

The generation snapshot must include at least:

- `rng_seed`;
- `temperature`;
- `top_p`;
- `top_k`;
- `min_p` when supported;
- `do_sample`;
- `num_beams`;
- `max_new_tokens`;
- `max_length`;
- `ignore_eos`;
- `repetition_penalty`;
- tool-choice text when available;
- whether structured output is active.

Writes use same-directory temporary files followed by rename/replace so a crash cannot leave a partially written authoritative JSON record.

### RAM cache

The store keeps only hot session manifest state in RAM. Full turn payloads remain on disk and are not loaded eagerly.

The RAM cache is an LRU bounded by `OVMS_SESSION_CACHE_ENTRIES`.

On cache miss:

1. load and validate `manifest.json` from disk if it exists;
2. otherwise create a new in-memory session state;
3. touch the LRU entry;
4. evict only the least-recently-used in-memory manifest when over capacity.

LRU eviction does not delete durable session files.

All cache/store mutations are mutex protected.

## Integration point

Session seed injection and raw/effective request persistence happen in `GenAiServable::parseRequest()` before construction/parsing of `OpenAIApiHandler`, because `HttpPayload` already carries both headers and parsed JSON.

This keeps session semantics outside model-specific generation builders and ensures the existing generation-config pipeline sees an ordinary explicit OpenAI `seed`.

After `extractInputRequest()` succeeds, `GenAiServable::parseRequest()` persists the effective `GenerationConfig` snapshot for the same turn.

Per-request execution context stores only lightweight session bookkeeping:

- session id;
- turn index;
- whether journaling is active.

## Bare `call:` recovery

Observed leaked Gemma4 calls can appear without `<|tool_call>` as:

```text
call:tool_name{...}
```

The parser must recover these calls beyond the current exact-phase-entry fallback, but only under strict guards.

A bare candidate is executable only when all of the following hold:

1. it begins at a lexical boundary, defined as start-of-buffer or immediately after whitespace/newline or a Gemma reasoning/control boundary already owned by the parser;
2. the normalized tool name is syntactically sane;
3. the tool name exists in `toolNameSchemaMap` for the current request;
4. the next non-space character starts a supported argument container (`{` or `(`);
5. the argument container closes correctly;
6. native/JSON argument parsing succeeds.

Unknown tools, malformed containers, quoted/documentation examples, and arbitrary prose containing `call:` remain content.

Canonical `<|tool_call>call:...<tool_call|>` behavior remains unchanged and has priority over bare recovery.

## Grounded tool-result behavior retained

The accepted request-local conversion of JSON-object tool results to structured mappings remains enabled for compatible Gemma4 templates. This implementation must not weaken exact opaque-value propagation already demonstrated for Git SHA values.

## Testing strategy

TDD order:

1. session-store unit tests for first-turn generated seed, explicit seed, same-seed reuse, conflict rejection, disk reload after RAM eviction/restart, atomic files, invalid session IDs, cache bound, and byte quota;
2. integration-oriented tests that mutate a RapidJSON OpenAI request document before request parsing and prove the same session seed reaches the normal generation-config builder on multiple turns;
3. generation-config snapshot serialization tests;
4. Gemma4 parser regressions using real observed bare shape `call:tool{...}` plus negative prose/unknown/malformed cases;
5. PowerShell preparation-script tests where practical plus a dry-run/check mode that verifies Google-template provenance without touching the source model.

The existing Gemma4 parser corpus and chained named/required/auto harness remain mandatory regression gates.

## Acceptance baseline

The new line is not accepted merely because unit tests compile.

Local Windows acceptance must demonstrate, on an exact branch HEAD:

- fresh build against the newest selected runtime;
- exact runtime/DLL provenance captured;
- runtime overlay uses Google template and proves its resolved Google revision/SHA256;
- source Wondernutts model directory remains unchanged;
- session seed remains byte-for-byte/numerically identical across every turn in one session;
- restarting OVMS and reusing the same session ID reloads the persisted seed from disk;
- different session IDs can use different seeds;
- conflicting explicit seed is rejected;
- raw/effective request and generation-config snapshots exist for every tested turn;
- canonical and recovered bare tool calls parse correctly;
- false-positive bare-call negatives remain plain text;
- existing exact SHA propagation remains accepted;
- repeated named/required/auto chain campaign records sampling profile, seed, full requests, raw outputs, and classified outcomes.

Only after this baseline is measured may a separate branch test Gemma4 `TriggeredTags` for `auto`.