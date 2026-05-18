#!/bin/bash
set -euo pipefail

# BOOT-RADICAL/scripts/qemu-boot-smoke.sh
# QEMU boot smoke harness for RADICAL environment.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BR_DIR="${ROOT_DIR}/BOOT-RADICAL"

# Defaults
IMAGE_PATH="${BOOT_RADICAL_QEMU_IMAGE:-${BR_DIR}/out/radical-boot.qcow2}"
TIMEOUT_SECONDS="${BOOT_RADICAL_QEMU_TIMEOUT_SECONDS:-30}"
ALLOW_KVM="${BOOT_RADICAL_QEMU_ALLOW_KVM:-1}"
ALLOW_MISSING_IMAGE="${BOOT_RADICAL_QEMU_ALLOW_MISSING_IMAGE:-0}"
QEMU_NET="${BOOT_RADICAL_QEMU_NET:-none}"
QEMU_MEMORY="${BOOT_RADICAL_QEMU_MEMORY:-2048M}"
SUCCESS_REGEX="${BOOT_RADICAL_QEMU_SUCCESS_REGEX:-}"
LOG_FILE="${BOOT_RADICAL_QEMU_LOG:-${BR_DIR}/out/qemu-boot-smoke.log}"
REPORT_FILE="${BOOT_RADICAL_QEMU_REPORT:-${BR_DIR}/out/qemu-boot-smoke.json}"

mkdir -p "$(dirname "${LOG_FILE}")"
mkdir -p "$(dirname "${REPORT_FILE}")"

echo "Starting BOOT-RADICAL QEMU Boot Smoke Harness..."
echo "Image: ${IMAGE_PATH}"
echo "Timeout: ${TIMEOUT_SECONDS}s"

function emit_report() {
    local status="$1"
    local reason="$2"
    local kvm_used="$3"
    
    cat <<EOF > "${REPORT_FILE}"
{
  "result": "${status}",
  "reason": "${reason}",
  "image": "${IMAGE_PATH}",
  "timeout": ${TIMEOUT_SECONDS},
  "kvm": ${kvm_used},
  "log": "${LOG_FILE}"
}
EOF
    echo "Report emitted to ${REPORT_FILE}"
}

# Check for QEMU
if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "[ERROR] qemu-system-x86_64 not found."
    emit_report "failed" "qemu_not_found" 0
    exit 1
fi

# Check for image
if [ ! -f "${IMAGE_PATH}" ]; then
    if [ "${ALLOW_MISSING_IMAGE}" = "1" ]; then
        echo "[INFO] Image not found, but ALLOW_MISSING_IMAGE=1. Skipping boot smoke."
        emit_report "skipped" "missing_artifact" 0
        exit 0
    else
        echo "[ERROR] Boot image not found: ${IMAGE_PATH}"
        emit_report "failed" "missing_artifact" 0
        exit 1
    fi
fi

# Prepare QEMU command
QEMU_OPTS=(
    "-machine" "q35"
    "-m" "${QEMU_MEMORY}"
    "-drive" "file=${IMAGE_PATH},format=qcow2,if=virtio"
    "-serial" "file:${LOG_FILE}"
    "-display" "none"
    "-nographic"
    "-net" "${QEMU_NET}"
    "-boot" "c"
)

KVM_USED=0
if [ "${ALLOW_KVM}" = "1" ] && [ -w /dev/kvm ]; then
    QEMU_OPTS+=("-enable-kvm")
    KVM_USED=1
    echo "KVM enabled."
fi

# Run QEMU with timeout
echo "Launching QEMU..."
set +e
timeout "${TIMEOUT_SECONDS}" qemu-system-x86_64 "${QEMU_OPTS[@]}" > /dev/null 2>&1
QEMU_EXIT=$?
set -e

# Analyze log for failure markers
echo "Analyzing logs..."
FAILURE_REASON=""

if grep -qiE "Kernel panic|kernel panic|panic:|No bootable device|not a bootable disk|failed to mount|Entering emergency mode|dracut emergency shell" "${LOG_FILE}"; then
    FAILURE_REASON=$(grep -iE "Kernel panic|kernel panic|panic:|No bootable device|not a bootable disk|failed to mount|Entering emergency mode|dracut emergency shell" "${LOG_FILE}" | head -n 1 | xargs)
    echo "[FAIL] Fatal marker detected: ${FAILURE_REASON}"
    emit_report "failed" "fatal_marker_detected: ${FAILURE_REASON}" "${KVM_USED}"
    exit 1
fi

# Check for success
if [ -n "${SUCCESS_REGEX}" ]; then
    if grep -qE "${SUCCESS_REGEX}" "${LOG_FILE}"; then
        echo "[PASS] Success regex found."
        emit_report "pass" "success_regex_matched" "${KVM_USED}"
        exit 0
    else
        echo "[FAIL] Success regex not found."
        emit_report "failed" "success_regex_not_found" "${KVM_USED}"
        exit 1
    fi
fi

# If no success regex, pass if no failure markers and timed out (presumed booting)
if [ "${QEMU_EXIT}" = "124" ]; then
    echo "[PASS] QEMU timed out without fatal errors (presumed successful boot)."
    emit_report "pass" "timeout_no_failure" "${KVM_USED}"
    exit 0
else
    echo "[FAIL] QEMU exited unexpectedly with code ${QEMU_EXIT}"
    emit_report "failed" "unexpected_exit_code_${QEMU_EXIT}" "${KVM_USED}"
    exit 1
fi
