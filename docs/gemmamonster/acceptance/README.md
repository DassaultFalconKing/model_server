# Gemmamonster Acceptance Reports

This directory stores small, human-readable acceptance reports for manifest-backed candidates.

Do not commit large binaries or raw build trees here. Put those in the external candidate vault and record their paths and SHA256 values in the report.

A report must distinguish:

```text
SOURCE: source ref exists
BUILD: binary produced and hashed
PROTOCOL: contract tests passed
LIVE: OVMS/model runtime tests passed
DOGFOOD: real agent loop passed
```

If a section was not run, write `NOT_RUN` with a reason. Guessing is not a verification strategy, despite centuries of human experimentation to the contrary.
