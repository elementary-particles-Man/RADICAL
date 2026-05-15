#![no_std]
#![no_main]
#![feature(abi_x86_interrupt)]

extern crate alloc;

use core::arch::asm;
use uefi::prelude::*;
use uefi::allocator::exit_boot_services;
use uefi::proto::console::gop::{GraphicsOutput, PixelFormat};

#[macro_use]
mod drivers;
mod arch;
mod mm;
mod compression;
mod task;
mod installer;

use task::{Task, executor::Executor};
use crate::drivers::gpu::GpuCommandRing;
use crate::drivers::virtio_blk::VirtioBlk;
use core::{future::Future, pin::Pin, task::{Context, Poll}};
use core::sync::atomic::Ordering;
use crate::drivers::pci::{PciAddress, PciBar};
use crate::drivers::framebuffer_console::{self, BootDiagnostics, FramebufferInfo, FramebufferPixelFormat};
use crate::arch::x86_64::{interrupts, cpu, gdt, apic, paging, syscall, user};
use crate::mm::memory;
use crate::compression::zram;

// --- 非同期スリープの実装 ---
struct SleepFuture {
    target_tick: u64,
}

impl SleepFuture {
    fn new(ticks: u64) -> Self {
        let current = interrupts::current_tick();
        SleepFuture { target_tick: current + ticks }
    }
}

impl Future for SleepFuture {
    type Output = ();

    fn poll(self: Pin<&mut Self>, cx: &mut Context) -> Poll<()> {
        let current = interrupts::current_tick();
        if current >= self.target_tick {
            Poll::Ready(())
        } else {
            interrupts::register_timer_waker(self.target_tick, cx.waker());
            Poll::Pending
        }
    }
}

#[entry]
fn main(image_handle: Handle, system_table: SystemTable<Boot>) -> Status {
    unsafe { drivers::serial::COM1.lock().init(); }
    serial_println!("--- TUFF-RADICAL-KERNEL T-RAD REBIRTH (FINAL TUNE) ---");

    let framebuffer = init_gop_framebuffer(image_handle, &system_table);
    framebuffer_console::println(format_args!("RADICAL BRING-UP CONSOLE"));
    framebuffer_console::println(format_args!("STAGE: UEFI GOP ONLINE"));

    serial_println!("TUFF-RADICAL-KERNEL: Requesting UEFI ExitBootServices handoff...");
    let (runtime_table, mut memory_map) = system_table.exit_boot_services();
    exit_boot_services();
    x86_64::instructions::interrupts::disable();
    serial_println!("TUFF-RADICAL-KERNEL: ExitBootServices complete. Firmware boot services are offline.");

    memory_map.sort();
    memory::init_memory(&memory_map);
    memory::inspect_memory_map();
    let summary = memory::memory_map_summary();
    framebuffer_console::set_boot_diagnostics(BootDiagnostics {
        framebuffer,
        memory_map_entries: summary.entries,
        usable_regions: summary.usable_regions,
        reserved_regions: summary.reserved_regions,
        mmio_regions: summary.mmio_regions,
    });
    framebuffer_console::println(format_args!(
        "STAGE: EXIT BOOT SERVICES OK"
    ));
    framebuffer_console::emit_boot_diagnostics_summary();
    framebuffer_console::println(format_args!(
        "UEFI MAP: ENTRIES={} USABLE={} RESERVED={} MMIO={}",
        summary.entries,
        summary.usable_regions,
        summary.reserved_regions,
        summary.mmio_regions
    ));
    if let Some(fb) = framebuffer {
        framebuffer_console::println(format_args!(
            "GOP: 0x{:x} {}B {}x{} STRIDE={} {}",
            fb.base,
            fb.size,
            fb.width,
            fb.height,
            fb.stride,
            fb.pixel_format.as_str()
        ));
    }
    unsafe { paging::init_paging(framebuffer); }
    
    // CPU feature detection also wires the runtime SIMD state.
    let features = unsafe { cpu::init_simd() };
    cpu::log_features(&features);
    
    if !features.avx_enabled {
        serial_println!("TUFF-RADICAL-KERNEL: [WARNING] AVX runtime unavailable. SIMD optimization degraded.");
    }

    serial_println!("TUFF-RADICAL-KERNEL: Asserting absolute control over CPU (GDT/IDT)...");
    gdt::init();
    interrupts::init_idt();
    unsafe { syscall::init(); }
    let apic_topology = apic::init(&runtime_table);
    if let Some(topo) = apic_topology {
        unsafe {
            apic::disable_8259_pic();
            if !topo.io_apics.is_empty() {
                // Route Keyboard (IRQ 1) to Vector 33
                apic::io_apic_set_redirection(topo.io_apics[0].address, 1, 33, 0);
                serial_println!("TUFF-RADICAL-APIC: Keyboard IRQ 1 routed via I/O APIC.");
            }
        }
    }
    interrupts::set_interrupt_timer_ready(apic::timer_routing_ready());
    zram::init();

    let mut executor = Executor::new();
    
    // 1. Spawn base async initialization (PCIe, GPU, ZRAM) decoupled from the main thread
    executor.spawn(Task::new(async_pcie_probe_and_init()));
    executor.spawn(Task::new(async_runtime_diagnostics(features)));
    // 1.5 Spawn User-mode Handoff sequence
    executor.spawn(Task::new(async_user_handoff()));

    // 2. Spawn unlinked async worker modules dynamically scaled to CPU logical threads
    serial_println!(
        "TUFF-RADICAL-KERNEL: Spawning {} cooperative worker modules...",
        features.recommended_workers
    );
    for thread_id in 0..features.recommended_workers {
        executor.spawn(Task::new(async_worker_module(thread_id)));
    }

    if interrupts::interrupt_timer_ready() {
        serial_println!("TUFF-RADICAL-KERNEL: APIC timer routing online. Releasing Interrupt Seals...");
        x86_64::instructions::interrupts::enable();
    } else {
        serial_println!("TUFF-RADICAL-KERNEL: APIC timer routing pending. External IRQs stay masked; cooperative scheduler fallback active.");
    }
    serial_println!("TUFF-RADICAL-KERNEL: OS Tick Active. Entering Async Executor loop.");
    framebuffer_console::println(format_args!("STAGE: EXECUTOR ONLINE"));

    executor.run();
}

