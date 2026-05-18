#!/bin/bash
set -euo pipefail

# BOOT-RADICAL/scripts/check-boot-radical.sh
# Checks for existence of RADICAL image / rootfs / boot disk artifacts.

echo "Checking RADICAL boot artifacts..."

CHECK_FAIL=0

# Check for KAIRO binaries
if [ -d "TUFF-KAIRO" ]; then
    echo "[OK] Found: TUFF-KAIRO directory"
else
    echo "[MISSING] Not found: TUFF-KAIRO directory"
    CHECK_FAIL=1
fi

# Check for tuffutl
if [ -f "TUFF-KAIRO/TUFF-UTL/target/release/tuffutl" ] || [ -f "TUFF-UTL/target/release/tuffutl" ]; then
    echo "[OK] Found: tuffutl"
else
    echo "[MISSING] Not found: tuffutl"
    # Not necessarily a fail for boot artifacts but a warning for RADICAL smoke
fi

# Check for Xwin scripts
if [ -d "TUFF-Xwin" ]; then
    echo "[OK] Found: TUFF-Xwin"
else
    echo "[MISSING] Not found: TUFF-Xwin"
fi

if [ $CHECK_FAIL -eq 0 ]; then
    echo "Basic RADICAL environment components are present."
else
    echo "Some RADICAL environment components are missing."
fi

# Vulkan Readiness Gate (RADICAL/Xwin acceleration preflight)
if [ -f "BOOT-RADICAL/scripts/check-vulkan-readiness.sh" ]; then
    echo ""
    echo "Running BOOT-RADICAL Vulkan Readiness Gate..."
    if ! bash ./BOOT-RADICAL/scripts/check-vulkan-readiness.sh; then
        echo "[CRITICAL] Vulkan readiness: FATAL. RADICAL Vulkan profile blocked by policy."
        exit 1
    fi
else
    echo "[MISSING] Vulkan readiness gate script not found."
    if [ "${RADICAL_VULKAN_STRICT:-0}" = "1" ]; then
        exit 1
    fi
fi

# Linux LPE Posture Check (RADICAL inherited Linux risk)
if [ -f "BOOT-RADICAL/scripts/check-linux-lpe-posture.sh" ]; then
    echo ""
    echo "Running QEMU Boot Smoke Harness...
    bash BOOT-RADICAL/scripts/qemu-boot-smoke.sh || true

Running Linux LPE Host Posture Gate..."
    if ! ./BOOT-RADICAL/scripts/check-linux-lpe-posture.sh; then
        echo "[CRITICAL] Linux LPE Posture: FATAL. RADICAL execution path blocked by security policy."
        if [ "${STRICT_SECURITY:-0}" = "1" ]; then
            exit 1
        fi
    fi
fi

exit 0
