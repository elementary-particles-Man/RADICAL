# BOOT-RADICAL Vulkan Readiness Audit

## Audit Date

2026-05-09

## Scope

Audit a Vulkan readiness gate for RADICAL boot/testing profiles. BOOT-RADICAL remains a lightweight recovery/tooling boot environment for RADICAL testing. Vulkan is an acceleration/readiness signal, not a final security or session authority.

## Current State

- `scripts/check-boot-radical.sh` checks for RADICAL environment components and Linux LPE host posture.
- TUFF-Xwin is detected by directory presence, but Vulkan readiness is not checked.
- The environment example has build/dry-run toggles but no Vulkan profile or GPU/QEMU profile controls.
- BOOT-RADICAL currently does not broaden boot scope into full desktop policy or kernel GPU control.

## Readiness Gate Proposal

| Gate | Required for | Failure behavior | Evidence to collect |
| --- | --- | --- | --- |
| TUFF-Xwin present | Any Vulkan readiness check | Warn, do not fail baseline boot check | `TUFF-Xwin` path exists |
| Vulkan backend probe available | Vulkan profile runs | Warn in `qemu-safe`; fail only in explicit strict Vulkan profile | Probe binary/command exits and emits capability summary |
| Compute capability | Vulkan-heavy profile | Warn/fallback by default; strict mode may block Vulkan-heavy test profile | `compute_available`, device name, selected queue family |
| CPU fallback healthy | All profiles | Must pass; do not run Vulkan-only profile without fallback | `cargo test` fallback tests or backend probe fallback result |
| Security boundary acknowledged | All profiles | Must pass | Config states GPU is preflight only |

## Suggested Profiles

| Profile | Use case | Vulkan expectation |
| --- | --- | --- |
| `radical-qemu-safe` | QEMU and CI | Vulkan optional, CPU fallback normal |
| `radical-vulkan-smoke` | Developer machine with GPU | Probe Vulkan and run small preflight workload; fallback is warning |
| `radical-vulkan-strict` | Explicit GPU tuning session | Probe failure blocks only this profile, not general RADICAL boot |

## QEMU GPU Test Notes

- Current TUFF-RADICAL QEMU path uses `-vga std`; this is appropriate for framebuffer smoke, not Vulkan validation.
- A future test matrix should distinguish `std-vga-framebuffer`, `virtio-gpu-pci`, and host GPU/Vulkan-capable environments.
- BOOT-RADICAL should record which profile was requested and whether Vulkan was absent, fallback-only, or ready.

## Non-Goals

- Do not broaden BOOT-RADICAL beyond documented RADICAL testing.
- Do not require Vulkan for baseline boot.
- Do not use GPU results for final auth/session/watchdog decisions.
- Do not remove CPU fallback.
- Do not modify kernel logic from this audit.

## Recommended Next Steps

1. Add optional env keys such as `RADICAL_VULKAN_PROFILE`, `RADICAL_VULKAN_STRICT`, and `RADICAL_QEMU_GPU_PROFILE`.
2. Add a TUFF-Xwin Vulkan probe command or script that BOOT-RADICAL can call without starting the full desktop stack.
3. Extend `check-boot-radical.sh` to print readiness status: `absent`, `fallback-only`, `ready`, or `strict-fail`.
4. Keep strict failure limited to explicit Vulkan-heavy test profiles.
5. Store readiness output under `BOOT-RADICAL/out/` for CI comparison.

## Validation Notes

This is a documentation-only audit. Runtime validation should continue to run:

```text
bash BOOT-RADICAL/scripts/check-boot-radical.sh || true
```

