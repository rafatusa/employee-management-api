#!/usr/bin/env bash
#
# Consolidate the validation workflow's outputs into a single HTML index that
# links the Newman report, the k6 summary and the REST Assured results.

set -euo pipefail

REPORT_DIR="${REPORT_DIR:-reports}"
OUT="${REPORT_DIR}/index.html"
GENERATED_AT="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

mkdir -p "${REPORT_DIR}"

# k6 --summary-export writes aggregate metrics; surface the two numbers the
# requirements actually gate on.
K6_P95="n/a"
K6_ERROR_RATE="n/a"
if [[ -f "${REPORT_DIR}/k6/summary.json" ]]; then
  K6_P95="$(python3 -c "
import json,sys
try:
    d=json.load(open('${REPORT_DIR}/k6/summary.json'))
    v=d.get('metrics',{}).get('http_req_duration',{})
    print(round(v.get('p(95)', v.get('values',{}).get('p(95)', 0)), 2))
except Exception:
    print('n/a')
" 2>/dev/null || echo 'n/a')"
  K6_ERROR_RATE="$(python3 -c "
import json,sys
try:
    d=json.load(open('${REPORT_DIR}/k6/summary.json'))
    v=d.get('metrics',{}).get('http_req_failed',{})
    rate=v.get('rate', v.get('values',{}).get('rate', 0))
    print(str(round(rate*100, 3)) + '%')
except Exception:
    print('n/a')
" 2>/dev/null || echo 'n/a')"
fi

link_if_exists() {
  local path="$1" label="$2"
  if [[ -e "${REPORT_DIR}/${path}" ]]; then
    echo "      <li><a href=\"${path}\">${label}</a></li>"
  else
    echo "      <li>${label} <em>(not produced in this run)</em></li>"
  fi
}

{
  cat <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Employee Management API — Validation Report</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
           margin: 2rem auto; max-width: 52rem; color: #1c1e21; line-height: 1.6; }
    h1 { border-bottom: 2px solid #e3e5e8; padding-bottom: .5rem; }
    .metrics { display: flex; gap: 1rem; flex-wrap: wrap; margin: 1.5rem 0; }
    .card { border: 1px solid #e3e5e8; border-radius: 8px; padding: 1rem 1.25rem; flex: 1 1 12rem; }
    .card .value { font-size: 1.6rem; font-weight: 600; }
    .card .label { color: #606770; font-size: .85rem; text-transform: uppercase; letter-spacing: .04em; }
    ul { padding-left: 1.2rem; }
    footer { margin-top: 2.5rem; color: #606770; font-size: .85rem; }
  </style>
</head>
<body>
  <h1>Employee Management API — Validation Report</h1>
  <p>Post-deployment validation of the live environment.</p>

  <div class="metrics">
    <div class="card"><div class="label">p95 response time</div><div class="value">${K6_P95} ms</div><div class="label">budget &lt; 500 ms</div></div>
    <div class="card"><div class="label">Error rate</div><div class="value">${K6_ERROR_RATE}</div><div class="label">budget &lt; 1%</div></div>
  </div>

  <h2>Reports</h2>
  <ul>
HTML

  link_if_exists "newman/report.html" "Postman / Newman functional tests"
  link_if_exists "k6/summary.json" "k6 load test summary (JSON)"
  link_if_exists "integrationTest/index.html" "REST Assured integration tests"

  cat <<HTML
  </ul>

  <h2>Coverage of the validation requirements</h2>
  <ul>
    <li>Application health — smoke test + Newman health check</li>
    <li>Authentication — anonymous request must return 401</li>
    <li>Employee CRUD — REST Assured and Newman create/read/update/delete flows</li>
    <li>Database connectivity — records read back after write; actuator DB health indicator</li>
    <li>Nginx reverse proxy — Server header asserted on proxied responses</li>
    <li>p95 &lt; 500 ms and error rate &lt; 1% — enforced as k6 thresholds</li>
  </ul>

  <footer>Generated ${GENERATED_AT}</footer>
</body>
</html>
HTML
} > "${OUT}"

echo "Consolidated report written to ${OUT}"
