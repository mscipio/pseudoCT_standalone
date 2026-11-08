"""Print key=value lines for the last launcher result record (type "result").

Usage: pseudo_CT_result_fields.py OUTPUT_FILE

Used by pseudo_CT_launch_request('invoke') on the stdout of `bin/pseudoct run ...
--format jsonl`; the last result record in the file wins. Exit 3 when no result
record is present.
"""
import json
import sys

FIELDS = ("outcome", "exit_code", "submission_status", "authentication_status",
          "dispatch_status", "scientific_completion_status", "backend",
          "error_code", "error_message", "invocation_id", "profile", "action")


def clean(value):
    """Return VALUE as one line: None becomes "", lists are space-joined, whitespace collapses."""
    if value is None:
        return ""
    if isinstance(value, list):
        return " ".join(str(item) for item in value)
    return " ".join(str(value).split())


def main():
    """Print the FIELDS of the last result record; exit 3 when there is none."""
    record = None
    with open(sys.argv[1], encoding="utf-8", errors="replace") as handle:
        for line in handle:
            text = line.strip()
            if not text.startswith("{"):
                continue
            try:
                candidate = json.loads(text)
            except ValueError:
                continue
            if isinstance(candidate, dict) and candidate.get("type") == "result":
                record = candidate
    if record is None:
        sys.exit(3)
    for name in FIELDS:
        print("%s=%s" % (name, clean(record.get(name))))
    print("job_ids=%s" % clean(record.get("job_ids", [])))


if __name__ == "__main__":
    main()
