# RADICAL bring-up console

`radical-bringup.sh` is the first-stage real-hardware diagnostic entrypoint for RADICAL media.
It is intentionally text/TTY oriented and must be the default carrier-media path instead of Debian KDE Plasma.

The script:

- runs `release/verify-release.sh` first when available;
- prints the RADICAL kernel and bootloader artifact paths plus SHA-256 hashes;
- reports UEFI vs BIOS/CSM carrier mode;
- lists detected disks with `lsblk` when available;
- summarizes VirtIO/NVMe/AHCI visibility without claiming missing NVMe/AHCI install support;
- reports GOP/framebuffer-related Linux carrier information from `/sys/class/graphics` and `lspci` when available;
- refuses destructive installation unless `TARGET_DISK` is explicit and `RUN_INSTALL=1` is also supplied.

Example diagnostics-only boot path:

```bash
release/bringup/radical-bringup.sh
```

Explicit installer launch after diagnostics:

```bash
sudo TARGET_DISK=/dev/sdX RUN_INSTALL=1 release/bringup/radical-bringup.sh
```
