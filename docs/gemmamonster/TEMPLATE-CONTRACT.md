# GEMMAMONSTER canonical Gemma4 template contract

Date: 2026-09-07
Status: LEADING TEMPLATE CONTRACT

## Authority

The deployment baseline for Gemma4 agent/tool-calling tests is the Google canonical template from:

```text
repository: google/gemma-4-12B-it
file: chat_template.jinja
pinned revision: 711c1368e39f1712f48ff0eb7bcdbbb760d52db0
canonical header date: 2026-07-09
```

Protocol authority:

- Google Gemma4 function-calling documentation;
- Google Gemma4 prompt-formatting documentation;
- the pinned canonical `chat_template.jinja` revision above.

The template is pinned by commit. A floating `main` download is not acceptance-grade provenance.

## Deployment target

Current production acceptance targets the GEMMAMONSTER Wondernuttz/Heretic OpenVINO Gemma4 26B lane unless a later acceptance report records a different model.

The model may ship its own template, but GEMMAMONSTER uses Google canonical behavior as the agent/tool-loop authority rather than assuming a derivative model template is equivalent.

## Responsibility split

```text
deployment pack -> chooses, pins and installs template
OVMS input path -> applies model-directory template
Gemma4 generator -> chooses generation constraints
model -> generates native Gemma4 protocol
Gemma4 parser -> parses and validates output
```

The template is not compiled into the C++ parser.

## Canonical tool syntax

The generator/template target is the native Gemma4 family:

```text
<|tool_call>call:name{...}<tool_call|>
```

Strings use the native Gemma4 delimiter family:

```text
<|\"|>...<|\"|>
```

Tool responses remain in the native Gemma4 response envelope expected by the canonical template.

## Canonical vs compatibility behavior

The parser may accept strongly anchored empirical variants such as:

```text
<|tool_call>:name{...}
<|tool_call>call:name(...)
call:name{...} after an accepted reasoning boundary
```

These are parser compatibility inputs only. The template and generator must not learn to emit them merely because the parser can recover them.

## Reasoning/history policy

Historical Heretic-line templates and the pinned Google template are not assumed byte-identical in reasoning preservation and turn closure.

For agent loops, the pinned Google template is authority. In particular, recent reasoning preservation, tool-call reasoning history and turn ordering must be evaluated against the canonical template actually installed on the acceptance host.

## Deployment helper ownership

The GEMMAMONSTER deployment helper is expected to:

1. pin the exact canonical revision;
2. avoid unnecessary network use when a local revision/hash sidecar proves the same template is already installed;
3. download only when missing/stale or explicitly refreshed;
4. validate canonical Gemma4 markers before installation;
5. back up a differing local model template before replacement;
6. verify the installed SHA-256;
7. write a machine-readable provenance sidecar beside the model;
8. permit explicit skip/override only for controlled experiments.

## Acceptance provenance

The live acceptance report must record:

```text
canonical template repository
canonical template revision
installed chat_template.jinja SHA256
pre-existing model template SHA256, if replaced
backup path, if created
deployment helper/profile used
```

A local model template with unknown provenance is not equivalent to the pinned canonical template because it happens to contain familiar Gemma markers.

## Change control

Changing the canonical template revision is a leading-contract change. It requires:

- semantic diff review against the previous pinned revision;
- rerun of tool-loop acceptance cases affected by reasoning, turn closure, tool declaration or response formatting;
- updated revision/hash in deployment documentation and acceptance provenance.

Historical detailed semantic diff material remains available under `docs/gemma4/google-template-contract.md`; this document is the current leading policy.
