# RADICAL installer component

This directory contains the boot-time RADICAL installer entrypoint for generated install media.

- `radical-installer.sh` is the user-facing installer wrapper.
- `radical-installer.service` starts the wrapper on `tty1` from `multi-user.target`.
- The wrapper refuses to guess an install disk. Use `TARGET_DISK=/dev/xxx` for noninteractive runs, or confirm the target interactively.
- `release/install.sh` remains the canonical install backend.

The live Debian environment is only a carrier for the RADICAL installer; KDE Plasma, SDDM, and generic Debian Live sessions must not be the default boot experience.
