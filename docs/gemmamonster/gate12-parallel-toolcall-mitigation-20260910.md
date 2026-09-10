# Gate12 Parallel Tool-Call Mitigation - 2026-09-10

## Problem

Frozen Gate12 can pass plain output, named tool calling, auto single-tool calling, tool-result continuation, and reasoning extraction with the live `gemma4` parsers.

The original `06_parallel_two_weather` shape is not accepted reliably:

- one function schema: `weather({ city })`
- request asks for Paris and Berlin
- `parallel_tool_calls: true`

Observed outcomes:

- with larger mixed parallel prompts, the GPU path can fail with `CL_OUT_OF_RESOURCES`;
- with smaller budgets, the request returns `finish_reason: length` with no extracted `tool_calls`;
- the parser itself still passes simpler named/auto tool cases.

## Passing Workaround

Use alias fan-out for repeated calls to the same logical tool.

Instead of exposing one repeated schema:

```json
[
  { "type": "function", "function": { "name": "weather", "parameters": { "type": "object", "properties": { "city": { "type": "string" } }, "required": ["city"] } } }
]
```

expose per-call aliases:

```json
[
  { "type": "function", "function": { "name": "weather_paris", "parameters": { "type": "object", "properties": {}, "required": [] } } },
  { "type": "function", "function": { "name": "weather_berlin", "parameters": { "type": "object", "properties": {}, "required": [] } } }
]
```

Then map both aliases back to the same backend executor:

- `weather_paris` -> `weather({ "city": "Paris" })`
- `weather_berlin` -> `weather({ "city": "Berlin" })`

## Live Evidence

Evidence directory:

`C:\git\model_server-gemma4-fast\docs\gemmamonster\evidence\gate12-parallel-mitigation-20260910T0330Z`

Passing request:

`C:\git\model_server-gemma4-fast\docs\gemmamonster\evidence\gate12-parallel-mitigation-20260910T0330Z\fast-parallel-city-specific-tools.request.json`

Passing response:

`C:\git\model_server-gemma4-fast\docs\gemmamonster\evidence\gate12-parallel-mitigation-20260910T0330Z\fast-parallel-city-specific-tools.response.json`

Observed result:

- status: `HTTP_OK`
- elapsed: `1.364s`
- `finish_reason: tool_calls`
- tool calls: `2`
- names: `weather_paris,weather_berlin`
- args: `{}` and `{}`

## Engineering Interpretation

This does not prove that same-function repeated parallel tool calls are fixed in the server. It proves a safe compatibility pattern for agent runtimes:

1. Detect repeated logical tool calls before sending the prompt.
2. Create stable alias names for each planned call target.
3. Keep each alias schema narrow.
4. Let the model emit parallel calls to distinct names.
5. Normalize aliases back to the original tool implementation after parsing.

For OpenCode-style integration, this can be implemented in the provider/harness layer without changing the frozen Gate12 binary. A later server-side fix can investigate why repeated same-name parallel generation falls into empty `length` responses or GPU resource pressure.
