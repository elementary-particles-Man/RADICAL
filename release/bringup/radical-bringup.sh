#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_root="$(cd -- "$script_dir/.." && pwd)"
repo_root="$(cd -- "$release_root/.." && pwd)"

sha256_file() {
  local path=$1
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    printf 'sha256 tool unavailable'
  fi
}

first_existing_file() {
  local path
  for path in "$@"; do
    if [[ -f "$path" ]]; then
      printf '%s\n' "$path"
      return 0
    fi
  done
  return 1
}

find_kernel_artifact() {
  first_existing_file \
    "$repo_root/TUFF-RADICAL-KERNEL/target/x86_64-unknown-uefi/debug/tuff-radical-kernel.efi" \
    "$repo_root/TUFF-RADICAL-KERNEL/target/x86_64-unknown-uefi/release/tuff-radical-kernel.efi" \
    "$release_root/kernel/tuff-radical-kernel.efi" \
    "$release_root/kernel/radical-kernel.efi" || true
}

find_bootloader_artifact() {
  first_existing_file \
    "$release_root/BOOT-RADICAL/BOOTX64.EFI" \
    "$release_root/BOOT-RADICAL/bootx64.efi" \
    "$release_root/BOOT-RADICAL/radical-bootloader.efi" || true
}

print_artifact() {
  local label=$1
  local path=$2
  if [[ -n "$path" && -f "$path" ]]; then
    echo "$label: $path"
    echo "$label sha256: $(sha256_file "$path")"
  else
    echo "$label: missing"
  fi
}

print_disks() {
  echo
  echo "[storage/disks]"
  if command -v lsblk >/dev/null 2>&1; then
    lsblk -dpno NAME,SIZE,TRAN,RM,ROTA,TYPE,MODEL | awk '$6 == "disk" { print "  " $0 }' || true
  else
    echo "  lsblk unavailable"
  fi

  echo
  echo "[storage driver support]"
  if command -v lspci >/dev/null 2>&1; then
    lspci -nn | awk '
      /Virtio|1af4/ { virtio=1; print "  virtio present: " $0 }
      /Non-Volatile memory controller|NVM Express|0108/ { nvme=1; print "  nvme controller present: " $0 }
      /SATA controller|AHCI|0106/ { ahci=1; print "  ahci controller present: " $0 }
      END {
        if (!virtio) print "  virtio: not detected"
        if (!nvme) print "  nvme: driver missing in RADICAL kernel; install disabled"
        if (!ahci) print "  ahci: driver missing in RADICAL kernel; install disabled"
      }'
  else
    echo "  lspci unavailable; kernel supports VirtIO probe only, NVMe/AHCI install disabled"
  fi
}

print_graphics() {
  echo
  echo "[graphics/framebuffer]"
  if [[ -d /sys/class/graphics ]]; then
    local node
    for node in /sys/class/graphics/*; do
      [[ -e "$node" ]] || continue
      printf '  %s' "$(basename "$node")"
      [[ -r "$node/modes" ]] && printf ' modes=%s' "$(tr '\n' ',' < "$node/modes" | sed 's/,$//')"
      [[ -r "$node/virtual_size" ]] && printf ' virtual_size=%s' "$(cat "$node/virtual_size")"
      echo
    done
  else
    echo "  /sys/class/graphics unavailable"
  fi

  if command -v lspci >/dev/null 2>&1; then
    lspci -nn | awk '/VGA compatible controller|3D controller|Display controller/ { print "  pci: " $0 }'
  else
    echo "  lspci unavailable"
  fi
}

banner() {
  cat <<'BANNER'
============================================================
  RADICAL Bring-up / RADICAL Installer text path
  KDE Plasma and Debian Live desktop autostart are disabled.
  This stage is diagnostics-first and non-destructive by default.
============================================================
BANNER
}

main() {
  banner

  if [[ -x "$release_root/verify-release.sh" ]]; then
    echo "[verify] running release/verify-release.sh first"
    "$release_root/verify-release.sh"
  else
    echo "[verify] release/verify-release.sh not found or not executable"
  fi

  echo
  echo "[artifacts]"
  local kernel_artifact bootloader_artifact firmware_mode
  kernel_artifact="$(find_kernel_artifact)"
  bootloader_artifact="$(find_bootloader_artifact)"
  print_artifact "kernel" "$kernel_artifact"
  print_artifact "bootloader" "$bootloader_artifact"

  if [[ -d /sys/firmware/efi ]]; then
    firmware_mode="UEFI"
  else
    firmware_mode="BIOS/CSM or non-Linux carrier"
  fi
  echo
  echo "[firmware] $firmware_mode"

  print_disks
  print_graphics

  echo
  echo "[boot policy] default target is RADICAL Bring-up / RADICAL Installer on multi-user.target. KDE/SDDM is not launched."

  if [[ -z "${TARGET_DISK:-}" ]]; then
    cat <<EOF_STOP

TARGET_DISK is not set. Diagnostics complete; no destructive install was attempted.
To run the installer explicitly, use:
  sudo TARGET_DISK=/dev/sdX RUN_INSTALL=1 $release_root/bringup/radical-bringup.sh
EOF_STOP
    return 0
  fi

  if [[ ! -b "$TARGET_DISK" ]]; then
    echo "TARGET_DISK is not a block device: $TARGET_DISK" >&2
    return 1
  fi

  if [[ "${RUN_INSTALL:-0}" != "1" ]]; then
    cat <<EOF_ARM
TARGET_DISK is set to $TARGET_DISK, but RUN_INSTALL=1 is not set.
No destructive install was attempted. Exact install command:
  sudo TARGET_DISK=$TARGET_DISK RUN_INSTALL=1 $release_root/bringup/radical-bringup.sh
EOF_ARM
    return 0
  fi

  echo "RUN_INSTALL=1 and explicit TARGET_DISK=$TARGET_DISK confirmed. Launching RADICAL installer."
  exec "$release_root/installer/radical-installer.sh" "$@"
}

main "$@"
