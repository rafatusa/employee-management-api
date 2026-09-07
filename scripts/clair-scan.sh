#!/usr/bin/env bash
#
# Run a Clair vulnerability report against an image reference and gate on it.
#
# Usage: clair-scan.sh <image-reference>
#
# The image must already be pushed to the local registry — Clair's indexer
# fetches layers by reference over the registry API and cannot read Podman's
# local image store.
#
# Teardown of clair / clair-db / scan-registry happens on BOTH the success and
# failure paths via trap EXIT, because the pipeline spec forbids `if: always()`
# steps.

set -euo pipefail

IMAGE_REF="${1:-}"
CLAIR_HOST="${CLAIR_HOST:-http://localhost:6060}"
REPORT_DIR="${REPORT_DIR:-reports/clair}"
REPORT_FILE="${REPORT_DIR}/report.json"

if [[ -z "${IMAGE_REF}" ]]; then
  echo "ERROR: usage: $0 <image-reference>" >&2
  exit 2
fi

cleanup() {
  local exit_code=$?
  if [[ ${exit_code} -ne 0 ]]; then
    echo "----- Clair scan failed (exit ${exit_code}); dumping container logs -----" >&2
    podman logs clair >&2 2>&1 || true
  fi
  echo "Cleaning up scan containers..."
  podman rm -f clair clair-db scan-registry >/dev/null 2>&1 || true
  exit "${exit_code}"
}
trap cleanup EXIT

mkdir -p "${REPORT_DIR}"

# clairctl needs a config pointing at the running Clair and the same PSK.
export CLAIR_CONF="${CLAIR_CONF:-/tmp/clair/config.yaml}"

echo "Requesting Clair vulnerability report for ${IMAGE_REF}..."
clairctl report \
  --host "${CLAIR_HOST}" \
  --out json \
  "${IMAGE_REF}" > "${REPORT_FILE}"

echo "Report written to ${REPORT_FILE} ($(wc -c < "${REPORT_FILE}") bytes)"

python3 scripts/clair-gate.py "${REPORT_FILE}"
