# BOOT-RADICAL Vulkan Readiness Gate Implementation

## Summary

This change adds a BOOT-RADICAL Vulkan readiness gate for RADICAL/Xwin boot validation.

The gate is intentionally QEMU/headless safe:

- non-strict mode records readiness and exits successfully even when Vulkan is unavailable;
- strict mode blocks only when `RADICAL_VULKAN_STRICT=1` and readiness fails;
- software Vulkan such as llvmpipe/lavapipe is allowed by default for validation profiles;
- Vulkan readiness remains an acceleration/preflight signal and is not used as final authority for auth, session, lock, or watchdog decisions.

## Added Files

- `BOOT-RADICAL/scripts/check-vulkan-readiness.sh`
- `BOOT-RADICAL/docs/status/BOOT_RADICAL_VULKAN_READINESS_GATE_IMPLEMENTATION.md`

## Updated Files

- `BOOT-RADICAL/scripts/check-boot-radical.sh`
- `BOOT-RADICAL/config/boot-radical.env.example`

## Runtime Policy

| Variable | Default | Meaning |
| :--- | :--- | :--- |
| `RADICAL_VULKAN_STRICT` | `0` | `0` warns/reports only; `1` fails when readiness is not available. |
| `RADICAL_VULKAN_ALLOW_SOFTWARE` | `1` | Allows software Vulkan for QEMU/headless validation. |
| `RADICAL_VULKANINFO_TIMEOUT_SECONDS` | `8` | Timeout for `vulkaninfo --summary`. |
| `RADICAL_VULKAN_REPORT_DIR` | `BOOT-RADICAL/out` | Directory for readiness report. |
| `RADICAL_VULKAN_REPORT` | derived | Full report path override. |
| `RADICAL_BOOT_PROFILE` | `default` | Profile label recorded in the report. |

## Readiness Classes

- `hardware`: `vulkaninfo --summary` succeeds and does not look like a software renderer.
- `software`: `vulkaninfo --summary` succeeds and reports llvmpipe/lavapipe/software/SwiftShader.
- `missing`: loader, ICD, DRI, or `vulkaninfo` is missing or fails.

## Report

The gate writes JSON to `BOOT-RADICAL/out/vulkan-readiness.json` by default.

The report contains:

- profile
- status
- readiness_class
- reason
- strict
- allow_software
- loader
- icd
- dri
- vulkaninfo_status
- software_renderer
- report_file

## Validation

Expected validation commands:

```bash
bash BOOT-RADICAL/scripts/check-vulkan-readiness.sh || true
RADICAL_VULKAN_STRICT=1 RADICAL_VULKAN_ALLOW_SOFTWARE=1 bash BOOT-RADICAL/scripts/check-vulkan-readiness.sh || true
bash BOOT-RADICAL/scripts/check-boot-radical.sh || true
bash -n BOOT-RADICAL/scripts/check-vulkan-readiness.sh
bash -n BOOT-RADICAL/scripts/check-boot-radical.sh
```

## Non-Goals

- Do not make Vulkan a final security authority.
- Do not require Vulkan in non-strict QEMU/headless smoke checks.
- Do not use GPU readiness for lockd/auth/sessiond/watchdog decisions.
- Do not broaden BOOT-RADICAL beyond RADICAL/KAIRO/Xwin/Chromium testing.
