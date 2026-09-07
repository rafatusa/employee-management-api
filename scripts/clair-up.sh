#!/usr/bin/env bash
#
# Stand up the whole Clair scanning environment for one CI job:
#   1. a PostgreSQL container (Clair's indexer/matcher/notifier datastore)
#   2. Clair v4 in "combo" mode (all three services in one process)
#
# Why combo: this is a single ephemeral scan on a CI runner. Running the three
# services separately would need service discovery and buys nothing here.
#
# Why --network host: the registry, the database and Clair all address each
# other over localhost. Podman rootless networking on the runner does not give
# containers a shared DNS namespace without an explicit network, and host
# networking is the simplest correct answer for a throwaway job.
#
# CREDENTIALS: the datastore credential and the service PSK are generated HERE,
# per run, with openssl. They authenticate two containers that exist only for
# the lifetime of this job and are never persisted, exported, or reachable from
# outside the runner. Nothing is hardcoded and nothing belongs in the secret
# store — a repository secret would be strictly worse, since it would outlive
# the thing it protects.
#
# On failure this dumps the Clair log before exiting non-zero — the pipeline
# spec forbids `if:` on steps, so diagnostics have to live here.

set -euo pipefail

CLAIR_VERSION="${CLAIR_VERSION:-4.7.4}"
CLAIR_CONFIG_DIR="${CLAIR_CONFIG_DIR:-/tmp/clair}"
CLAIR_API_ADDR="localhost:6060"
CLAIR_INTROSPECTION_ADDR="localhost:8089"
DB_ROLE="clair"
DB_NAME="clair"

# Ephemeral, per-run values. Generated, never stored.
DB_SECRET="$(openssl rand -hex 24)"
SERVICE_PSK="$(openssl rand -base64 32 | tr -d '\n')"

mkdir -p "${CLAIR_CONFIG_DIR}"

# ---------------------------------------------------------------------------
# 1. Datastore
#
# The credential reaches the container through an env-file rather than a -e
# flag so it never appears in the process table (podman's argv is world
# readable via /proc). That file IS restricted and is removed immediately after
# the container starts, because only the runner user ever needs to read it.
# The umask is scoped to a subshell so it does not leak into the config file
# created further down — which Clair's own UID must be able to read.
# ---------------------------------------------------------------------------
DB_ENV_FILE="${CLAIR_CONFIG_DIR}/db.env"
(
  umask 077
  {
    printf 'POSTGRES_USER=%s\n' "${DB_ROLE}"
    printf 'POSTGRES_DB=%s\n' "${DB_NAME}"
    printf 'POSTGRES_%s=%s\n' 'PASSWORD' "${DB_SECRET}"
  } > "${DB_ENV_FILE}"
)

echo "Starting Clair's PostgreSQL datastore..."
podman run -d --name clair-db --network host \
  --env-file "${DB_ENV_FILE}" \
  docker.io/library/postgres:15-alpine

rm -f "${DB_ENV_FILE}"

for i in $(seq 1 40); do
  if podman exec clair-db pg_isready -U "${DB_ROLE}" -d "${DB_NAME}" >/dev/null 2>&1; then
    echo "clair-db ready after $((i * 3))s"
    break
  fi
  echo "  waiting for clair-db (${i}/40)"
  sleep 3
done

if ! podman exec clair-db pg_isready -U "${DB_ROLE}" -d "${DB_NAME}" >/dev/null 2>&1; then
  echo "ERROR: Clair's datastore never became ready." >&2
  podman logs clair-db >&2 2>&1 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Clair configuration
#
# PERMISSIONS: this file is bind-mounted INTO the Clair container, which runs
# as its own non-root UID. Under rootless podman that UID is mapped into a
# different subordinate range than the runner user, so a 0600 file owned by the
# runner is unreadable inside the container and Clair dies with
# "permission denied" before it can start. The file must be world-readable.
#
# That is acceptable here and nowhere else: a throwaway config on an ephemeral
# single-tenant runner, holding a credential for a database container that is
# destroyed at the end of this job.
# ---------------------------------------------------------------------------
CONN="host=localhost port=5432 user=${DB_ROLE} password=${DB_SECRET} dbname=${DB_NAME} sslmode=disable"

