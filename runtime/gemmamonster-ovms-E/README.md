# Runtime profile E

Profile **E** is the current working Gemma4 profile on the Windows/Intel Arc target and is the primary runtime profile for the OVMS 2026.5 forward-port.

The machine-readable contract is `profile.json`. Launch it through `scripts/gemma4/launch-gemma4-candidate.ps1 -Profile E` rather than editing a committed `config.json` with machine-specific absolute paths.

Pinned working properties:

- `device: GPU`
- `pipeline_type: VLM_CB`
- `max_num_seqs: 1`
- `DYNAMIC_QUANTIZATION_GROUP_SIZE: 0`
- `KV_CACHE_PRECISION: u8`
- `enable_prefix_caching: true`
- default `chat_template_mode: JINJA`
- `max_tokens_limit: 65536`

`cache_size` is deliberately not pinned in E because the exact currently working value is not present in the frozen repository evidence. The launcher therefore omits that option for E. It must not silently inherit B2's `0` or C's `8` merely to make the file look complete.

`Stable` and `PrefixCache` in the launcher are diagnostic comparison profiles. They are not aliases for E.
