# Gemmamonster Jenkins and upstream lineage policy

## Purpose

Gemmamonster is maintained on multiple OVMS release lines at the same time. The repository default branch is therefore not a safe implicit PR target and not a safe source of Jenkins/build parameters.

A packaging or release assistant MUST resolve the OVMS version, an honest PR base, and the matching upstream Jenkins profile before creating a PR or claiming Jenkins compatibility.

## Versioned infrastructure branches

Infrastructure work is isolated per OVMS release line.

Branch convention:

```text
infra/gemmamonster-<YYYY.M>-jenkins-lineage
```

Examples:

```text
infra/gemmamonster-2026.4-jenkins-lineage
infra/gemmamonster-2026.5-jenkins-lineage
infra/gemmamonster-2026.6-jenkins-lineage
```

Do not forward-edit an older infrastructure branch to represent a newer OVMS release. Create the new version branch from the corresponding version line and port the Gemmamonster policy/patches deliberately.

## Two refs, two jobs

The assistant MUST keep these concepts separate:

- `PR_TARGET`: a branch in the Gemmamonster fork that has honest ancestry with the working branch and belongs to the same OVMS release line.
- `JENKINS_PROFILE_REF`: the matching canonical OpenVINO Model Server release branch from which Jenkins/build behavior is read.

For OVMS `2026.4.x`, the canonical Jenkins profile is:

```text
openvinotoolkit/model_server:releases/2026/4
```

The repository default `main` is never an implicit fallback for either field.

## Mandatory resolver protocol

Before package build, release validation, or PR creation, the coding assistant MUST perform the following steps.

### 1. Determine the product version from the checked-out tree

Read `PRODUCT_VERSION` from the branch's own build metadata, currently the `Makefile`, and cross-check version-bearing files such as `versions.mk` where useful.

Normalize to a release line:

```text
2026.4.0 -> 2026.4
2026.5.0 -> 2026.5
2026.6.0 -> 2026.6
```

Do not infer the version from the repository default branch, branch checkout directory name, or from a previously remembered run.

### 2. Resolve candidate PR bases in the fork

Fetch/inspect remote branches and consider only branches for the same normalized release line. Typical candidates include version anchors such as `main-2026.4`, versioned integration branches, and other explicitly maintained Gemmamonster release-line branches.

For each candidate compute ancestry against the working HEAD.

Preferred condition:

```bash
git merge-base --is-ancestor <candidate> HEAD
```

If several candidates are ancestors, choose the closest intended maintained base, not simply the branch with the lexicographically nicest name. Record the candidate HEAD and merge-base.

If no same-version maintained branch has defensible ancestry, stop PR creation. Do not silently target `main`.

### 3. Resolve the canonical upstream Jenkins profile

For normalized line `<YYYY.M>`, resolve the corresponding branch in `openvinotoolkit/model_server`:

```text
releases/<YYYY>/<M>
```

Examples:

```text
2026.4 -> releases/2026/4
2026.6 -> releases/2026/6
```

If the exact release branch does not exist, stop and report the unresolved Jenkins profile. Do not substitute upstream `main` or another release.

### 4. Read Jenkins/build behavior from that exact ref

At minimum inspect the matching version of:

```text
ci/build_test_OnCommit.groovy
ci/loadWin.groovy
Makefile
versions.mk
.bazelversion
windows_install_build_dependencies.bat
windows_build.bat
windows_create_package.bat
windows_test.bat
```

The release branch is the authority for CI/build mechanics. A command copied from another OVMS version is only a hint until verified against the selected profile.

### 5. Build and package against the selected profile

A PR is not ready merely because source-level tests pass. For package-oriented work the acceptance evidence must include compilation and package creation using commands compatible with the selected release-line Jenkins profile.

Do not claim Jenkins readiness unless the relevant local or CI-equivalent build steps passed.

### 6. Create the PR only after target evidence is fixed

The assistant must report at least:

```text
PRODUCT_VERSION=<full version>
RELEASE_LINE=<YYYY.M>
WORK_HEAD=<sha>
PR_TARGET=<branch>
PR_TARGET_HEAD=<sha>
MERGE_BASE=<sha>
JENKINS_PROFILE_REF=releases/<YYYY>/<M>
JENKINS_PROFILE_HEAD=<sha>
COMPILE=<PASS|FAIL|NOT_RUN>
PACKAGE=<PASS|FAIL|NOT_RUN>
TESTS=<PASS|FAIL|NOT_RUN>
```

A PR MUST NOT be created when `PR_TARGET`, `MERGE_BASE`, or `JENKINS_PROFILE_REF` is unresolved.

## Jenkins PR behavior

OVMS Jenkins already uses the PR target when calculating change scope: on a PR it fetches `${CHANGE_TARGET}`, computes a merge-base with `HEAD`, and derives the changed files from that base. Therefore selecting the correct version target is part of the CI contract, not cosmetic GitHub metadata.

If a 2026.4 patch is submitted to a 2026.5 target, Jenkins is entitled to test it as a 2026.5 change. That failure is a targeting error, not evidence that the 2026.4 patch is invalid.

## Current 2026.4 policy

The 2026.4 packaging lineage is intentionally kept independent of the repository's newer default line.

Current infrastructure branch:

```text
infra/gemmamonster-2026.4-jenkins-lineage
```

It was created from:

```text
fix/gemmamonster-2026.4-package
14a7d870578f201c3e96837e5e86ce030b7b74ff
```

The build metadata on that line declares `PRODUCT_VERSION = 2026.4.0`.

Canonical Jenkins profile:

```text
openvinotoolkit/model_server:releases/2026/4
```

The existence of a newer 2026.5 `main` does not change this contract.

## New OVMS release procedure

When a new OVMS release line appears, for example 2026.6:

1. Resolve and pin the new canonical upstream release branch `releases/2026/6`.
2. Create `infra/gemmamonster-2026.6-jenkins-lineage` from the corresponding Gemmamonster 2026.6 base, not from the 2026.4 infrastructure branch.
3. Diff the new release's Jenkins/build files against the previous supported release.
4. Port Gemmamonster patches onto the new release line.
5. Re-establish compile, package, and relevant test evidence under the 2026.6 Jenkins profile.
6. Only then open PRs against the honest 2026.6 fork target.

This is a per-version lifecycle. Older version branches remain historical evidence and maintenance surfaces rather than being rewritten to follow `main`.
