#!/bin/bash
set -euo pipefail

# BOOT-RADICAL/scripts/check-vulkan-readiness.sh
# QEMU/headless-safe Vulkan readiness gate for RADICAL/Xwin boot validation.
#
# Policy:
#   - Non-strict mode reports readiness and exits 0 even when Vulkan is unavailable.
#   - Strict mode exits 1 unless the readiness class is hardware or software.
#   - GPU/Vulkan readiness is an acceleration/preflight signal, not an auth/session/watchdog authority.

STRICT="${RADICAL_VULKAN_STRICT:-0}"
ALLOW_SOFTWARE="${RADICAL_VULKAN_ALLOW_SOFTWARE:-1}"
TIMEOUT_SECONDS="${RADICAL_VULKANINFO_TIMEOUT_SECONDS:-8}"
REPORT_DIR="${RADICAL_VULKAN_REPORT_DIR:-BOOT-RADICAL/out}"
REPORT_FILE="${RADICAL_VULKAN_REPORT:-${REPORT_DIR}/vulkan-readiness.json}"
PROFILE="${RADICAL_BOOT_PROFILE:-default}"

mkdir -p "$(dirname "${REPORT_FILE}")"

status="not_ready"
readiness_class="missing"
reason="not_evaluated"
loader="missing"
icd="missing"
dri="missing"
vulkaninfo_status="not_run"
software_renderer="unknown"
summary_file=""

if command -v vulkaninfo >/dev/null 2>&1; then
    loader="present"
else
    reason="vulkaninfo_not_found"
fi

if find /usr/share/vulkan/icd.d /etc/vulkan/icd.d -maxdepth 1 -type f -name '*.json' 2>/dev/null | grep -q .; then
    icd="present"
else
    if [ "${reason}" = "not_evaluated" ]; then
        reason="vulkan_icd_not_found"
    fi
fi

if [ -d /dev/dri ]; then
    dri="present"
else
    if [ "${reason}" = "not_evaluated" ]; then
        reason="dev_dri_not_found"
    fi
fi

if [ "${loader}" = "present" ]; then
    summary_file="$(mktemp)"
    if timeout "${TIMEOUT_SECONDS}" vulkaninfo --summary >"${summary_file}" 2>&1; then
        vulkaninfo_status="pass"
        if grep -Eiq 'llvmpipe|lavapipe|software|SwiftShader' "${summary_file}"; then
            software_renderer="yes"
            readiness_class="software"
            if [ "${ALLOW_SOFTWARE}" = "1" ]; then
                status="ready"
                reason="software_vulkan_available"
            else
                status="not_ready"
                reason="software_vulkan_disallowed"
            fi
        else
            software_renderer="no"
            readiness_class="hardware"
            status="ready"
            reason="hardware_vulkan_available"
        fi
    else
        vulkaninfo_status="fail"
        if [ "${reason}" = "not_evaluated" ]; then
            reason="vulkaninfo_failed"
        fi
    fi
    rm -f "${summary_file}"
fi

cat >"${REPORT_FILE}" <<EOF
{
  "profile": "${PROFILE}",
  "status": "${status}",
  "readiness_class": "${readiness_class}",
  "reason": "${reason}",
  "strict": "${STRICT}",
  "allow_software": "${ALLOW_SOFTWARE}",
  "loader": "${loader}",
  "icd": "${icd}",
  "dri": "${dri}",
  "vulkaninfo_status": "${vulkaninfo_status}",
  "software_renderer": "${software_renderer}",
  "report_file": "${REPORT_FILE}"
}
EOF

if [ "${status}" = "ready" ]; then
    echo "[OK] Vulkan readiness: ${readiness_class} (${reason})"
    echo "[OK] Report: ${REPORT_FILE}"
    exit 0
fi

echo "[WARN] Vulkan readiness: ${status} (${reason})"
echo "[WARN] Report: ${REPORT_FILE}"

if [ "${STRICT}" = "1" ]; then
    echo "[CRITICAL] RADICAL_VULKAN_STRICT=1 and Vulkan readiness failed."
    exit 1
fi

exit 0
