"""Outcome and exit mapping of the bin/pseudoct result block.

The block is the embedded python that reads the verified result summary and
prints the JSONL/text record. It is extracted from bin/pseudoct itself, so the
test exercises the shipped code, not a copy. No MATLAB, scheduler or science.
Run: python3 -I -B tests/test_pseudoct_outcome.py
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LAUNCHER = os.path.join(ROOT, "bin", "pseudoct")
MARKER = ('pyrun - "$summary_file" "$invocation_id" "$profile" "$action" '
          '"$format" "$backend" "$run_log_index" "${result_file:-}" "$subject_temp" <<\'PY\'')
INVOCATION = "6f1f5f0e-2b7a-4c1d-9e3a-0123456789ab"


def result_block():
    with open(LAUNCHER, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    start = lines.index(MARKER) + 1
    end = lines.index("PY", start)
    return "\n".join(lines[start:end]) + "\n"


def run_block(summary_values, output_format="jsonl"):
    """Run the block with one 10-line summary; returns (exit_code, stdout)."""
    with tempfile.TemporaryDirectory() as work:
        code_path = os.path.join(work, "block.py")
        summary_path = os.path.join(work, "summary.txt")
        log_index = os.path.join(work, "run-logs.txt")
        with open(code_path, "w", encoding="utf-8") as handle:
            handle.write(result_block())
        with open(summary_path, "w", encoding="utf-8") as handle:
            handle.write("\n".join(summary_values) + "\n")
        with open(log_index, "w", encoding="utf-8") as handle:
            handle.write("")
        completed = subprocess.run(
            [sys.executable, "-I", "-B", code_path, summary_path, INVOCATION,
             "mlsc", summary_values[8], output_format, summary_values[4],
             log_index, "", work],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, universal_newlines=True)
        return completed.returncode, completed.stdout


def summary(status, error_code, backend, science, dispatch, action="submit",
            submission="not_attempted", auth="not_attempted", ids="-"):
    # Ten values in the order the launcher writes them.
    return [status, error_code, auth, submission, backend, science, dispatch,
            ids, action, "-"]


class OutcomeMappingTest(unittest.TestCase):
    def test_local_unobserved_failure_is_unverified_not_scientific_failure(self):
        code, out = run_block(summary("failed", "-", "local", "not_observed",
                                      "dispatched"))
        record = json.loads(out)
        self.assertEqual(code, 68)
        self.assertEqual(record["outcome"], "scientific_completion_unverified")
        self.assertNotEqual(record["outcome"], "scientific_failed")
        self.assertIsNone(record["scientific_completion"])
        self.assertEqual(record["exit_code"], 68)

    def test_verified_local_failure_stays_scientific_failed(self):
        code, out = run_block(summary("failed", "-", "local", "failed", "dispatched"))
        record = json.loads(out)
        self.assertEqual(code, 68)
        self.assertEqual(record["outcome"], "scientific_failed")

    def test_verified_completion_is_scientific_completed_with_exit_zero(self):
        code, out = run_block(summary("submitted", "-", "local", "completed",
                                      "dispatched"))
        record = json.loads(out)
        self.assertEqual(code, 0)
        self.assertEqual(record["outcome"], "scientific_completed")

    def test_remote_accepted_without_completion_is_unverified(self):
        code, out = run_block(summary("submitted", "-", "mlsc", "not_observed",
                                      "dispatched", submission="accepted",
                                      auth="authenticated", ids="31415"))
        record = json.loads(out)
        self.assertEqual(code, 68)
        self.assertEqual(record["outcome"], "submission_accepted_completion_unverified")
        self.assertEqual(record["job_ids"], [31415])

    def test_text_output_uses_the_same_outcome(self):
        code, out = run_block(summary("failed", "-", "local", "not_observed",
                                      "dispatched"), output_format="text")
        self.assertEqual(code, 68)
        self.assertIn("pseudoct run: scientific_completion_unverified", out)
        self.assertNotIn("scientific_failed", out)


if __name__ == "__main__":
    unittest.main()
