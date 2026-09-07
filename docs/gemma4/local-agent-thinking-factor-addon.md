# Addendum: thinking mode as a reliability factor

Add one controlled sub-campaign to `local-agent-grounded-facts-test-handoff.md`.

Google's current Gemma 4 function-calling guide explicitly states that thinking improves function-calling accuracy. Therefore do not treat `enable_thinking` as an irrelevant presentation option.

## Required comparison

Hold constant:

- production SHA/binary/model
- prompt and tools
- `tool_choice=auto`
- `temperature=0`
- `seed=42`
- max tokens large enough not to truncate thinking

Run at least:

- thinking disabled: 30 trials
- thinking enabled: 30 trials

Then repeat a smaller sampling cell if budget allows:

- thinking disabled, `temperature=0.9`, seed omitted: 20 trials
- thinking enabled, `temperature=0.9`, seed omitted: 20 trials

Record the actual `chat_template_kwargs`/effective template mode and preserve verbose/raw output with special tokens when possible.

Report separately whether thinking changes:

1. `A_NO_TOOL_DECISION` rate;
2. malformed/noncanonical protocol attempt rate;
3. wrong-tool rate;
4. grounded exact-value fidelity conditional on an intended parsed call;
5. latency/token overhead.

Do not mix the thinking comparison into the main temperature/seed cells when calculating their primary Wilson intervals; report it as a separate controlled axis.
