
# TUFF-RADICAL

TUFF-RADICAL is a Pure Rust bare-metal OS experiment targeting UEFI/QEMU. The current repository centers on a standalone kernel prototype, hardware-facing subsystems, and an accompanying Codex skill used to steer low-level development work.

## Repository Layout

- `TUFF-RADICAL-KERNEL/`: UEFI kernel crate, memory/paging setup, interrupt/GDT wiring, async task executor, GPU command-ring PoC, VirtIO block-device installation simulation, and in-memory ZRAM prototype.
- `skills/SKILL.md`: Development skill definition for the TUFF-RADICAL project.
- `tuff-radical-commander.skill`: Packaged version of the skill for distribution/import.
- `overhaul_docs.py`: Helper script for rewriting markdown documentation to TUFF-RADICAL terminology.

## Quick Start

```bash
cd TUFF-RADICAL-KERNEL
cargo build
./run_qemu.sh
```

## Notes

- Build artifacts and QEMU logs are intentionally git-ignored.
- This codebase is experimental and oriented toward low-level prototyping rather than production deployment.

## RADICAL release install unit

The lowercase `release/` directory is the canonical RADICAL distribution and install root. Do not use a parallel `Release/` tree.

Common commands:

```bash
sudo release/install.sh
sudo release/uninstall.sh
release/verify-release.sh
release/build-release.sh
release/generate-manifest.sh
```

`release/install.sh` supports `DESTDIR` (default `/opt/radical`), `BINDIR` (default `/usr/local/bin`), `SYSCONFDIR` (default `/etc/radical`), and `STATE_DIR` (default `/var/lib/radical`). The matching `release/uninstall.sh` preserves `SYSCONFDIR` and `STATE_DIR` unless `PURGE=1` is explicitly set.

`kairo-daemon` is deprecated and must not be installed, built, or listed in the RADICAL release manifest. `tuff-core` is TUFF-OS PID1/core scope and is not part of the RADICAL release install set. The RADICAL GPGPU component is `rad-gpgpu`, while its Rust library crate name remains `tuff_gpgpu` for source compatibility.