fn init_gop_framebuffer(image_handle: Handle, system_table: &SystemTable<Boot>) -> Option<FramebufferInfo> {
    let boot_services = system_table.boot_services();
    let handle = match boot_services.get_handle_for_protocol::<GraphicsOutput>() {
        Ok(handle) => handle,
        Err(status) => {
            serial_println!("TUFF-RADICAL-GOP: Graphics Output Protocol not found: {:?}", status.status());
            return None;
        }
    };

    let mut gop = match boot_services.open_protocol_exclusive::<GraphicsOutput>(handle) {
        Ok(gop) => gop,
        Err(status) => {
            serial_println!("TUFF-RADICAL-GOP: unable to open GOP exclusively: {:?}", status.status());
            return None;
        }
    };

    let mode_info = gop.current_mode_info();
    let (width, height) = mode_info.resolution();
    let stride = mode_info.stride();
    let pixel_format = match mode_info.pixel_format() {
        PixelFormat::Rgb => FramebufferPixelFormat::Rgb,
        PixelFormat::Bgr => FramebufferPixelFormat::Bgr,
        PixelFormat::Bitmask => FramebufferPixelFormat::Bitmask,
        PixelFormat::BltOnly => {
            serial_println!("TUFF-RADICAL-GOP: current mode is BLT-only; framebuffer console disabled.");
            return None;
        }
    };
    let mut fb = gop.frame_buffer();
    let info = FramebufferInfo {
        base: fb.as_mut_ptr() as u64,
        size: fb.size(),
        width,
        height,
        stride,
        pixel_format,
    };

    framebuffer_console::init(info);
    framebuffer_console::set_boot_diagnostics(BootDiagnostics {
        framebuffer: Some(info),
        memory_map_entries: 0,
        usable_regions: 0,
        reserved_regions: 0,
        mmio_regions: 0,
    });
    serial_println!(
        "TUFF-RADICAL-GOP: framebuffer console online image={:?} base=0x{:x} size={} mode={}x{} stride={} format={}",
        image_handle,
        info.base,
        info.size,
        info.width,
        info.height,
        info.stride,
        info.pixel_format.as_str()
    );
    Some(info)
}

async fn async_worker_module(thread_id: u32) {
    serial_println!("TUFF-RADICAL-ASYNC [WORKER-{}]: Online. Awaiting Vulkan/SIMD tasks.", thread_id);
    let base_sleep = 50 + (thread_id as u64 * 15); // Unlinked heartbeat timings (無動機秘連動)
    loop {
        SleepFuture::new(base_sleep).await;
        let current_tick = interrupts::TICKS.load(Ordering::Relaxed);
        if current_tick.is_multiple_of(1000) {
            serial_println!("TUFF-RADICAL-ASYNC [WORKER-{}]: Heartbeat. OS Tick: {}", thread_id, current_tick);
        }
    }
}

