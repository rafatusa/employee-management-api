#!/usr/bin/env python3
"""Parse a Clair v4 vulnerability report and fail the build on HIGH/CRITICAL findings.

Clair's JSON report keys vulnerabilities by an opaque id and records severity in
two places: `normalized_severity` (Clair's own scale) and `severity` (whatever
the upstream security tracker said). We gate on the normalized value and fall
back to the raw string, because some updaters leave the normalized field
"Unknown" while the raw severity is explicit.

Exit codes:
    0 - no blocking findings
    1 - at least one HIGH or CRITICAL finding
    2 - the report could not be parsed
"""

from __future__ import annotations

import json
import sys
from collections import Counter

BLOCKING = {"high", "critical"}
SEVERITY_ORDER = ["critical", "high", "medium", "low", "negligible", "unknown"]


def load_report(path: str) -> dict:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        print(f"ERROR: Clair report not found at {path}", file=sys.stderr)
        sys.exit(2)
    except json.JSONDecodeError as exc:
        print(f"ERROR: Clair report at {path} is not valid JSON: {exc}", file=sys.stderr)
        sys.exit(2)


def severity_of(vuln: dict) -> str:
    normalized = (vuln.get("normalized_severity") or "").strip().lower()
    if normalized and normalized != "unknown":
        return normalized
    return (vuln.get("severity") or "unknown").strip().lower()


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: clair-gate.py <report.json>", file=sys.stderr)
        return 2

    report = load_report(sys.argv[1])
    vulnerabilities = report.get("vulnerabilities") or {}

    if not isinstance(vulnerabilities, dict):
        print("ERROR: unexpected report shape: 'vulnerabilities' is not an object", file=sys.stderr)
        return 2

    counts: Counter = Counter()
    blocking_findings = []

    for vuln in vulnerabilities.values():
        severity = severity_of(vuln)
        counts[severity] += 1
        if severity in BLOCKING:
            blocking_findings.append(
                {
                    "name": vuln.get("name", "<unnamed>"),
                    "severity": severity,
                    "package": (vuln.get("package") or {}).get("name", "<unknown>"),
                    "version": (vuln.get("package") or {}).get("version", "<unknown>"),
                    "fixed_in": vuln.get("fixed_in_version") or "no fix published",
                    "description": (vuln.get("description") or "").strip()[:200],
                }
            )

    total = sum(counts.values())
    print("=" * 72)
    print(f"Clair scan summary: {total} vulnerabilities found")
    for severity in SEVERITY_ORDER:
        if counts.get(severity):
            print(f"  {severity.upper():<11} {counts[severity]}")
    print("=" * 72)

    if not blocking_findings:
        print("PASS: no HIGH or CRITICAL vulnerabilities.")
        return 0

    print(f"\nFAIL: {len(blocking_findings)} blocking (HIGH/CRITICAL) vulnerabilities:\n")
    for finding in sorted(blocking_findings, key=lambda f: f["severity"]):
        print(f"  [{finding['severity'].upper()}] {finding['name']}")
        print(f"      package : {finding['package']} {finding['version']}")
        print(f"      fixed in: {finding['fixed_in']}")
        if finding["description"]:
            print(f"      detail  : {finding['description']}")
        print()

    print("Rebuild on a patched base image or upgrade the affected packages.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
