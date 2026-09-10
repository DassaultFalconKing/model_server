# Gemmamonster Candidate Acceptance Report

Generated UTC: 2026-09-09T21:03:32.9775088Z

## Candidate identity

| Field | Value |
| --- | --- |
| Source SHA | $(@{schema_version=1; project=Gemmamonster; repository=DassaultFalconKing/model_server; created_at_utc=09/09/2026 20:12:50; label=gate12-opencode; candidate_name=01ea946a-gate12-opencode-20260909T200627Z; candidate_dir=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z; branch=test/gemmamonster-gate12-20260909-e398363c; source_sha=01ea946a5dc8a179a91e8c42e77f0f7a443bc343; tree_sha=3b97ce638d7354fc659ee5a631bc3a669459cb6d; repo_dirty=True; build_profile=; build_command=scripts/gemma4/build-local-candidate.ps1 -RepoRoot C:\git\model_server-gemma4-fast -ShortRoot g5 -Label gate12-opencode; build_log=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\build.log; binary=; legacy_candidate=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\legacy-candidate.json; versions_mk_sha256=9bf9f06ee178b27afad9df8f8d412bdd4342672e5fb926431adf0ec86b75ee6e; tests=; launch=; status=built_not_accepted}.source_sha) |
| Tree SHA | $(@{schema_version=1; project=Gemmamonster; repository=DassaultFalconKing/model_server; created_at_utc=09/09/2026 20:12:50; label=gate12-opencode; candidate_name=01ea946a-gate12-opencode-20260909T200627Z; candidate_dir=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z; branch=test/gemmamonster-gate12-20260909-e398363c; source_sha=01ea946a5dc8a179a91e8c42e77f0f7a443bc343; tree_sha=3b97ce638d7354fc659ee5a631bc3a669459cb6d; repo_dirty=True; build_profile=; build_command=scripts/gemma4/build-local-candidate.ps1 -RepoRoot C:\git\model_server-gemma4-fast -ShortRoot g5 -Label gate12-opencode; build_log=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\build.log; binary=; legacy_candidate=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\legacy-candidate.json; versions_mk_sha256=9bf9f06ee178b27afad9df8f8d412bdd4342672e5fb926431adf0ec86b75ee6e; tests=; launch=; status=built_not_accepted}.tree_sha) |
| Branch | $(@{schema_version=1; project=Gemmamonster; repository=DassaultFalconKing/model_server; created_at_utc=09/09/2026 20:12:50; label=gate12-opencode; candidate_name=01ea946a-gate12-opencode-20260909T200627Z; candidate_dir=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z; branch=test/gemmamonster-gate12-20260909-e398363c; source_sha=01ea946a5dc8a179a91e8c42e77f0f7a443bc343; tree_sha=3b97ce638d7354fc659ee5a631bc3a669459cb6d; repo_dirty=True; build_profile=; build_command=scripts/gemma4/build-local-candidate.ps1 -RepoRoot C:\git\model_server-gemma4-fast -ShortRoot g5 -Label gate12-opencode; build_log=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\build.log; binary=; legacy_candidate=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\legacy-candidate.json; versions_mk_sha256=9bf9f06ee178b27afad9df8f8d412bdd4342672e5fb926431adf0ec86b75ee6e; tests=; launch=; status=built_not_accepted}.branch) |
| Candidate directory | $candidateDir |
| Binary SHA256 | $actualBinarySha |
| Status | $status |
| Target branch | $TargetBranch |

## Evidence

| Gate | Status | Evidence |
| --- | --- | --- |
| Build | PASS | $buildLog |
| Protocol | $protocolOverall | $protocolSummary |
| Launch/live | NOT_RUN | $(@{schema_version=1; project=Gemmamonster; repository=DassaultFalconKing/model_server; created_at_utc=09/09/2026 20:12:50; label=gate12-opencode; candidate_name=01ea946a-gate12-opencode-20260909T200627Z; candidate_dir=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z; branch=test/gemmamonster-gate12-20260909-e398363c; source_sha=01ea946a5dc8a179a91e8c42e77f0f7a443bc343; tree_sha=3b97ce638d7354fc659ee5a631bc3a669459cb6d; repo_dirty=True; build_profile=; build_command=scripts/gemma4/build-local-candidate.ps1 -RepoRoot C:\git\model_server-gemma4-fast -ShortRoot g5 -Label gate12-opencode; build_log=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\build.log; binary=; legacy_candidate=C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\legacy-candidate.json; versions_mk_sha256=9bf9f06ee178b27afad9df8f8d412bdd4342672e5fb926431adf0ec86b75ee6e; tests=; launch=; status=built_not_accepted}.launch.latest_launch_json) |

## Promotion decision

Dry run: $(True.IsPresent)

Promotion is permitted only when this report is backed by the manifest and logs above. This script does not move protected branches or tags automatically.

## Required handoff

`	ext
BRANCH: test/gemmamonster-gate12-20260909-e398363c
HEAD_SHA: 01ea946a5dc8a179a91e8c42e77f0f7a443bc343
BUILD: PASS, see C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\build.log
TESTS: FAIL, see C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z\protocol-summary.json
ARTIFACTS: C:\gemmamonster-artifacts\candidates\01ea946a-gate12-opencode-20260909T200627Z
PROMOTION_RECOMMENDATION: review and fast-forward/cherry-pick manually after evidence review
`
