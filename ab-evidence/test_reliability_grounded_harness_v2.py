import json
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import reliability_grounded_harness_v2 as v2


class FakeLegacy:
    @staticmethod
    def extract_tool_calls(response):
        choices = (response or {}).get("choices") or []
        if not choices:
            return None, [], None
        choice = choices[0]
        message = choice.get("message") or {}
        return message, message.get("tool_calls") or [], choice.get("finish_reason")


class HarnessV2ContractTests(unittest.TestCase):
    def test_sampled_thinking_cells_omit_seed(self):
        args = SimpleNamespace(
            n_think_off=0,
            n_think_on=0,
            n_think_sample_off=2,
            n_think_sample_on=3,
        )
        cells = v2.strict_thinking_cells(args)
        sampled = {cell[1]: cell for cell in cells}
        self.assertEqual(sampled["thinking_off_t09_seed_omitted"][3], "omitted")
        self.assertEqual(sampled["thinking_on_t09_seed_omitted"][3], "omitted")

    def test_campaign_a_rejects_multiple_tool_calls(self):
        trial = {
            "response": {
                "choices": [{
                    "message": {
                        "tool_calls": [
                            {"function": {"name": "publish_review_evidence"}},
                            {"function": {"name": "extra_call"}},
                        ]
                    }
                }]
            }
        }
        outcome, reason = v2.strict_classify_campaign_a(
            FakeLegacy,
            lambda _: ("PASS", "legacy-pass"),
            trial,
        )
        self.assertEqual(outcome, "D_WRONG_TOOL")
        self.assertIn("exactly one", reason)

    def test_allow_no_tool_rejects_any_structured_call(self):
        trial = {
            "allow_no_tool": True,
            "response": {
                "choices": [{
                    "message": {
                        "tool_calls": [
                            {"function": {"name": "publish_exact_facts", "arguments": "{}"}}
                        ]
                    }
                }]
            },
        }
        outcome, reason = v2.strict_classify_campaign_b(
            FakeLegacy,
            lambda _: ("PASS", "legacy-pass"),
            trial,
        )
        self.assertEqual(outcome, "D_WRONG_TOOL")
        self.assertIn("forbidden", reason)

    def test_summary_renames_parser_metric_and_marks_scope(self):
        source = {
            "key_rates": {
                "parser_recognition_conditional_on_attempted_call": {"n": 10, "k": 10}
            },
            "cells": {
                "x": {
                    "parser_recognition_conditional_on_attempted_call": {"n": 1, "k": 1}
                }
            },
        }
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "summary.json"
            path.write_text(json.dumps(source), encoding="utf-8")
            v2.augment_summary(path)
            data = json.loads(path.read_text(encoding="utf-8"))
        self.assertNotIn("parser_recognition_conditional_on_attempted_call", data["key_rates"])
        self.assertIn(
            "api_visible_parser_recognition_conditional_on_api_visible_attempted_call",
            data["key_rates"],
        )
        self.assertEqual(data["measurement_contract"]["parser_attempt_observability"], "api_visible_only")


if __name__ == "__main__":
    unittest.main()
