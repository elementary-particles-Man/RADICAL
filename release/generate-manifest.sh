#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
release_root="$script_dir"
manifest="$release_root/MANIFEST.generated.toml"
components=(kernel rad-gpgpu TUFF-Xwin BOOT-RADICAL TUFF-KAIRO bringup installer uninstaller)

sha_for_component() {
  local component=$1
  local dir="$release_root/$component"
  [[ -d "$dir" ]] || return 0
  while IFS= read -r -d '' file; do
    local rel sha
    rel="${file#"$release_root/"}"
    sha="$(sha256sum "$file" | awk '{print $1}')"
    printf '[[component.file]]\n'
    printf 'path = "%s"\n' "$rel"
    printf 'sha256 = "%s"\n\n' "$sha"
  done < <(find "$dir" -type f ! -path '*/target/*' -print0 | sort -z)
}

main() {
  local tmp
  tmp="$(mktemp)"
  {
    printf '# Generated RADICAL release manifest. Do not edit by hand.\n'
    printf 'origin = "RADICAL"\n'
    printf 'schema_version = 1\n\n'
    local component
    printf '[[bringup_entrypoint]]\n'
    printf 'name = "RADICAL Bring-up"\n'
    printf 'origin = "RADICAL"\n'
    printf 'script = "bringup/radical-bringup.sh"\n'
    printf 'service = "bringup/radical-bringup.service"\n'
    printf 'default_target = "multi-user.target"\n'
    printf 'boot_marker = "radical.installer=1"\n\n'

    printf '[[installer_entrypoint]]\n'
    printf 'name = "RADICAL Installer"\n'
    printf 'origin = "RADICAL"\n'
    printf 'script = "installer/radical-installer.sh"\n'
    printf 'service = "installer/radical-installer.service"\n'
    printf 'backend = "install.sh"\n'
    printf 'default_target = "multi-user.target"\n'
    printf 'boot_marker = "radical.installer=1"\n\n'

    for component in "${components[@]}"; do
      printf '[[component]]\n'
      printf 'name = "%s"\n' "$component"
      printf 'path = "%s/"\n' "$component"
      printf 'required = true\n'
      if [[ "$component" == "rad-gpgpu" ]]; then
        printf 'rust_package = "rad-gpgpu"\n'
        printf 'rust_lib = "tuff_gpgpu"\n'
        printf 'note = "The RADICAL GPGPU package exports the tuff_gpgpu Rust library name for source compatibility."\n'
      fi
      printf '\n'
      sha_for_component "$component"
    done
  } > "$tmp"
  mv "$tmp" "$manifest"
  echo "Wrote $manifest"
}

main "$@"