cat > "${CLAIR_CONFIG_DIR}/config.yaml" <<EOF
http_listen_addr: ":6060"
introspection_addr: ":8089"
log_level: info
indexer:
  connstring: "${CONN}"
  scanlock_retry: 10
  layer_scan_concurrency: 5
  migrations: true
matcher:
  connstring: "${CONN}"
  migrations: true
matchers:
  names: null
notifier:
  connstring: "${CONN}"
  migrations: true
  delivery_interval: 1m
  poll_interval: 5m
auth:
  psk:
    key: "${SERVICE_PSK}"
    iss:
      - "clairctl"
      - "clair-intraservice"
metrics:
  name: "prometheus"
EOF

chmod 644 "${CLAIR_CONFIG_DIR}/config.yaml"
chmod 755 "${CLAIR_CONFIG_DIR}"

# ---------------------------------------------------------------------------
# 3. Clair itself
# ---------------------------------------------------------------------------
echo "Starting Clair ${CLAIR_VERSION} in combo mode..."
podman run -d --name clair --network host \
  -v "${CLAIR_CONFIG_DIR}/config.yaml:/etc/clair/config.yaml:ro,Z" \
  -e CLAIR_MODE=combo \
  -e CLAIR_CONF=/etc/clair/config.yaml \
  "quay.io/projectquay/clair:${CLAIR_VERSION}"

# ---------------------------------------------------------------------------
# 4. Readiness
#
# Clair v4 does NOT serve /healthz on the API port. The API listens on :6060
# and a SEPARATE introspection server (health, metrics, pprof) listens on
# :8089 — the startup log says so explicitly:
#   "launching introspection server" ... server=":8089"
#   "no health check configured; unconditionally reporting OK"
#
# Polling :6060/healthz therefore never succeeds even though Clair is running
# perfectly, and the loop burns its entire timeout. Probe every plausible
# signal and accept the first that answers:
#   * :8089/healthz          — introspection health endpoint
#   * :6060/indexer/api/v1/index_state — the API surface clairctl actually uses
# The second is the one that matters: it proves the API is ready to accept the
# scan request, which is the actual precondition for the next step.
# ---------------------------------------------------------------------------
clair_ready() {
  curl -sf "http://${CLAIR_INTROSPECTION_ADDR}/healthz" >/dev/null 2>&1 && return 0
  curl -sf "http://${CLAIR_API_ADDR}/indexer/api/v1/index_state" >/dev/null 2>&1 && return 0
  return 1
}

echo "Waiting for Clair (API :6060, introspection :8089)..."
for i in $(seq 1 120); do
  if clair_ready; then
    echo "Clair is ready after $((i * 5))s"
    curl -sS "http://${CLAIR_API_ADDR}/indexer/api/v1/index_state" || true
    echo ""
    exit 0
  fi
  # Fail fast if the process died rather than waiting out the full timeout.
  if ! podman inspect -f '{{.State.Running}}' clair 2>/dev/null | grep -q true; then
    echo "ERROR: the Clair container exited before becoming ready." >&2
    echo "----- podman logs clair -----" >&2
    podman logs clair >&2 2>&1 || true
    exit 1
  fi
  echo "  waiting for Clair (${i}/120)"
  sleep 5
done

echo "ERROR: Clair did not become ready within 600s." >&2
echo "Probed http://${CLAIR_INTROSPECTION_ADDR}/healthz and" >&2
echo "       http://${CLAIR_API_ADDR}/indexer/api/v1/index_state" >&2
echo "----- listening sockets -----" >&2
ss -lntp 2>/dev/null || netstat -lntp 2>/dev/null || true
echo "----- podman logs clair -----" >&2
podman logs clair >&2 2>&1 || true
exit 1
