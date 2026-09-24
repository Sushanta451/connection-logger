#!/usr/bin/env python3
"""Turn Claude's review verdict into the pass/fail status of the merge gate.

Reads the structured output of anthropics/claude-code-action from $REVIEW and
exits non-zero unless the verdict is an explicit "approve". The gate fails
closed: a missing, malformed, or absent verdict blocks the merge rather than
waving it through, because "the reviewer never answered" is not an approval.

Writes a readable summary to the GitHub Actions job summary either way.
"""

import json
import os
import sys

SUMMARY_PATH = os.environ.get("GITHUB_STEP_SUMMARY")


def emit(markdown: str) -> None:
    print(markdown)
    if SUMMARY_PATH:
        with open(SUMMARY_PATH, "a", encoding="utf-8") as handle:
            handle.write(markdown + "\n")


def fail(reason: str, detail: str = "") -> None:
    body = f"## ❌ Merge blocked\n\n{reason}\n"
    if detail:
        body += f"\n```\n{detail}\n```\n"
    emit(body)
    sys.exit(1)


def main() -> None:
    conclusion = os.environ.get("CONCLUSION", "").strip()
    raw = os.environ.get("REVIEW", "").strip()

    if conclusion and conclusion != "success":
        fail(
            "The review step did not finish, so no verdict was produced. "
            "Check the step log above, then re-run this job.",
            f"conclusion={conclusion}",
        )

    if not raw:
        fail(
            "Claude produced no verdict. This usually means the review step failed "
            "or the ANTHROPIC_API_KEY secret is missing. Re-run the job once the "
            "cause is fixed."
        )

    try:
        review = json.loads(raw)
    except json.JSONDecodeError as exc:
        fail(f"Could not parse Claude's verdict ({exc}).", raw[:2000])

    verdict = str(review.get("verdict", "")).strip().lower()
    summary = str(review.get("summary", "")).strip()
    blocking = review.get("blocking_issues") or []
    notes = review.get("non_blocking_notes") or []

    headers = {
        "approve": "## ✅ Claude approved this pull request\n",
        "request_changes": "## ❌ Claude requested changes\n",
    }
    lines = [headers.get(verdict, "## ⚠️ Claude returned an unrecognized verdict\n")]
    if summary:
        lines.append(summary + "\n")

    if blocking:
        lines.append("### Blocking\n")
        for item in blocking:
            where = f"`{item.get('file', '?')}:{item.get('line', '?')}`"
            lines.append(f"- {where} — {item.get('issue', '')}")
            impact = str(item.get("impact", "")).strip()
            if impact:
                lines.append(f"  - Impact: {impact}")
        lines.append("")

    if notes:
        lines.append("### Non-blocking notes\n")
        lines.extend(f"- {note}" for note in notes)
        lines.append("")

    emit("\n".join(lines))

    if verdict == "approve":
        if blocking:
            # An approval that still lists blocking issues is self-contradictory;
            # treat the issues as authoritative.
            fail(
                f"Verdict was 'approve' but {len(blocking)} blocking issue(s) were "
                "reported. Resolve them, or re-run the review."
            )
        return

    if verdict != "request_changes":
        fail(f"Unrecognized verdict {verdict!r}; expected 'approve' or 'request_changes'.")

    count = len(blocking)
    emit(
        f"\n**Merge is blocked until {'this issue is' if count == 1 else 'these issues are'} "
        "addressed.** Push a fix and the review runs again automatically."
    )
    sys.exit(1)


if __name__ == "__main__":
    main()
