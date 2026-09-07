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
CLAIR_HEALTH_URL="http://localhost:6060/healthz"
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
# "permission denied" before it can start. The file must therefore be
# world-readable (0644).
#
# That is acceptable here and nowhere else: this is a throwaway config on an
# ephemeral single-tenant runner, holding a credential for a database container
# that is destroyed at the end of this job. Nothing else runs on this machine
# and neither value outlives it.
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
  max_conn_pool: 100
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

# Readable by the container's UID — see the note above.
chmod 644 "${CLAIR_CONFIG_DIR}/config.yaml"
chmod 755 "${CLAIR_CONFIG_DIR}"

# ---------------------------------------------------------------------------
# 3. Clair itself
#
# :ro,Z — read-only, and Z relabels for SELinux hosts. The container cannot
# modify the config it is given.
# ---------------------------------------------------------------------------
echo "Starting Clair ${CLAIR_VERSION} in combo mode..."
podman run -d --name clair --network host \
  -v "${CLAIR_CONFIG_DIR}/config.yaml:/etc/clair/config.yaml:ro,Z" \
  -e CLAIR_MODE=combo \
  -e CLAIR_CONF=/etc/clair/config.yaml \
  "quay.io/projectquay/clair:${CLAIR_VERSION}"

# Clair loads its vulnerability database on first start. That is the slow part
# of this stage; allow up to ~10 minutes before declaring failure.
echo "Waiting for Clair to become healthy (includes the initial CVE database load)..."
for i in $(seq 1 120); do
  if curl -sf "${CLAIR_HEALTH_URL}" >/dev/null 2>&1; then
    echo "Clair is healthy after $((i * 5))s"
    exit 0
  fi
  if ! podman inspect -f '{{.State.Running}}' clair 2>/dev/null | grep -q true; then
    echo "ERROR: the Clair container exited before becoming healthy." >&2
    echo "----- podman logs clair -----" >&2
    podman logs clair >&2 2>&1 || true
    exit 1
  fi
  echo "  waiting for Clair (${i}/120)"
  sleep 5
done

echo "ERROR: Clair did not become healthy within 600s." >&2
echo "----- podman logs clair -----" >&2
podman logs clair >&2 2>&1 || true
exit 1
