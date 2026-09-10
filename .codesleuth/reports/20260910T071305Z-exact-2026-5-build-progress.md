---
reportType: documentation
targetSha: fde0762ba314dc5f6448726dfce7c533bad9a8a6
provenance: anon
reviewId: none
---

# Exact 2026.5 build: progress + blocker (short)

- date: 2026-09-10T07:13:05Z
- target: fde0762ba314dc5f6448726dfce7c533bad9a8a6
- branch: OVMS-Gemmamonster-acceptance-track (same HEAD)
- status: BLOCKED on OpenCV rebuild (missing VS2019 v142); user is installing it elevated
- provenance: anon

## Done

- Source authority: HEAD `fde0762` verified (`git cat-file -e` OK); pre-existing dirty `*.sh` unrelated, untouched.
- Worktree `C:\git\model_server-gemma4-2026.5-exact` created detached at `fde0762`, HEAD re-verified.
- `versions.mk` pins verified: OV 9b1d5c9, tokenizers 4813f2b, genai 2e3b291, package `openvino_genai_windows_2026.5.0.0.dev20260903_x86_64.zip`, opencv 4.14.0, curl 8.21.0_7.
- `windows_install_build_dependencies.bat g55 1 0` run: GenAI 2026.5 package downloaded + extracted to `C:\g55`, symlink `C:\g55\openvino` → dev20260903 package.
- G55 verified: openvino.dll `25C7B09A…`, genai `7D4EA32E…`, tokenizers `BF6423AC…`, `version.txt` = `2026.5.0-23005-9b1d5c9494e`; ZIP sha `195B6281…`.
- WORKSPACE in worktree transiently rewritten to `C:\g55\openvino\runtime` (uncommitted, as allowed).

## Damage (honest)

- Installer with expunge=1 deleted `C:\opt\opencv_4.14.0`, then failed rebuilding it: script hardcodes `cmake -T v142`, machine has only v143 (14.44). `C:\opt\openvino` (2026.4) and `C:\g5` intact (hashes re-verified).
- No Windows OVMS build on this machine can link until opencv_4.14.0 is restored (all WORKSPACEs point there).

## Blocker + recovery

- `vs_installer modify` needs elevation (my shell is not admin); user runs it elevated now (without the bogus `--wait` flag I first gave — my error, corrected).
- Resume at §10 (`windows_build.bat g55 --with_python`) once `C:\BuildTools\VC\Tools\MSVC\14.29.*` exists. If opencv rebuild succeeds, rerun tail of installer or continue; installer exit so far: 1 (opencv only).

## Limitations

- No source/config changes made; no commits; no merges. This doc is navigation, not acceptance.
