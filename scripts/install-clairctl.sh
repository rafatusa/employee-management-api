#!/usr/bin/env bash
#
# Install clairctl, the CLI that drives a Clair server.
#
# WHY THIS IS NOT A ONE-LINE curl:
# A pinned release-asset URL is a single point of failure — if the asset name or
# version tag is wrong, `curl -f` exits 22, `set -e` kills the step, and the log
# says only "exit 22" with no indication that the URL was the problem. That
# failure mode has burned real deployments.
#
# So: try the pinned asset first, fall back to querying the GitHub API for the
# actual asset name in that release, and finally fail with a message that says
# exactly what was attempted.

set -euo pipefail

CLAIRCTL_VERSION="${CLAIRCTL_VERSION:-4.7.4}"
DEST="${DEST:-/usr/local/bin/clairctl}"
TMP="/tmp/clairctl"
REPO="quay/clair"

log() { echo "[install-clairctl] $*"; }

try_download() {
  local url="$1"
  log "trying ${url}"
  # -f so a 404 is a failure, -L to follow redirects, -s to stay quiet.
  if curl -fsSL "${url}" -o "${TMP}" && [[ -s "${TMP}" ]]; then
    # A GitHub 404 page can still be written to disk; reject anything that is
    # not an executable binary.
    if file "${TMP}" 2>/dev/null | grep -qi 'executable'; then
      return 0
    fi
    log "downloaded file is not an executable (likely an error page); discarding"
    rm -f "${TMP}"
  fi
  return 1
}

# --- 1. the conventional asset name -----------------------------------------
if try_download "https://github.com/${REPO}/releases/download/v${CLAIRCTL_VERSION}/clairctl-linux-amd64"; then
  log "installed from the pinned asset name"
else
  # --- 2. ask the API what the release actually contains ---------------------
  log "pinned asset not found; querying the GitHub release for its real asset name"
  ASSET_URL="$(
    curl -fsSL "https://api.github.com/repos/${REPO}/releases/tags/v${CLAIRCTL_VERSION}" \
      | grep -o '"browser_download_url": *"[^"]*clairctl[^"]*linux[^"]*amd64[^"]*"' \
      | head -n 1 \
      | sed 's/.*": *"//; s/"$//'
  )" || ASSET_URL=""

  if [[ -n "${ASSET_URL}" ]] && try_download "${ASSET_URL}"; then
    log "installed from the release's actual asset: ${ASSET_URL}"
  else
    echo "ERROR: could not obtain clairctl ${CLAIRCTL_VERSION}." >&2
    echo "  Tried: https://github.com/${REPO}/releases/download/v${CLAIRCTL_VERSION}/clairctl-linux-amd64" >&2
    echo "  Tried: the linux/amd64 asset advertised by the GitHub API for tag v${CLAIRCTL_VERSION}" >&2
    echo "  Check that the release exists and publishes a linux amd64 clairctl binary:" >&2
    echo "    https://github.com/${REPO}/releases/tag/v${CLAIRCTL_VERSION}" >&2
    exit 1
  fi
fi

sudo install -m 0755 "${TMP}" "${DEST}"
rm -f "${TMP}"

"${DEST}" --version
log "clairctl ready at ${DEST}"
