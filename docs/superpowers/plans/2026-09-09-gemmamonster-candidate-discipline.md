# Gemmamonster Candidate Discipline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a small repository-native discipline layer that prevents branch confusion, unverifiable binaries, and unsupported known-good claims.

**Architecture:** Keep existing Gemma4 build/test scripts as the low-level engine. Add a Gemmamonster wrapper layer that creates candidate manifests, candidate artifact directories, launch records, promotion gates, and human-readable ledgers. The wrappers must refuse to make runtime or known-good claims unless source SHA, binary SHA256, command output, and test summaries exist.

**Tech Stack:** PowerShell 5+ on Windows, Git CLI, Bazel-driven existing OVMS build scripts, JSON manifests, Markdown ledgers.

**Spec:** `docs/gemmamonster/CANDIDATE-DISCIPLINE.md`

## Global Constraints

- Never touch `main`, `integration/gemma4-protocol-hardening-2026.5`, tags, or upstream refs from these scripts.
- Candidate identity requires `source_sha`, `tree_sha`, `branch`, `binary_sha256`, `build_profile`, and `status`.
- A binary without a manifest is not a candidate.
- A launched process without a recorded manifest/hash/PID is not accepted runtime evidence.
- Source PASS, build PASS, protocol PASS, and live PASS are separate statuses.
- Devstral tokenizer absence is not a Gemma4 parser failure unless a Gemma4 test depends on it.

---

### Task 1: Documentation and ledgers

**Files:**
- Create: `docs/gemmamonster/CANDIDATE-DISCIPLINE.md`
- Create: `docs/gemmamonster/BRANCH-LEDGER.md`
- Create: `docs/gemmamonster/KNOWN-GOOD.md`
- Create: `docs/gemmamonster/acceptance/README.md`

**Interfaces:**
- Consumes: current Gemmamonster branch/test discipline.
- Produces: stable human-readable rules used by wrappers and agents.

- [ ] **Step 1: Write candidate discipline doc**

Document branch lanes, candidate identity fields, artifact layout, manifest rules, launcher rules, promotion rules, and agent handoff block.

- [ ] **Step 2: Write branch ledger seed**

Add entries for `integration/gemma4-parser-generator-refit-next`, `test/gemmamonster-gate12-20260909-e398363c`, and this infra branch. Mark their statuses explicitly.

- [ ] **Step 3: Write known-good seed**

Record that `e398363c2fe6f572a0fdc3ed9fd37c551fd73c76` is source-ported but not machine accepted.

- [ ] **Step 4: Commit**

```bash
git add docs/gemmamonster/CANDIDATE-DISCIPLINE.md docs/gemmamonster/BRANCH-LEDGER.md docs/gemmamonster/KNOWN-GOOD.md docs/gemmamonster/acceptance/README.md
git commit -m "docs(gemmamonster): define candidate discipline"
```

### Task 2: Candidate build wrapper

**Files:**
- Create: `scripts/gemmamonster/build-candidate.ps1`

**Interfaces:**
- Consumes: `scripts/gemma4/build-local-candidate.ps1`, optional `scripts/gemma4/test-protocol-hardening.ps1`.
- Produces: candidate directory with `manifest.json`, `ovms.exe`, `build.log`, copied legacy candidate metadata, optional protocol logs, and `sha256sums.txt`.

- [ ] **Step 1: Add wrapper**

The wrapper resolves the Git branch/SHA/tree, rejects dirty trees unless explicitly allowed, invokes the existing Gemma4 builder, copies `ovms.exe` into a stable artifact directory, computes SHA256, and writes `manifest.json`.

- [ ] **Step 2: Add optional protocol run**

When `-RunProtocol` is passed, run `scripts/gemma4/test-protocol-hardening.ps1`, copy its newest `summary.json`, and mark `tests.overall` from the summary.

- [ ] **Step 3: Commit**

```bash
git add scripts/gemmamonster/build-candidate.ps1
git commit -m "feat(gemmamonster): add manifest-first candidate build wrapper"
```

### Task 3: Candidate launch wrapper

**Files:**
- Create: `scripts/gemmamonster/launch-candidate.ps1`

**Interfaces:**
- Consumes: candidate `manifest.json` and copied `ovms.exe`.
- Produces: `runtime/<timestamp>/launch.json`, stdout/stderr logs, optional `/v1/models` healthcheck record.

- [ ] **Step 1: Add launcher**

The launcher refuses to run if the manifest is missing, binary hash does not match, model path is missing, or the requested REST port is already occupied.

- [ ] **Step 2: Record process identity**

Write PID, source SHA, binary SHA256, command line, model path, port, and start time into `launch.json`.

- [ ] **Step 3: Commit**

```bash
git add scripts/gemmamonster/launch-candidate.ps1
git commit -m "feat(gemmamonster): add manifest-checked candidate launcher"
```

### Task 4: Promotion gate

**Files:**
- Create: `scripts/gemmamonster/promote-candidate.ps1`

**Interfaces:**
- Consumes: candidate `manifest.json`.
- Produces: local acceptance markdown scaffold and a hard gate that refuses promotion without PASS evidence.

- [ ] **Step 1: Add gate checks**

The script verifies candidate manifest, source SHA, binary SHA256, required logs, and protocol PASS before allowing integration/freeze promotion claims.

- [ ] **Step 2: Add acceptance scaffold output**

Generate a Markdown report under `docs/gemmamonster/acceptance/` when checks pass or when `-DryRun` is requested.

- [ ] **Step 3: Commit**

```bash
git add scripts/gemmamonster/promote-candidate.ps1
git commit -m "feat(gemmamonster): add candidate promotion gate"
```

### Task 5: Static review and handoff

**Files:**
- Modify: the files created above if review finds contradictions.

**Interfaces:**
- Consumes: final diff on the infra branch.
- Produces: exact branch/HEAD/files summary for review.

- [ ] **Step 1: Run syntax checks locally**

```powershell
Get-ChildItem scripts/gemmamonster/*.ps1 | ForEach-Object { $null = [System.Management.Automation.PSParser]::Tokenize((Get-Content $_.FullName -Raw), [ref]$null) }
```

- [ ] **Step 2: Run dry-run checks**

```powershell
.\scripts\gemmamonster\promote-candidate.ps1 -CandidateManifest C:\missing\manifest.json -DryRun
```

Expected: nonzero failure due to missing manifest.

- [ ] **Step 3: Report actual state**

Return `BRANCH`, `HEAD_SHA`, `FILES_CHANGED`, `TESTS`, `KNOWN_FAILURES`, and `NOT_RUN` sections. Do not claim build/runtime PASS without fresh evidence.
