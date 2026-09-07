#!/usr/bin/env bash
#
# Remote chef-solo bootstrap and converge.
#
# This script is piped to `sudo bash -s` on the target host by the configure
# stage. It expects /tmp/chef-bundle.tgz to already be uploaded (the stage scp's
# it immediately before).
#
# chef-solo is deliberate: this project configures a single instance, so a Chef
# Server would add infrastructure without adding value. `chef-client
# --local-mode` is the modern spelling of chef-solo and is what ships in
# chef-workstation / cinc-client.

set -euo pipefail

CHEF_RUN_DIR="/opt/chef-run"
BUNDLE="/tmp/chef-bundle.tgz"
CHEF_VERSION="18.5.0"

if [[ ! -f "${BUNDLE}" ]]; then
  echo "ERROR: ${BUNDLE} not found on the host." >&2
  exit 1
fi

echo "==> Ensuring the Chef client is installed"
if ! command -v chef-client >/dev/null 2>&1; then
  echo "    installing cinc-client ${CHEF_VERSION} (Chef Infra Client, Apache-2.0 build)"
  # The official omnitruck installer is the supported bootstrap path and is
  # idempotent; -v pins the version so converges are reproducible.
  curl -sSL https://omnitruck.cinc.sh/install.sh -o /tmp/install-chef.sh
  bash /tmp/install-chef.sh -v "${CHEF_VERSION}"
  # cinc-client installs as `cinc-client`; expose the conventional name.
  if ! command -v chef-client >/dev/null 2>&1 && command -v cinc-client >/dev/null 2>&1; then
    ln -sf "$(command -v cinc-client)" /usr/bin/chef-client
  fi
fi

chef-client --version

echo "==> Unpacking the cookbook bundle"
rm -rf "${CHEF_RUN_DIR}"
mkdir -p "${CHEF_RUN_DIR}" /var/chef/cache
tar xzf "${BUNDLE}" -C "${CHEF_RUN_DIR}"

if [[ ! -f "${CHEF_RUN_DIR}/nodes/app.json" ]]; then
  echo "ERROR: node attributes ${CHEF_RUN_DIR}/nodes/app.json were not uploaded." >&2
  ls -la "${CHEF_RUN_DIR}/nodes" >&2 || true
  exit 1
fi

echo "==> Converging employee_api::default"
chef-client \
  --local-mode \
  --config "${CHEF_RUN_DIR}/solo.rb" \
  --json-attributes "${CHEF_RUN_DIR}/nodes/app.json" \
  --chef-license accept-silent

echo "==> Converge complete; service status:"
systemctl is-active employee-api || true
systemctl is-active nginx || true

# Node attributes carry credentials — do not leave them on disk.
shred -u "${CHEF_RUN_DIR}/nodes/app.json" 2>/dev/null || rm -f "${CHEF_RUN_DIR}/nodes/app.json"
rm -f "${BUNDLE}"
