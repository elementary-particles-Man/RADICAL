# RADICAL Kernel Secret FD Exposure Boundary — 2026-05-19

## Scope

This document records the RADICAL kernel-side response to the Linux CVE-2026-46333 / `ssh-keysign-pwn` class.

The Linux issue depends on Linux-specific process lifetime semantics around `ptrace`, `pidfd_getfd`, `task->mm`, and fdtable cleanup. RADICAL is a Rust UEFI/bare-metal kernel prototype and does not currently implement those Linux ABI surfaces.

## Kernel Boundary

RADICAL-KERNEL keeps the following surfaces absent by default:

- Linux `ptrace` ABI
- Linux `pidfd_getfd` ABI
- `/proc/<pid>/fd` style fd aliasing
- Cross-process FD duplication
- `ssh-keysign` / `chage` helper execution path

The boot path now calls `kernel_security::assert_secret_fd_boundary_sealed()` before the UEFI `ExitBootServices` handoff. This is a fail-closed guard for future kernel evolution: if the kernel later grows any process-introspection or cross-process FD duplication surface, this boundary must be deliberately redesigned instead of silently inheriting Linux-style risk.

## Non-goals

This is not a Linux patch backport. RADICAL is not a Linux kernel tree and does not contain the vulnerable Linux code path.

No exploit logic is included:

- No `pidfd_getfd`
- No `ptrace`
- No process-exit race harness
- No `ssh-keysign` execution
- No `chage` execution
- No `/etc/shadow` reads
- No SSH private key reads

## Changed Files

- `RADICAL-KERNEL/src/kernel_security.rs`
- `RADICAL-KERNEL/src/main.rs`
- `docs/status/RADICAL_KERNEL_SECRET_FD_EXPOSURE_BOUNDARY_20260519.md`

## Validation

Recommended local validation:

```bash
cd RADICAL-KERNEL
cargo fmt --check
cargo check
cargo build --release
./run_qemu.sh
```
