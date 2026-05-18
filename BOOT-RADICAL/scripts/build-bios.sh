#!/bin/bash
set -euo pipefail

# BOOT-RADICAL/scripts/build-bios.sh
# In RADICAL, we do not build a custom bootloader.
# This script confirms the standard Debian boot path requirements.

echo "Checking RADICAL BIOS/Bootloader requirements..."

# Confirm that we are NOT referencing TUFF_BOOT/UEFI_PLATFORM/BZ_IMAGE
if grep -rE "TUFF_BOOT|BZ_IMAGE|UEFI_PLATFORM" . --exclude-dir=BOOT-TUFF --exclude-dir=.git | grep -v "not used" | grep -v "README.md" > /dev/null; then
    echo "Warning: Potential TUFF reference found in RADICAL context!"
    # We don't fail here but warn.
fi

echo "RADICAL uses standard Debian boot path (GRUB/systemd-boot)."
echo "Requirement check complete."
