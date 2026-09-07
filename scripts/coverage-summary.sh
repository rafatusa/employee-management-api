#!/usr/bin/env bash
#
# Print the achieved JaCoCo line coverage to the build log.
#
# The coverage gate itself lives in build.gradle
# (jacocoTestCoverageVerification, 90% LINE) and runs BEFORE this script. When
# it fails, Gradle reports the bundle ratio but the detailed report is an XML
# file CI discards. This prints a per-class breakdown so a shortfall names the
# classes that need tests, rather than costing another run to find out.
#
# REPORTING ONLY: this never changes the pass/fail outcome — the gate has
# already decided by the time this runs.

set -euo pipefail

REPORT="build/reports/jacoco/test/jacocoTestReport.xml"

if [[ ! -f "${REPORT}" ]]; then
  echo "No JaCoCo XML report at ${REPORT} — skipping coverage summary."
  exit 0
fi

python3 - "${REPORT}" <<'PY'
import sys
import xml.etree.ElementTree as ET

path = sys.argv[1]
try:
    root = ET.parse(path).getroot()
except ET.ParseError as exc:
    print("Could not parse the JaCoCo report: %s" % exc)
    sys.exit(0)


def line_counts(node):
    """Return (covered, missed) for the LINE counter of a JaCoCo node."""
    for counter in node.findall("counter"):
        if counter.get("type") == "LINE":
            return int(counter.get("covered", 0)), int(counter.get("missed", 0))
    return 0, 0


covered, missed = line_counts(root)
total = covered + missed
overall = (covered / total * 100) if total else 100.0

print("=" * 68)
print("JaCoCo line coverage: %.2f%%  (%d/%d lines)  minimum 90.00%%"
      % (overall, covered, total))
print("=" * 68)

rows = []
for package in root.findall("package"):
    pkg = package.get("name", "").replace("/", ".")
    for cls in package.findall("class"):
        name = cls.get("name", "").split("/")[-1]
        c, m = line_counts(cls)
        t = c + m
        if t == 0:
            continue
        rows.append((c / t * 100, "%s.%s" % (pkg, name), c, t))

rows.sort()
print("%9s  %9s  class" % ("coverage", "lines"))
for pct, name, c, t in rows:
    flag = "  <-- below 90%" if pct < 90 else ""
    print("%8.2f%%  %4d/%-4d  %s%s" % (pct, c, t, name, flag))
print("=" * 68)
PY
