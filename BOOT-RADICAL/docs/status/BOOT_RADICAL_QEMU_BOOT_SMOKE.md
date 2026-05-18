# BOOT-RADICAL QEMU Boot Smoke Harness

## Normalization Date
2026-05-09

## Base Commit
`7c8293c74df9678bda62fd190ca67bd572627e6b`

## Summary
The `BOOT-RADICAL` QEMU boot smoke harness provides a validation layer for RADICAL environment boot artifacts. It attempts to boot a target QEMU image and monitors the serial output for kernel panics, boot failures, or success markers. This harness is designed for headless CI environments where physical or ISO validation is not feasible.

## QEMU Configuration
- **Machine**: q35
- **Memory**: 2048M (default)
- **Net**: none (default)
- **Display**: none / nographic
- **Acceleration**: KVM (optional, used if available)

## Environment Variables
- `BOOT_RADICAL_QEMU_IMAGE`: Path to the boot image (default: `out/radical-boot.qcow2`).
- `BOOT_RADICAL_QEMU_TIMEOUT_SECONDS`: Duration to wait for boot (default: 30s).
- `BOOT_RADICAL_QEMU_ALLOW_MISSING_IMAGE`: If 1, skips tests instead of failing when image is absent.
- `BOOT_RADICAL_QEMU_SUCCESS_REGEX`: Optional regex to confirm boot completion in logs.

## Failure Markers Detected
- Kernel panic
- No bootable device / not a bootable disk
- failed to mount
- Entering emergency mode / dracut emergency shell

## Output Artifacts
- `BOOT-RADICAL/out/qemu-boot-smoke.log`: Full serial output from the guest.
- `BOOT-RADICAL/out/qemu-boot-smoke.json`: Structured results for automation.

## Validation Results
- Shell syntax check: **PASS**
- Headless execution (missing image mode): **PASS**
- JSON emission: **PASS**
