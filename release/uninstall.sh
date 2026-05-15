#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_root="$script_dir"

DESTDIR="${DESTDIR:-/opt/radical}"
BINDIR="${BINDIR:-/usr/local/bin}"
SYSCONFDIR="${SYSCONFDIR:-/etc/radical}"
STATE_DIR="${STATE_DIR:-/var/lib/radical}"
PURGE="${PURGE:-0}"
DRY_RUN="${DRY_RUN:-0}"

components=(kernel rad-gpgpu TUFF-Xwin BOOT-RADICAL TUFF-KAIRO bringup installer uninstaller)
launcher_record="$DESTDIR/.radical-launchers"

run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '+ '
    printf '%q ' "$@"
    printf '\n'
  else
    "$@"
  fi
}

remove_launchers() {
  if [[ -f "$launcher_record" ]]; then
    while IFS= read -r launcher; do
      [[ -n "$launcher" ]] || continue
      case "$launcher" in
        "$BINDIR"/radical-*) run rm -f "$launcher" ;;
      esac
    done < "$launcher_record"
  fi

  if [[ -d "$BINDIR" ]]; then
    local launcher
    while IFS= read -r -d '' launcher; do
      run rm -f "$launcher"
    done < <(find "$BINDIR" -maxdepth 1 -type f -name 'radical-*' -print0 2>/dev/null)
  fi
}

main() {
  remove_launchers

  local component
  for component in "${components[@]}"; do
    run rm -rf "$DESTDIR/$component"
  done
  run rm -f "$DESTDIR/MANIFEST.toml" "$launcher_record"
  if [[ -d "$DESTDIR" ]]; then
    run rmdir "$DESTDIR" 2>/dev/null || true
  fi

  if [[ "$PURGE" == "1" ]]; then
    run rm -rf "$SYSCONFDIR" "$STATE_DIR"
  else
    echo "Preserved configuration directory: $SYSCONFDIR"
    echo "Preserved state directory: $STATE_DIR"
  fi

  echo "Removed RADICAL release from $DESTDIR"
  echo "Removed components:"
  printf '  - %s\n' "${components[@]}"
}

main "$@"
