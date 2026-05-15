# RADICAL release

`release/` is the canonical RADICAL distribution and installation root for this repository. Use the lowercase directory name only.

## Commands

```bash
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
- `installer/`
- `uninstaller/`

The RADICAL GPGPU component directory and package name are both `rad-gpgpu`; its Rust library crate name remains `tuff_gpgpu` for source compatibility.

The legacy KAIRO background service package is deprecated and must not be installed, built, or listed by RADICAL release tooling.

TUFF-OS PID1/core payloads are outside this RADICAL release boundary and must not be added to this install set.
