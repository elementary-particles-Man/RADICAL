#!/bin/bash
set -euo pipefail

# BOOT-RADICAL/scripts/build-boot-disk.sh
# Creates RADICAL boot disk image (Standard Debian boot).

DRY_RUN=${DRY_RUN:-true}
OUT_DIR="BOOT-RADICAL/out"
TARGET_IMG="$OUT_DIR/radical-boot.qcow2"

echo "Creating RADICAL boot disk..."

if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY-RUN] Would run: qemu-img create -f qcow2 $TARGET_IMG 32G"
    echo "[DRY-RUN] Would configure GRUB/systemd-boot for micro Debian."
    exit 0
fi

if [ -z "${RADICAL_BUILD_ENABLED:-}" ]; then
    echo "Error: RADICAL_BUILD_ENABLED is not set."
    exit 1
fi

qemu-img create -f qcow2 "$TARGET_IMG" 32G
echo "RADICAL boot disk created: $TARGET_IMG"
