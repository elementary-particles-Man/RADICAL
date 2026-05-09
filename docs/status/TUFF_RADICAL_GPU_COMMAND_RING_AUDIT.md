# TUFF-RADICAL GPU Command-Ring Audit

## Audit Date

2026-05-09

## Scope

Audit fine-tuning opportunities for the TUFF-RADICAL GPU command-ring path. This is documentation only. The current kernel GPU path is a command-ring/MMIO proof of concept and framebuffer smoke path, not a real Vulkan implementation.

## Current State

- `TUFF-RADICAL-KERNEL/src/drivers/gpu.rs` provides `GpuDriver` framebuffer writes and `GpuCommandRing` volatile MMIO writes.
- `async_pcie_probe_and_init` detects display-class PCI devices, reads BAR0, performs a framebuffer draw, initializes VirtIO GPU if available, and submits a command-ring compute marker.
- `run_qemu.sh` uses `-vga std`, which is suitable for simple framebuffer smoke but not Vulkan validation.
- Roadmap text mentions SPIR-V/Vulkan runtime, but current code does not load SPIR-V, create Vulkan objects, or implement a Vulkan driver stack.

## Classification

| Area | Classification | Reason |
| --- | --- | --- |
| `GpuDriver::clear` / `draw_rect` | MMIO/framebuffer PoC | Direct volatile writes to assumed framebuffer geometry |
| `GpuCommandRing::submit_compute_command` | Command-ring PoC | Writes shader/data markers to MMIO, no queue ownership or device protocol validation |
| `async_gpu_compute_task` | GPU smoke task | Submits a marker after delay; no real Vulkan execution |
| VirtIO GPU init path | Device bring-up candidate | Useful for QEMU profile evolution, but separate from Vulkan |
| Vulkan roadmap items | Future design intent | Not implemented runtime behavior |

## Tuning Candidates

| Priority | Candidate | Practical next step |
| --- | --- | --- |
| P0 | MMIO safety boundary | Introduce an audited wrapper type around BAR/MMIO ranges before expanding command writes |
| P0 | Command-ring contract | Define ring layout, ownership, doorbell semantics, bounds, memory ordering, and error states in docs before code growth |
| P1 | QEMU GPU profiles | Split framebuffer smoke (`-vga std`) from VirtIO GPU smoke and any future host/Vulkan profile |
| P1 | Telemetry | Emit structured serial lines for BAR discovery, framebuffer draw, virtio init, ring submit, and rejected/unsupported GPU mode |
| P1 | CPU/fallback authority | Keep GPU tasks diagnostic/accelerator-only; never final authority for auth/session/watchdog |
| P2 | SPIR-V/Vulkan terminology cleanup | Use `Vulkan-compatible intent` only where appropriate; label current code as MMIO PoC |

## MMIO Safety Boundary Proposal

Before adding more GPU behavior, define:

- BAR range base, length, and provenance from PCI config.
- Volatile read/write helpers with checked offsets.
- Alignment and width rules for register writes.
- Memory ordering/fence policy around doorbell writes.
- Device-specific capability state before command submission.
- Failure mode for absent/unsupported GPU: no panic for normal QEMU profile.

## QEMU GPU Test Profiles

| Profile | QEMU shape | Expected result |
| --- | --- | --- |
| `std-vga-framebuffer` | Existing `-vga std` | Framebuffer smoke only |
| `virtio-gpu-smoke` | Future `-device virtio-gpu-pci` profile | Device detection and init telemetry |
| `no-gpu` | Explicit no display/GPU profile | CPU path and boot diagnostics continue |
| `host-vulkan-dev` | Future host-assisted developer profile | Not a baseline CI requirement |

## Non-Goals

- Do not call the current command-ring path a real Vulkan implementation.
- Do not modify kernel logic in this audit branch.
- Do not use GPU for lockd/auth/sessiond/watchdog final decisions.
- Do not remove CPU fallback or non-GPU boot path.
- Do not broaden boot scope beyond documented RADICAL testing.

## Recommended Next Steps

1. Add an MMIO safety design note and then wrap BAR writes behind checked helper APIs.
2. Define the command-ring ABI before adding more commands.
3. Add QEMU profile documentation for `std-vga-framebuffer`, `virtio-gpu-smoke`, and `no-gpu`.
4. Add serial telemetry for GPU probe and command-ring events.
5. Keep Vulkan terminology reserved for future user-space/runtime integration or a real driver design.

## Validation Notes

This is a documentation-only audit. Runtime validation should continue to run:

```text
cd TUFF-RADICAL-KERNEL && cargo build
```

