# GEMMAMONSTER AGENT BOOTSTRAP CONTRACT

This instruction is mandatory for every coding, research, review, debugging, porting, build, or implementation session in this repository.

## BEFORE THE FIRST TOOL CALL

Before invoking any shell, Git, filesystem, search, web, GitHub, build, test, edit, patch, or other tool:

1. Read this file completely.
2. Read `docs/gemmamonster/AGENT-AUTHORITY-INDEX.md` completely.
3. Read `docs/gemmamonster/AGENT-NEGATIVE-CONTRACT.md` completely.
4. Resolve and record the exact current repository, branch, and HEAD.
5. Resolve every authority ref required by the task. Never assume a branch still points at the SHA recorded in the index.
6. Do not modify product source until the task's evidence requirements and first failing layer are understood.

If either required document is missing, unreadable, or contradicts this file, stop before modifying or testing product behavior. Do not silently substitute memory, prior chat context, branch names, commit messages, or similarly named tests for the required authority documents.

## EVIDENCE RULE

For semantic-refit work, the primary question is not:

> What appears to have been ported?

The primary question is:

> What semantic equivalence cannot currently be proven?

Treat every unproven cross-layer equivalence as an open risk until it has evidence. A semantic difference between an authority implementation and the current Gemmamonster refit is not acceptable merely because the target code looks similar.

Every accepted semantic difference requires:

1. explicit rationale;
2. a source-level regression contract;
3. runtime evidence when runtime behavior is involved.

Prefer negative, falsifiable constraints over broad positive goals. For example, `do not change terminal behavior between authority and refit without a documented rationale and regression test` is stronger than `preserve semantics`.

## PRODUCT-SOURCE GUARD

Do not patch product behavior merely because a synthetic reproducer demonstrates a possible failure mechanism. First capture the naturally occurring failure, identify the earliest evidenced failing layer, and show that the proposed code owner actually owns that failure.

Do not move `main`, release refs, freeze refs, tags, or accepted baselines unless the user explicitly requests that ref movement.

## DEFAULT FAILURE CLASSIFICATION

Classify at the earliest evidenced failing layer:

- `MODEL_EOS`
- `GENERATION_LIMIT`
- `CONTEXT_EXHAUSTED`
- `STREAM_TERMINATED`
- `PARSER_DROPPED_CALL`
- `WIRE_EMISSION_FAILURE`
- `SESSION_CONTINUITY_FAILURE`
- `HARNESS_STOPPED_LOOP`
- `RUNTIME_FAILURE`
- `UNKNOWN`

Never collapse distinct failure domains merely because the user-visible symptom is "the agent stopped".

## REFIT DIFFERENTIAL OUTPUT

When comparing an authority line with a refit, lead with what is unproven:

```text
UNPROVEN SEMANTIC EQUIVALENCE
-----------------------------
source behavior:
target behavior:
why existing tests do not prove equivalence:
minimal differential test:
possible impact:
confidence:
```

Do not lead with a list of files that merely look similar.

## CANONICAL DOCUMENTS

The live authority map is `docs/gemmamonster/AGENT-AUTHORITY-INDEX.md`.

The mandatory negative constraints are `docs/gemmamonster/AGENT-NEGATIVE-CONTRACT.md`.

The enforcement model and adapter policy are documented in `docs/gemmamonster/AGENT-BOOTSTRAP-GATE.md`.
