# Gemma4 Google-template runtime contract

This branch deliberately separates model weights from chat-template authority.

## Authority

- **IR / quantized weights:** the existing Wondernutts OpenVINO export.
- **Chat template:** current `google/gemma-4-26B-A4B-it` `chat_template.jinja`, resolved to an exact Hugging Face commit at overlay-preparation time.
- **Runtime:** newest mutually compatible Windows OpenVINO + OpenVINO GenAI selected for the acceptance run; exact binaries/DLL hashes are evidence.
- **OVMS source:** exact Git SHA of this branch.

The Wondernutts `chat_template.jinja` is never copied into the runtime overlay.

## Prepare the runtime model overlay

```powershell
pwsh .\scripts\gemma4\prepare-google-template-overlay.ps1 `
  -SourceModelPath 'C:\llm\models\OpenVINO\Wondernutts\gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov' `
  -OverlayPath 'C:\llm\models\runtime\gemma4-26-heretic-google-current' `
  -LinkMode Auto `
  -Force
```

`Auto` prefers NTFS hardlinks. It refuses to silently copy a large model file if a hardlink is unavailable; place the overlay on the same volume or request `-LinkMode Copy` explicitly.

The script resolves Google `main` to an exact 40-hex revision, downloads only the template from that revision, validates Gemma4 tool markers, and writes:

`gemma4-template-provenance.json`

For reproduction of a previous run, pass the recorded SHA:

```powershell
-GoogleRevision <exact-40-hex-sha>
```

## Session persistence

Set a persistent store before launching OVMS:

```powershell
$env:OVMS_SESSION_STORE_DIR = 'C:\llm\ovms-session-store'
$env:OVMS_SESSION_CACHE_ENTRIES = '64'
$env:OVMS_SESSION_MAX_BYTES = '1073741824'
$env:OVMS_SESSION_MAX_REQUEST_BYTES = '8388608'
```

Clients opt in per chain with:

```text
X-OVMS-Session-ID: <stable-session-id>
```

The first turn establishes the session seed. If the request omits `seed`, OVMS creates one non-zero uint32 seed and injects it. Every later turn reuses that seed. A conflicting explicit seed fails before generation.

Each turn journals:

```text
<store>/<session>/turns/<turn>/raw-request.json
<store>/<session>/turns/<turn>/effective-request.json
<store>/<session>/turns/<turn>/generation-config.json
```

`manifest.json` is durable. Only bounded manifest metadata is cached in RAM; full request history remains on disk.

## Collect runtime provenance

```powershell
pwsh .\scripts\gemma4\collect-runtime-provenance.ps1 `
  -OvmsPath 'C:\llm\ovms\ovms.exe' `
  -OpenVinoDir $env:OpenVINO_DIR `
  -RepoPath $PWD `
  -TemplateProvenancePath 'C:\llm\models\runtime\gemma4-26-heretic-google-current\gemma4-template-provenance.json' `
  -OutputPath '.\ab-evidence\newest-runtime\runtime-provenance.json'
```

Acceptance is invalid if runtime provenance is missing or if OVMS is launched against the source Wondernutts model directory instead of the prepared Google-template overlay.

## Launch invariant

The launch/model path must point to the overlay:

```text
C:\llm\models\runtime\gemma4-26-heretic-google-current
```

not to the source export.

## Sampling discipline

A chain uses one immutable session seed. Sampling profiles are compared across distinct session IDs. Do not change temperature/top-p/top-k mid-chain.

The live harness records `session-config.json` and supports a restart proof:

1. run with `--stop-after-tool-result`;
2. stop and restart OVMS;
3. rerun the same harness/output directory with `--resume`;
4. verify the session journal shows the same seed on both turns.

The server-side session journal is the authority for the **effective** seed when the client uses `--omit-seed`.
