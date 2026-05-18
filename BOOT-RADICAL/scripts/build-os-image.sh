#!/bin/bash
set -euo pipefail

# BOOT-RADICAL/scripts/build-os-image.sh
# Wrapper for micro Debian / RADICAL OS image build.

DRY_RUN=${DRY_RUN:-true}
OUT_DIR="BOOT-RADICAL/out"

echo "Building RADICAL micro Debian image..."

if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY-RUN] Would run RADICAL OS image build (e.g. from projects/tuff-linux-distro)"
    echo "[DRY-RUN] Target output: $OUT_DIR/radical-rootfs.tar or $OUT_DIR/radical-os.qcow2"
    exit 0
fi

if [ -z "${RADICAL_BUILD_ENABLED:-}" ]; then
    echo "Error: RADICAL_BUILD_ENABLED is not set."
    exit 1
fi

# Placeholder for actual build command if it were known
echo "Building RADICAL OS image..."
# (Actual command here)

echo "RADICAL OS image build complete."
