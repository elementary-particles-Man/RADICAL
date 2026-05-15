# RADICAL release

`release/` is the canonical RADICAL distribution and installation root for this repository. Use the lowercase directory name only.

## Commands

```bash
# Run the non-destructive real-hardware bring-up diagnostics.
release/bringup/radical-bringup.sh

# Install RADICAL into the default system locations.
sudo release/install.sh

# Remove installed RADICAL files while preserving configuration and state.
sudo release/uninstall.sh

# Validate the release tree, manifests, scripts, and available Cargo crates.
release/verify-release.sh

# Build available RADICAL release crates and write checksums under release/out/.
release/build-release.sh

# Generate release/MANIFEST.generated.toml with component file hashes.
release/generate-manifest.sh
```

## Install locations

`install.sh` and `uninstall.sh` support these environment overrides:

- `DESTDIR` defaults to `/opt/radical` and receives the component payloads.
- `BINDIR` defaults to `/usr/local/bin` and receives stable RADICAL launchers when built executables are present under component `bin/` or `target/` trees.
- `SYSCONFDIR` defaults to `/etc/radical` and stores host configuration.
- `STATE_DIR` defaults to `/var/lib/radical` and stores runtime state.

Example non-root smoke install:

```bash
DESTDIR=/tmp/radical-test-install \
BINDIR=/tmp/radical-test-bin \
SYSCONFDIR=/tmp/radical-test-etc \
STATE_DIR=/tmp/radical-test-state \
release/install.sh
```

Set `PURGE=1` for `release/uninstall.sh` only when configuration and state directories should also be removed.

## Component policy

The required RADICAL release components are:

- `kernel/`
- `rad-gpgpu/`
- `TUFF-Xwin/`
- `BOOT-RADICAL/`
- `TUFF-KAIRO/`
- `bringup/`
- `installer/`
- `uninstaller/`

The RADICAL GPGPU component directory and package name are both `rad-gpgpu`; its Rust library crate name remains `tuff_gpgpu` for source compatibility.

The legacy KAIRO background service package is deprecated and must not be installed, built, or listed by RADICAL release tooling.

TUFF-OS PID1/core payloads are outside this RADICAL release boundary and must not be added to this install set.


## Real-hardware bring-up default

Generated live/carrier media must default to the `RADICAL Bring-up / RADICAL Installer` text path, not Debian KDE Plasma. The live-build hook sets `multi-user.target`, enables the RADICAL installer service, and masks `display-manager.service`/`sddm.service`; boot menu labels are rewritten to RADICAL Bring-up / RADICAL Installer. KDE or Plasma payloads may exist only as manual debug layers and are not the default boot path.

`release/bringup/radical-bringup.sh` is diagnostics-first: it verifies the release, prints kernel/bootloader hashes, reports firmware mode, storage, GPU/framebuffer information, and refuses destructive installation unless `TARGET_DISK` is explicit and `RUN_INSTALL=1` is supplied.
