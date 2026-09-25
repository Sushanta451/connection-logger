#!/usr/bin/env python3
"""Print whatever the review run recorded about its own failure.

anthropics/claude-code-action logs a trimmed result object that leaves out the
error text, so a failed review reads as "Claude produced no verdict" with no
cause. The execution file it writes does have the detail; this pulls out the
parts worth reading and puts them in the job log and summary.
"""

import json
import os
import sys

KEYS_OF_INTEREST = (
    "result", "error", "message", "subtype", "is_error",
    "api_error_status", "stop_reason", "num_turns", "total_cost_usd",
    "permission_denials", "terminal_reason",
)


def emit(text: str) -> None:
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as handle:
            handle.write(text + "\n")


def interesting(event: dict) -> dict:
    return {k: event[k] for k in KEYS_OF_INTEREST if k in event and event[k] not in (None, [], {})}


def main() -> None:
    path = os.environ.get("EXECUTION_FILE", "").strip()
    if not path or not os.path.exists(path):
        emit(f"## Review diagnostics\n\nNo execution file to read (EXECUTION_FILE={path!r}).")
        return

    with open(path, encoding="utf-8") as handle:
        raw = handle.read()

    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        emit("## Review diagnostics\n\nExecution file is not JSON; last 2000 characters:\n\n"
             f"```\n{raw[-2000:]}\n```")
        return

    events = data if isinstance(data, list) else [data]
    results = [e for e in events if isinstance(e, dict) and e.get("type") == "result"]
    errors = [e for e in events if isinstance(e, dict) and (e.get("is_error") or e.get("error"))]

    lines = ["## Review diagnostics\n"]
    for label, chosen in (("Result", results[-1:]), ("Errors", errors[-3:])):
        for event in chosen:
            detail = interesting(event)
            if detail:
                lines.append(f"**{label}**\n\n```json\n{json.dumps(detail, indent=2)[:3000]}\n```\n")

    if len(lines) == 1:
        lines.append(f"Nothing matched; last 2000 characters of the execution file:\n\n"
                     f"```\n{raw[-2000:]}\n```")

    emit("\n".join(lines))


if __name__ == "__main__":
    main()
    sys.exit(0)
