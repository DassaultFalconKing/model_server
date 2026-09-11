# GEMMAMONSTER Frankenstein experimental probe

- Source repository: https://github.com/DassaultFalconKing/gemmamonster_model_server_OVMS.git
- Mutable source ref: local/experimental-gemmamonster-xgrammar026
- Authoritative source SHA: c5115ba494729f5af40d3ab733c8e49c339932b0
- Scope: evidence-only archival of the 2026-09-11 local runtime acceptance campaign.

## Included material

Raw OpenAI-compatible requests and responses, test summaries, trace excerpt, runtime logs, startup logs, and the final verdict. No product source, build output, binaries, model weights, or credentials are included.

## Result

`FRANKENSTEIN_TAB_LOOP_NOT_FIXED`. The deterministic three-call prompt generated 256 tokens, including 344 consecutive decoded whitespace characters, then stopped by length. A later GPU `CL_OUT_OF_RESOURCES` fault was contained: the server and `/v3/models` survived while the same model executor was quarantined.

## Limitations

The available `ovms_test.exe` exited with `-1073741515` before gtest inventory, so the source contract test was not executed. Streaming and multiturn cases were not run because the executor was already quarantined. This archive is runtime evidence, not product-source authority or acceptance promotion.