# Gemmamonster Branch Ledger

This ledger records why branches exist and what claims are allowed for them. It is not a replacement for Git. It is the part where we stop pretending branch names are self-documenting, because apparently civilization has limits.

## Open lanes

| Branch | Base / HEAD at creation | Purpose | Allowed changes | Promotion target | Status |
| --- | --- | --- | --- | --- | --- |
| `integration/gemma4-parser-generator-refit-next` | current tracked HEAD: `e398363c2fe6f572a0fdc3ed9fd37c551fd73c76` | source integration lane for Gemma4 parser/generator refit | reviewed source changes, docs, contract tests | later freeze branch after acceptance | source only, machine verification pending |
| `test/gemmamonster-gate12-20260909-e398363c` | `e398363c2fe6f572a0fdc3ed9fd37c551fd73c76` | OpenCode/local machine Gate 1 and Gate 2 build/test work | test/build wiring, minimal fixes proven by logs | `integration/gemma4-parser-generator-refit-next` after review | open test lane |
| `infra/gemmamonster-candidate-discipline-20260909` | `e398363c2fe6f572a0fdc3ed9fd37c551fd73c76` | candidate manifest, vault, launcher, promotion discipline | docs and scripts under `docs/gemmamonster`, `docs/superpowers/plans`, `scripts/gemmamonster` | review then merge/cherry-pick to integration | open infra lane |

## Closed / frozen refs

| Ref | Meaning | Evidence |
| --- | --- | --- |
| `52c6b534dab9cb2cb413eb175541870785cdd2c3` | OVMS 2026.5 refit baseline freeze source point | documented in `docs/gemmamonster/2026-09-09-ovms-2026.5-refit-baseline.md` |
| `e398363c2fe6f572a0fdc3ed9fd37c551fd73c76` | current source candidate after Jinja contract wiring and content-owned routing dofix port | source-level commits only; machine verification pending |

## Update rule

Add a row whenever creating a branch that may be used by a human or agent later. The row must answer:

```text
why this branch exists
what SHA it started from
what it may change
where it may promote
what status claims are allowed
```

No row, no trust. Very harsh. Very fair.
