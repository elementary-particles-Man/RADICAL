#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_root="$script_dir"
out_dir="$release_root/out"
components=(rad-gpgpu TUFF-KAIRO TUFF-Xwin uninstaller installer)

run_cargo_build() {
  local component=$1
  shift
  local dir="$release_root/$component"
  if [[ -f "$dir/Cargo.toml" ]]; then
    echo "Building release/$component: cargo $*"
    (cd "$dir" && cargo "$@")
  else
    echo "Skipping release/$component: no Cargo.toml"
  fi
}

collect_artifacts() {
  local component=$1
  local dir="$release_root/$component"
  local dst="$out_dir/$component"
  [[ -d "$dir/target/release" ]] || return 0
  mkdir -p "$dst"

  local artifact
  while IFS= read -r -d '' artifact; do
    case "$artifact" in
      */deps/*|*/build/*|*.d|*.rmeta) continue ;;
    esac
    [[ -f "$artifact" ]] || continue
    cp -a "$artifact" "$dst/"
  done < <(find "$dir/target/release" -maxdepth 2 -type f \( -perm -111 -o -name '*.rlib' -o -name '*.so' -o -name '*.a' \) -print0 2>/dev/null)
}

collect_installer_entrypoint() {
  mkdir -p "$out_dir/installer"
  install -m 0755 "$release_root/installer/radical-installer.sh" "$out_dir/installer/radical-installer.sh"
  install -m 0644 "$release_root/installer/radical-installer.service" "$out_dir/installer/radical-installer.service"
}

generate_checksums() {
  mkdir -p "$out_dir"
  : > "$out_dir/SHA256SUMS"
  if find "$out_dir" -type f ! -name SHA256SUMS -print -quit | rg . >/dev/null; then
    (cd "$out_dir" && find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS)
  fi
  echo "Wrote $out_dir/SHA256SUMS"
}

main() {
  run_cargo_build rad-gpgpu build --release
  run_cargo_build TUFF-KAIRO build --workspace --release
  run_cargo_build TUFF-Xwin build --workspace --release
  run_cargo_build uninstaller build --release
  run_cargo_build installer build --release

  local component
  for component in "${components[@]}"; do
    collect_artifacts "$component"
  done
  collect_installer_entrypoint
  generate_checksums
  echo "RADICAL release build completed."
}

main "$@"
