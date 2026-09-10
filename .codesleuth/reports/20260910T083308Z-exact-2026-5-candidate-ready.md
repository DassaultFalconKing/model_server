---
reportType: documentation
targetSha: fde0762ba314dc5f6448726dfce7c533bad9a8a6
provenance: anon
reviewId: none
---

# Exact 2026.5 candidate built: COHERENT_2026_5_CANDIDATE_READY (short)

- date: 2026-09-10T08:33:08Z
- target: fde0762ba314dc5f6448726dfce7c533bad9a8a6
- branch: OVMS-Gemmamonster-acceptance-track
- provenance: anon

## Result

`COHERENT_2026_5_CANDIDATE_READY`. Candidate root: `C:\gemmamonster-artifacts\candidates\2026.5\fde0762-ov2026.5-dev20260903` (ovms\ + ovms.zip 138809319 bytes, sha `468DA423…59E6E`).

- source == fde0762 (detached worktree, parsers untouched; only WORKSPACE + opencv BUILD transient-uncommitted)
- dep root `C:\g55`, package `openvino_genai_windows_2026.5.0.0.dev20260903_x86_64`
- `--version`: OVMS 2026.5.0 / OV backend 2026.5.0-23005-9b1d5c9494e / GenAI 2026.5.0.0-3421-2e3b291a30e — no 2026.4
- built exe `DA505F7B…AC` (22930432) == packaged exe; packaged DLLs == g55 hashes; opencv == v143 system build
- self-contained smoke PASS via own setupvars.bat with system-only PATH
- old known-good `9926F8B5…` untouched (separate artifact)

## Deviations (documented, version-exactness kept)

- opencv 4.14.0 source-built with VS2022 v143 (official script demands absent v142); BUILD vc16→vc17 worktree-local; stale vc16 removed; prebuilt exe/zip kept at `C:\opt\opencv-4.14.0-windows.exe`
- pixi python3-shim (3.14, broken stdlib resolution) shadowed by `C:\g55\pyfix` copies of 3.12 for bazel fetch env only; user setup untouched
- leaked PYTHONHOME in my shell poisoned first attempt; fixed + server shutdown + `bazel clean` (g55 root only)

## Deferred

- LOADED_* module check → protocol acceptance launch (per §18). MIXED_2026_4_COMPONENTS: NO (file provenance).
- Full evidence: manifest.json, SHA256SUMS.txt (2954 files), provenance/*.json, logs/win_build.log inside CandidateRoot.
