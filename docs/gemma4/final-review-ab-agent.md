# Independent OpenCode A/B acceptance

You are the independent A/B tester for the Gemma4 tool-calling final review.
The reviewer is implementing fixes in C:/git/g4-final-review. Do not edit its
production sources, tests, build files, branches, or model configuration.

Stage A now: create a reusable Python standard-library HTTP test harness and
run the baseline. Save harness and all evidence under
C:/git/gemma4-acceptance-evidence-20260906/final-review-ab/.
When stage A is complete, report results and your session ID, then stop. The
reviewer will continue your session with the built B binary. Do not wait or
poll for B and do not build either variant yourself.

Baseline A source: be410567f2b3f8146eda87087beb59b67199c893.
Baseline binary: C:/git/model_server-gemma4-fast/bazel-bin/src/ovms.exe.
Model name: gemma4-26-heretic.
Model path: C:/llm/models/OpenVINO/Wondernutts/gemma-4-26B-A4B-it-qat-q4_0-unquantized-uncensored-heretic-int4-ov.
Use this same already-fixed graph and model/template/tokenizer for A and B.
Record binary, graph, template and tokenizer-config SHA256 hashes. Never load
both variants at once on the GPU. Check REST 18000 and gRPC 19000 are free
before launching; never kill an existing process you did not start.

Start OVMS with --model_path MODEL_PATH --model_name gemma4-26-heretic
--rest_port 18000 --port 19000 --log_level DEBUG --log_path EVIDENCE_LOG.
For the child process prepend PATH with C:/llm/ovms/python;
C:/opt/openvino/runtime/bin;C:/opt/openvino/runtime/3rdparty/tbb/bin;
C:/opt/opencv_4.14.0/x64/vc17/bin;C:/opt/Python312;
C:/git/model_server-gemma4-fast. Set PYTHONHOME=C:/opt/Python312 and
PYTHONPATH=C:/llm/ovms/python;C:/opt/Python312/Lib/site-packages.
Use C:/opt/Python312/python.exe for the harness. Save stdout/stderr and server
logs, poll readiness with a bounded 180-second deadline, terminate only the
child you started in finally, and verify ports were released. On Windows
background helpers must run hidden.

Use temperature 0, fixed seed if supported, identical prompts and limits for
A and B. Keep a practical runtime corpus (about 10-14 cases, 256-768 output
tokens per case, 180-second request deadline): unary text; streaming text;
auto tool selection; named nested tool call using the four tools in
C:/git/gemma4-acceptance-evidence-20260906/complex-tool-catalog.json;
required call; none; tool result roundtrip; streaming nested tool call;
low-token truncation; required without tools (expect 4xx); named without
tools (expect 4xx); parameterless function; literal <tool_call|> inside a JSON
string. Do not execute generated tools: this harness validates their wire
contract. Use a deterministic synthetic tool response for the roundtrip.
Do not label six planned cases in generated arguments as six executed tests.

For each case save exact request and raw response/SSE, status, elapsed time,
finish reason, parsed tool arguments, shape/type checks, tool count and IDs,
and whether protocol markers leaked outside valid argument strings. For
SSE reconstruct every indexed call without filtering empty calls or sparse
indices. Distinguish PARSER, GENERATION_CONTRACT, MODEL_QUALITY, TRUNCATION,
GPU_RUNTIME and HARNESS_ERROR; record uncertainty rather than guessing.

No commits, push, remote publishing, model changes or external tool actions.
Only this local evidence directory is writable by you. If provider access or
tool permissions fail, report the exact blocker; do not change credentials
or global OpenCode permissions. Do not use --auto to bypass permissions.
