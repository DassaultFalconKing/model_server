# Gemma4 RC1 reviewed contracts implementation plan

Goal: repair the two reviewed P1s and make the Gemma4 builder contract explicit while preserving the runtime-proven predecessor.

Base: 0a537f08987a3df4c0254c1614162c06ac20b968. Isolated branch: fix/gemma4-rc1-reviewed-contracts.
Spec: user attachment f6984593-1f1d-4a6b-b693-d55d4f576e9c/pasted-text.txt. Later portability is a design constraint, not a request to change other runners now.

## Constraints
- Preserve native fallback; do not repair truncated JSON or change shared native scanner semantics.
- Gemma4 opts into tool-start termination of reasoning. Other combinations default off.
- Hard choices start tool structure immediately; auto permits content and optional tools.
- Keep P1-A, P1-B, and builder relocation independently reviewable commits.
- Do not edit Cursor's active regression worktree or GPU recovery/runtime service.
- Distinguish compilation, focused real-source gtests, full Bazel target, and GPU runtime evidence.

## Execution
- [x] Resolve remote and local predecessor; read production request, builder, parser, and streamer path.
- [x] Snapshot Cursor drafts outside its active worktree (hashes retained in evidence).
- [ ] Reproduce Cursor P1 tests against predecessor with real GenAI tokenizer and actual production C++ sources.
- [ ] Commit the reviewed tests; preserve tests of inherited limitations as evidence, not new acceptance scope.
- [ ] P1-A: select ordinary JSON by the first non-whitespace argument character (quoted key or empty object); incrementally scan strings, escapes, and nested containers; only parse a complete observed object; never fall through invalid guided JSON to native coercion. Native input retains its existing scanner and serializer.
- [ ] Add every-byte split, escaped quote/backslash, nested heterogeneous JSON, and truncation tests; run RED then GREEN.
- [ ] P1-B: add parser-owned capability and use it only for opted-in reasoning/tool transitions. Test Gemma4 and Qwen3/Hermes3 with the real streamer; inspect ordering of markers and token-ID routing.
- [ ] Relocate Gemma4GenerationConfigBuilder to gemma4/generation_config_builder.hpp and .cpp, wire src/llm/BUILD, no semantic changes in that commit.
- [ ] Builder: preserve TagsWithSeparator and TriggeredTags unless executable GenAI evidence disproves them; test none/auto/required/named, guided flag, absent/empty/missing schema, named filtering, schema fidelity, response format conflict, decoding and stop limits.
- [ ] Trace validation errors through extractInputRequest; hard choice may not silently downgrade to unconstrained generation. Keep model-specific policy owned by builder.
- [ ] Run relevant existing parser/builder/API tests, full relevant Bazel target, build, and bounded runtime smoke if a separate test instance is available.
- [ ] Review diff and issue an evidence-linked engineering report with exact HEADs, architecture verdict, outstanding blockers and inherited limitations.

## Current evidence and design caveats
Cursor drafts are still being edited. Initial parser draft SHA256: 2C76957EFB1A1A9F6746A1784BEC90B1EFDCB2A6B7FAD57A774BB8732F30292F.
Builder draft SHA256: 24E68AC81200604103E6D56797C1081F10CAE18FDE7BF0812A71CFDDA4A0B637.
The builder draft currently has include/API shape errors and characterizes silent constraint overwrite rather than an agreed contract.
Some direct parser draft tests assume a single optional Delta can contain multiple calls and content. Compare against the actual streamer's one-Delta invocation contract before interpreting failures.
Focused harness uses production source plus real previously compiled dependency libraries, not stub parser/tokenizer implementations. It is not a substitute for a fresh canonical Bazel build.
