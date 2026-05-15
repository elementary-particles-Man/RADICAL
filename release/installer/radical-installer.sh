#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="/var/log/radical-installer.log"
if touch "$LOG_FILE" >/dev/null 2>&1; then
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

banner() {
  cat <<'BANNER'
============================================================
  RADICAL Installer
  This media boots into the RADICAL installer flow.
  Debian live components are only the carrier environment.
============================================================
BANNER
}

script_dir() {
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd
}

find_install_sh() {
  local here
  here="$(script_dir)"

  local candidates=(
    "${RADICAL_RELEASE_ROOT:-}/install.sh"
    "$here/install.sh"
    "$here/../install.sh"
    "$here/../../install.sh"
    "/opt/radical/release/install.sh"
    "/usr/local/share/radical/release/install.sh"
    "/run/live/medium/release/install.sh"
    "/run/live/medium/install.sh"
    "/cdrom/release/install.sh"
    "/cdrom/install.sh"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    [[ -n "$candidate" ]] || continue
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

validate_target_disk() {
  local disk=$1
  if [[ -z "$disk" ]]; then
    echo "TARGET_DISK is empty." >&2
    return 1
  fi
  if [[ ! -b "$disk" ]]; then
    echo "TARGET_DISK is not a block device: $disk" >&2
    return 1
  fi
}

select_target_disk() {
  if [[ -n "${TARGET_DISK:-}" ]]; then
    validate_target_disk "$TARGET_DISK"
    printf '%s\n' "$TARGET_DISK"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    cat >&2 <<'EOF_REFUSE'
TARGET_DISK is required in noninteractive installer mode.
Refusing to guess an installation disk.
EOF_REFUSE
    return 1
  fi

  echo
  echo "Available disks:"
  lsblk -dpno NAME,SIZE,TRAN,RM,TYPE,MODEL | awk '$5 == "disk" { print "  " $0 }' || true
  echo
  read -r -p "Enter target disk for RADICAL installation (example: /dev/sda): " selected_disk
  validate_target_disk "$selected_disk"

  echo
  echo "WARNING: RADICAL installation target is: $selected_disk"
  read -r -p "Type RADICAL-INSTALL to confirm this explicit target: " confirmation
  if [[ "$confirmation" != "RADICAL-INSTALL" ]]; then
    echo "Confirmation did not match. Aborting without installation." >&2
    return 1
  fi

  printf '%s\n' "$selected_disk"
}

main() {
  banner

  local install_sh target_disk
  if ! install_sh="$(find_install_sh)"; then
    cat >&2 <<'EOF_MISSING'
ERROR: release/install.sh was not found on this installer media or installed release tree.
RADICAL installer cannot continue because release/install.sh is the canonical install entrypoint.
EOF_MISSING
    exit 1
  fi

  target_disk="$(select_target_disk)"

  echo
  echo "Using canonical installer backend: $install_sh"
  echo "Confirmed target disk: $target_disk"
  echo

  export TARGET_DISK="$target_disk"
  exec "$install_sh" "$@"
}

main "$@"
