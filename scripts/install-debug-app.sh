#!/bin/bash
set -euo pipefail

if [[ "${CONFIGURATION:-}" != "Debug" ]]; then
  exit 0
fi

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${FULL_PRODUCT_NAME:-}" ]]; then
  echo "warning: Missing Xcode build environment, skipping debug app install."
  exit 0
fi

SRC_APP="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
DEST_DIR="${HOME}/Applications"
DEST_APP="${DEST_DIR}/${FULL_PRODUCT_NAME}"
LOG_FILE="${TMPDIR:-/tmp}/datagate-debug-install.log"

if [[ ! -d "${SRC_APP}" ]]; then
  echo "warning: Built app not found at ${SRC_APP}, skipping install."
  exit 0
fi

cat > "${TMPDIR:-/tmp}/datagate-install-worker.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

SRC_APP="$1"
DEST_DIR="$2"
DEST_APP="$3"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

latest_mtime() {
  /usr/bin/find "$1" -type f -exec /usr/bin/stat -f '%m' {} + 2>/dev/null | /usr/bin/sort -n | /usr/bin/tail -1
}

stable_count=0
last_mtime=""
for _ in $(seq 1 30); do
  current_mtime="$(latest_mtime "${SRC_APP}" || true)"
  if [[ -n "${current_mtime}" && "${current_mtime}" == "${last_mtime}" ]]; then
    stable_count=$((stable_count + 1))
  else
    stable_count=0
    last_mtime="${current_mtime}"
  fi
  if [[ ${stable_count} -ge 2 ]]; then
    break
  fi
  sleep 1
done

mkdir -p "${DEST_DIR}"
rm -rf "${DEST_APP}"
/usr/bin/ditto "${SRC_APP}" "${DEST_APP}"
if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -f -R -trusted "${DEST_APP}"
fi
echo "Installed debug app to ${DEST_APP}"
EOF

/bin/chmod +x "${TMPDIR:-/tmp}/datagate-install-worker.sh"
/usr/bin/nohup "${TMPDIR:-/tmp}/datagate-install-worker.sh" "${SRC_APP}" "${DEST_DIR}" "${DEST_APP}" > "${LOG_FILE}" 2>&1 </dev/null &

echo "Scheduled debug app install to ${DEST_APP}"
echo "Install log: ${LOG_FILE}"
