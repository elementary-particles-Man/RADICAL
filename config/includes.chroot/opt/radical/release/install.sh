#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_root="$script_dir"

DESTDIR="${DESTDIR:-/opt/radical}"
BINDIR="${BINDIR:-/usr/local/bin}"
SYSCONFDIR="${SYSCONFDIR:-/etc/radical}"
STATE_DIR="${STATE_DIR:-/var/lib/radical}"
DRY_RUN="${DRY_RUN:-0}"

components=(kernel rad-gpgpu TUFF-Xwin BOOT-RADICAL TUFF-KAIRO installer uninstaller)
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

copy_tree() {
  local src=$1
  local dst=$2
  run mkdir -p "$dst"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '+ copy contents %q -> %q\n' "$src" "$dst"
    return 0
  fi
  shopt -s dotglob nullglob
  local entries=("$src"/*)
  if ((${#entries[@]} > 0)); then
    cp -a "${entries[@]}" "$dst"/
  fi
  shopt -u dotglob nullglob
}

is_forbidden_component() {
  local path=$1
  local legacy_core="tuff-""core"
  local legacy_gpgpu="tuff-""gpgpu"
  local legacy_kairo="kairo-""daemon"
  case "/$path/" in
    */${legacy_core}/*|*/${legacy_gpgpu}/*|*/${legacy_kairo}/*) return 0 ;;
    *) return 1 ;;
  esac
}

install_launcher() {
  local component=$1
  local src=$2
  local base launcher target
  base="$(basename "$src")"
  launcher="radical-${component}-${base}"
  target="$BINDIR/$launcher"

  run mkdir -p "$BINDIR"
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '+ write launcher %q -> %q\n' "$target" "$src"
    printf '+ record launcher %q\n' "$target"
    return 0
  fi

  cat > "$target" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
exec "$DESTDIR/$component/${src#"$release_root/$component/"}" "\$@"
WRAPPER
  chmod 0755 "$target"
  printf '%s\n' "$target" >> "$launcher_record"
}

install_component_launchers() {
  local component=$1
  local component_root="$release_root/$component"
  [[ -d "$component_root" ]] || return 0

  local search_roots=()
  [[ -d "$component_root/bin" ]] && search_roots+=("$component_root/bin")
  [[ -d "$component_root/target" ]] && search_roots+=("$component_root/target")
  ((${#search_roots[@]} > 0)) || return 0

  local src rel
  while IFS= read -r -d '' src; do
    rel="${src#"$component_root/"}"
    case "$rel" in
      target/debug/deps/*|target/release/deps/*|target/*/build/*|*.d|*.rlib|*.rmeta) continue ;;
    esac
    [[ -f "$src" && -x "$src" ]] || continue
    install_launcher "$component" "$src"
  done < <(find "${search_roots[@]}" -type f -perm -111 -print0 2>/dev/null)
}

main() {
  run mkdir -p "$DESTDIR" "$SYSCONFDIR" "$STATE_DIR"
  if [[ "$DRY_RUN" != "1" ]]; then
    : > "$launcher_record"
  fi

  local component src dst
  for component in "${components[@]}"; do
    src="$release_root/$component"
    dst="$DESTDIR/$component"
    if [[ ! -d "$src" ]]; then
      echo "missing release component: $component" >&2
      exit 1
    fi
    if is_forbidden_component "$component"; then
      echo "refusing forbidden release component: $component" >&2
      exit 1
    fi
    copy_tree "$src" "$dst"
    install_component_launchers "$component"
  done

  if [[ ! -f "$release_root/MANIFEST.toml" ]]; then
    echo "missing release manifest: $release_root/MANIFEST.toml" >&2
    exit 1
  fi
  run cp "$release_root/MANIFEST.toml" "$DESTDIR/MANIFEST.toml"

  echo "Installed RADICAL release into $DESTDIR"
  echo "Configuration directory: $SYSCONFDIR"
  echo "State directory: $STATE_DIR"
  echo "Installed components:"
  printf '  - %s\n' "${components[@]}"
}

main "$@"