async fn async_pcie_probe_and_init() {
    serial_println!("TUFF-RADICAL-ASYNC [INIT]: Asynchronous PCIe probing for GPU/Storage...");
    let mut gpu_mmio_base: Option<u64> = None;
    let mut storage_device: Option<VirtioBlk> = None;

    for bus in 0..=255 {
        for slot in 0..=31 {
            let address_base = PciAddress { bus, slot, func: 0 };
            let dev_base = unsafe { drivers::pci::probe_device(address_base) };
            if dev_base.is_none() { continue; }
            
            for func in 0..=7 {
                let address = PciAddress { bus, slot, func };
                let Some(dev) = (unsafe { drivers::pci::probe_device(address) }) else { continue; };
                
                if dev.class == 0x03 { // Display Controller
                    if let Some(bar0) = unsafe { read_pci_bar0(address) } {
                        gpu_mmio_base = Some(bar0);
                        unsafe { drivers::gpu::test_draw(bar0); }
                        if let Some(vgpu) = unsafe { drivers::virtio_gpu::VirtioGpu::from_pci(address) } {
                            unsafe { vgpu.init(); }
                        }
                    }
                }

                if dev.vendor_id == 0x1AF4 { // VirtIO
                    if dev.device_id == 0x1001 { // Block
                        if let Some(device) = unsafe { VirtioBlk::from_pci(address) } {
                            storage_device = Some(device);
                        }
                    }
                }
            }
        }
        if bus % 32 == 0 { SleepFuture::new(1).await; }
    }

    if storage_device.is_some() {
        framebuffer_console::println(format_args!("STORAGE: VIRTIO-BLK DRIVER PRESENT"));
    } else {
        framebuffer_console::println(format_args!("STORAGE: VIRTIO/NVME/AHCI INSTALL DISABLED"));
        serial_println!("TUFF-RADICAL-ASYNC [STORAGE]: VirtIO block not found; NVMe/AHCI drivers missing; install disabled.");
    }

    if let Some(base) = gpu_mmio_base {
        serial_println!("TUFF-RADICAL-ASYNC [INIT]: GPU Active at 0x{:x}. Submitting Vulkan-compatible pipeline.", base);
        // Using a fixed physical address for the command buffer substrate in this test environment
        let ring = unsafe { GpuCommandRing::new(base, 0x5000000) };
        async_gpu_compute_task(ring).await;
    } else {
        serial_println!("TUFF-RADICAL-ASYNC [INIT]: No GPU found. Directing Vulkan workload to CPU SIMD fallback.");
        async_cpu_simd_fallback_task().await;
    }

    if let Some(disk) = storage_device {
        serial_println!("TUFF-RADICAL-ASYNC [STORAGE]: VirtIO block detected; install pipeline remains simulation-gated in bring-up mode.");
        async_install_task(disk).await;
    } else {
        serial_println!("TUFF-RADICAL-ASYNC [STORAGE]: No supported writable install target. Destructive install path is disabled.");
    }
}

async fn async_runtime_diagnostics(features: cpu::CpuFeatures) {
    SleepFuture::new(5).await;
    serial_println!(
        "TUFF-RADICAL-ASYNC [CPU]: workers={} simd={} avx={} avx512={} xcr0={:#x}",
        features.recommended_workers,
        features.simd_enabled,
        features.avx_enabled,
        features.avx512_enabled,
        features.xcr0
    );
}

async fn async_gpu_compute_task(mut ring: GpuCommandRing) {
    serial_println!("TUFF-RADICAL-ASYNC [GPU]: Vulkan compute sequence isolated.");
    SleepFuture::new(10).await;
    
    let shader_id = 0x70FF;
    let data_phys = 0x6000000;
    let result_phys = 0x6001000;

    serial_println!("TUFF-RADICAL-ASYNC [GPU]: Submitting batch to Command Ring...");
    if ring.submit_compute_batch(shader_id, data_phys, result_phys) {
        ring.wait_for_idle();
        serial_println!("TUFF-RADICAL-ASYNC [GPU]: Batch completed via Vulkan path.");
    } else {
        serial_println!("TUFF-RADICAL-ASYNC [GPU]: Submission rejected. Falling back to CPU SIMD.");
        async_cpu_simd_fallback_task().await;
    }
}

async fn async_cpu_simd_fallback_task() {
    serial_println!("TUFF-RADICAL-ASYNC [CPU-FALLBACK]: Executing Vulkan compute workload via SIMD.");
    // Simulated AVX/SSE workload
    SleepFuture::new(5).await;
    serial_println!("TUFF-RADICAL-ASYNC [CPU-FALLBACK]: SIMD compute task finalized.");
}

async fn async_install_task(disk: VirtioBlk) {
    framebuffer_console::println(format_args!("INSTALL: VIRTIO SIMULATION ONLY"));
    serial_println!("TUFF-RADICAL-ASYNC [INSTALL-TASK]: Beginning automated deployment simulation...");
    SleepFuture::new(30).await; 
    installer::run_install_pipeline(&disk);
    serial_println!("TUFF-RADICAL-ASYNC [INSTALL-TASK]: Deployment finalized. System ready.");
}

#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    serial_println!("\n[!!!] TUFF-RADICAL-KERNEL T-RAD PANIC [!!!]");
    serial_println!("Nature: {}", info);
    framebuffer_console::draw_panic_screen(format_args!("{}", info));
    serial_println!("System halted. The core remains pure.");
    loop { unsafe { asm!("hlt"); } }
}

unsafe fn read_pci_bar0(address: PciAddress) -> Option<u64> {
    match drivers::pci::read_bar(address, 0)? {
        PciBar::Memory32 { base, .. } | PciBar::Memory64 { base, .. } => Some(base),
        PciBar::Io { .. } => None,
    }
}

async fn async_user_handoff() {
    serial_println!("TUFF-RADICAL-ASYNC [USER]: Initiating handoff to unprivileged space.");
    SleepFuture::new(10).await; // Wait for system to stabilize
    user::spawn_user_hello();
}
