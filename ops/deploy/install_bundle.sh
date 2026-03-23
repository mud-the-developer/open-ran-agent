#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage: install_bundle.sh <bundle-tarball> [install-root]

Environment:
  RAN_INSTALL_ROOT        Install root. Default: /opt/open-ran-agent
  RAN_ETC_ROOT            Operator config root. Default: /etc/open-ran-agent
  RAN_SYSTEMD_STAGING_DIR Systemd staging dir. Default: <install-root>/systemd
EOF
}

copy_if_absent() {
  local source="$1"
  local target="$2"

  if [[ -f "${source}" && ! -e "${target}" ]]; then
    mkdir -p "$(dirname "${target}")"
    cp "${source}" "${target}"
  fi
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 64
fi

TARBALL="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
INSTALL_ROOT="${2:-${RAN_INSTALL_ROOT:-/opt/open-ran-agent}}"
ETC_ROOT="${RAN_ETC_ROOT:-/etc/open-ran-agent}"
SYSTEMD_STAGING_DIR="${RAN_SYSTEMD_STAGING_DIR:-${INSTALL_ROOT}/systemd}"

if [[ ! -f "${TARBALL}" ]]; then
  echo "bundle tarball not found: ${TARBALL}" >&2
  exit 66
fi

BUNDLE_NAME="$(basename "${TARBALL}")"
BUNDLE_ID="${BUNDLE_NAME#open_ran_agent-}"
BUNDLE_ID="${BUNDLE_ID%.tar.gz}"

RELEASE_DIR="${INSTALL_ROOT}/releases/${BUNDLE_ID}"
CURRENT_DIR="${INSTALL_ROOT}/current"

mkdir -p "${INSTALL_ROOT}/releases" "${ETC_ROOT}/requests" "${ETC_ROOT}/oai" "${SYSTEMD_STAGING_DIR}"
rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

tar -xzf "${TARBALL}" -C "${RELEASE_DIR}"
ln -sfn "${RELEASE_DIR}" "${CURRENT_DIR}"

chmod +x \
  "${CURRENT_DIR}/bin/ran-debug-latest" \
  "${CURRENT_DIR}/bin/ran-install" \
  "${CURRENT_DIR}/bin/ranctl" \
  "${CURRENT_DIR}/bin/ran-dashboard" \
  "${CURRENT_DIR}/bin/ran-deploy-wizard" \
  "${CURRENT_DIR}/bin/ran-fetch-remote-artifacts" \
  "${CURRENT_DIR}/bin/ran-host-preflight" \
  "${CURRENT_DIR}/bin/ran-remote-ranctl" \
  "${CURRENT_DIR}/bin/ran-ship-bundle" \
  "${CURRENT_DIR}/ops/deploy/easy_install.sh" \
  "${CURRENT_DIR}/ops/deploy/debug_latest.sh" \
  "${CURRENT_DIR}/ops/deploy/fetch_remote_artifacts.sh" \
  "${CURRENT_DIR}/ops/deploy/preflight.sh" \
  "${CURRENT_DIR}/ops/deploy/run_remote_ranctl.sh" \
  "${CURRENT_DIR}/ops/deploy/ship_bundle.sh" || true

copy_if_absent \
  "${CURRENT_DIR}/ops/deploy/systemd/ran-dashboard.env.example" \
  "${ETC_ROOT}/ran-dashboard.env"

copy_if_absent \
  "${CURRENT_DIR}/ops/deploy/systemd/ran-host-preflight.env.example" \
  "${ETC_ROOT}/ran-host-preflight.env"

copy_if_absent \
  "${CURRENT_DIR}/config/prod/topology.single_du.target_host.rfsim.json.example" \
  "${ETC_ROOT}/topology.single_du.target_host.rfsim.json"

copy_if_absent \
  "${CURRENT_DIR}/examples/ranctl/precheck-target-host.json.example" \
  "${ETC_ROOT}/requests/precheck-target-host.json"

for unit in "${CURRENT_DIR}"/ops/deploy/systemd/*.service; do
  [[ -f "${unit}" ]] || continue
  cp "${unit}" "${SYSTEMD_STAGING_DIR}/"
done

cat <<EOF
Installed bundle ${BUNDLE_ID}
  install root: ${INSTALL_ROOT}
  current link : ${CURRENT_DIR}
  config root  : ${ETC_ROOT}
  systemd stage: ${SYSTEMD_STAGING_DIR}

Next:
  1. Run  ${CURRENT_DIR}/bin/ran-install
  2. Or run ${CURRENT_DIR}/bin/ran-deploy-wizard --skip-install
  3. Or edit ${ETC_ROOT}/topology.single_du.target_host.rfsim.json
  4. And edit ${ETC_ROOT}/requests/precheck-target-host.json
  5. Run  ${CURRENT_DIR}/bin/ran-host-preflight
  6. Use  ${CURRENT_DIR}/bin/ran-debug-latest --failures-only to inspect the latest failed run
  7. Start ${CURRENT_DIR}/bin/ran-dashboard or install systemd units from ${SYSTEMD_STAGING_DIR}
EOF
