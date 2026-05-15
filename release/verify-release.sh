#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_root="$script_dir"

required_dirs=(kernel rad-gpgpu TUFF-Xwin BOOT-RADICAL TUFF-KAIRO installer uninstaller)
forbidden_dirs=("tuff-""core" "tuff-""gpgpu" "kairo-""daemon" "TUFF-KAIRO/kairo-""daemon")

failures=0

fail() {
  echo "FAIL: $*" >&2
  failures=$((failures + 1))
}

pass() {
  echo "PASS: $*"
}

check_required_dirs() {
  local dir
  for dir in "${required_dirs[@]}"; do
    if [[ -d "$release_root/$dir" ]]; then
      pass "required directory exists: release/$dir"
    else
      fail "missing required directory: release/$dir"
    fi
  done
}

check_forbidden_dirs() {
  local dir
  for dir in "${forbidden_dirs[@]}"; do
    if [[ -e "$release_root/$dir" ]]; then
      fail "forbidden release path exists: release/$dir"
    else
      pass "forbidden path absent: release/$dir"
    fi
  done
}

check_legacy_references() {
  local legacy_pattern legacy_core
  local legacy_dash="kairo-""daemon"
  local legacy_under="kairo_""daemon"
  legacy_pattern="${legacy_dash}|${legacy_under}|KAIRO[[:space:]]daemon|kairo[[:space:]]daemon"
  legacy_core="tuff-""core"
  if rg -n "$legacy_pattern" "$release_root" >/tmp/radical-legacy-scan.txt 2>/dev/null; then
    if rg -v 'deprecated|Deprecated|DEPRECATED|legacy|Legacy' /tmp/radical-legacy-scan.txt >/tmp/radical-legacy-active.txt; then
      cat /tmp/radical-legacy-active.txt >&2
      fail "active legacy KAIRO service references remain under release/"
    else
      pass "only explicitly deprecated legacy KAIRO service references remain"
    fi
  else
    pass "no legacy KAIRO service references under release/"
  fi

  if find "$release_root" -path "*/$legacy_core" -o -path "*/$legacy_core/*" | rg . >/tmp/radical-core-paths.txt; then
    cat /tmp/radical-core-paths.txt >&2
    fail "TUFF-OS core paths must not exist in RADICAL release"
  else
    pass "no TUFF-OS core paths under release/"
  fi
}

check_rad_gpgpu_manifest() {
  local cargo="$release_root/rad-gpgpu/Cargo.toml"
  if [[ ! -f "$cargo" ]]; then
    fail "missing release/rad-gpgpu/Cargo.toml"
    return
  fi
  rg -n '^name = "rad-gpgpu"$' "$cargo" >/dev/null || fail "rad-gpgpu package name is not rad-gpgpu"
  rg -n '^name = "tuff_gpgpu"$' "$cargo" >/dev/null || fail "rad-gpgpu lib name is not tuff_gpgpu"
  pass "rad-gpgpu Cargo package/lib names verified"
}

check_gpgpu_dependencies() {
  local component cargo
  for component in TUFF-KAIRO TUFF-Xwin; do
    cargo="$release_root/$component/Cargo.toml"
    [[ -f "$cargo" ]] || { pass "$component has no Cargo.toml dependency graph to check"; continue; }
    if rg -n 'tuff_gpgpu|rad[-_]gpgpu|gpgpu' "$cargo" >/dev/null; then
      if rg -n 'package[[:space:]]*=[[:space:]]*"rad-gpgpu"' "$cargo" >/dev/null; then
        pass "$component GPGPU dependency uses package = \"rad-gpgpu\""
      else
        fail "$component GPGPU dependency must use package = \"rad-gpgpu\""
      fi
    else
      pass "$component has no GPGPU dependency entry"
    fi
  done
}

check_installer_entrypoint() {
  local script="$release_root/installer/radical-installer.sh"
  local service="$release_root/installer/radical-installer.service"

  if [[ -x "$script" ]]; then
    pass "installer entrypoint is executable: release/installer/radical-installer.sh"
  else
    fail "installer entrypoint missing or not executable: release/installer/radical-installer.sh"
  fi

  if [[ -f "$service" ]]; then
    pass "installer service exists: release/installer/radical-installer.service"
  else
    fail "installer service missing: release/installer/radical-installer.service"
  fi

  rg -n 'ExecStart=/usr/local/sbin/radical-installer' "$service" >/dev/null || fail "installer service must launch radical-installer"
  rg -n 'WantedBy=multi-user.target' "$service" >/dev/null || fail "installer service must be wanted by multi-user.target"
  if rg -n 'graphical.target' "$service" >/dev/null; then
    fail "installer service must not require graphical.target"
  else
    pass "installer service does not require graphical.target"
  fi
  rg -n 'RADICAL Installer' "$release_root/MANIFEST.toml" >/dev/null || fail "manifest must list RADICAL Installer entrypoint"
  rg -n 'origin = "RADICAL"' "$release_root/MANIFEST.toml" >/dev/null || fail "manifest must state origin = \"RADICAL\""
}

check_shell_syntax() {
  local script
  for script in install.sh uninstall.sh build-release.sh generate-manifest.sh installer/radical-installer.sh; do
    if bash -n "$release_root/$script"; then
      pass "bash syntax: release/$script"
    else
      fail "bash syntax failed: release/$script"
    fi
  done
}

cargo_check_if_present() {
  local dir=$1
  shift
  if [[ -f "$release_root/$dir/Cargo.toml" ]]; then
    echo "Running cargo check in release/$dir: cargo $*"
    if (cd "$release_root/$dir" && cargo "$@"); then
      pass "cargo $* succeeded in release/$dir"
    else
      fail "cargo $* failed in release/$dir"
    fi
  else
    pass "release/$dir has no Cargo.toml; cargo check skipped"
  fi
}

main() {
  check_required_dirs
  check_forbidden_dirs
  check_legacy_references
  check_rad_gpgpu_manifest
  check_gpgpu_dependencies
  check_installer_entrypoint
  check_shell_syntax
  cargo_check_if_present rad-gpgpu check
  cargo_check_if_present TUFF-KAIRO check --workspace
  cargo_check_if_present TUFF-Xwin check --workspace

  if ((failures > 0)); then
    echo "RADICAL release verification failed with $failures failure(s)." >&2
    exit 1
  fi
  echo "RADICAL release verification passed."
}

main "$@"
