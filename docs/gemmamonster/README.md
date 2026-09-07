# GEMMAMONSTER leading documents

Date: 2026-09-07
Status: CANONICAL PROJECT DOCUMENT ROOT

This directory is the canonical entry point for the GEMMAMONSTER fork work: Gemma4 deployment on OVMS/OpenVINO, tool-calling parser/generator integration, Windows/Arc acceptance, and promotion into the fork `main`.

The purpose of this directory is to separate **leading documents** from historical reports, raw evidence, temporary agent prompts and branch-local notes. Older material remains useful as provenance, but it does not override the contracts here unless a later leading document explicitly says so.

## Leading documents

Read in this order:

1. [`INTEGRATION-BASELINE.md`](INTEGRATION-BASELINE.md) — current fork/upstream/PR topology and clean-main integration policy.
2. [`TOOL-CALLING-ARCHITECTURE.md`](TOOL-CALLING-ARCHITECTURE.md) — end-to-end request → generator → model → parser → response architecture.
3. [`GENERATOR-CONTRACT.md`](GENERATOR-CONTRACT.md) — canonical generator behavior, lazy auto semantics, hard choices and `parallel_tool_calls`.
4. [`PARSER-CONTRACT.md`](PARSER-CONTRACT.md) — canonical parser invariants and tolerated compatibility inputs.
5. [`TEMPLATE-CONTRACT.md`](TEMPLATE-CONTRACT.md) — Google canonical Gemma4 template authority and deployment ownership.
6. [`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md) — exact promotion gate for the new fork `main` candidate.
7. [`WINDOWS-ACCEPTANCE-GATE.md`](WINDOWS-ACCEPTANCE-GATE.md) — Windows/Bazel/toolchain/tokenizer preconditions for evidence-bearing tests.
8. [`CURRENT-INVESTIGATIONS.md`](CURRENT-INVESTIGATIONS.md) — active investigation lanes and what each agent is allowed to change.

## Authority hierarchy

When documents disagree, use this order:

1. current leading document in this directory;
2. explicit accepted source/test contract on the current integration candidate;
3. official Google Gemma4 protocol/template documentation;
4. current OpenVINO GenAI / xgrammar structural-output API behavior;
5. current OVMS upstream implementation patterns;
6. peer runtime compatibility evidence such as llama.cpp or vLLM;
7. historical GEMMAMONSTER reports and raw runtime evidence.

Peer runtimes are comparators, not protocol authority.

## Current branch policy

The current documentation branch is:

```text
docs/gemmamonster-leading-docs
```

It was created from the fork `main` observed at:

```text
be410567f2b3f8146eda87087beb59b67199c893
```

This branch does not move production `main` and is intended to be rebased/ported onto the new clean fork-main candidate after the integration investigation resolves the final base.

## Historical provenance, not leading authority

Important earlier materials remain in the repository, including:

```text
docs/gemma4/*
docs/superpowers/plans/*gemma4*
docs/superpowers/reports/*gemma4*
ab-evidence/*
HANDOFF.md
```

In particular:

- `docs/gemma4-auto-generator-port-handoff.md` records the first TriggeredTags generator port handoff;
- `docs/superpowers/plans/2026-09-07-gemma4-generator-hardening.md` records the generator hardening implementation plan;
- `docs/gemma4/google-template-contract.md` records the Google-template diff review;
- `docs/gemma4/tool-calling-callgraph.md` is useful historical architecture material but its older `auto` description predates the accepted TriggeredTags/lazy-generator direction and therefore must not override `TOOL-CALLING-ARCHITECTURE.md` here;
- `ab-evidence/*` contains runtime/campaign evidence and must not be treated as source authority by filename or age alone.

## Promotion discipline

No branch becomes the GEMMAMONSTER fork `main` because it is mergeable or because an old acceptance campaign passed.

Promotion requires the exact candidate to satisfy [`ACCEPTANCE-MATRIX-V1.md`](ACCEPTANCE-MATRIX-V1.md), with PASS/FAIL/BLOCKED/NOT_RUN reported honestly and source/binary/model/template provenance attached.
