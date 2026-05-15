use uefi::table::boot::{MemoryType, PAGE_SIZE};
use crate::arch::x86_64::registers::{Cr3, EFER};
use crate::drivers::framebuffer_console::{self, FramebufferInfo};
use crate::mm::memory;

/// ページテーブルのエントリ属性
const PRESENT: u64 = 1 << 0;
const WRITABLE: u64 = 1 << 1;
pub const USER_ACCESSIBLE: u64 = 1 << 2;
#[allow(dead_code)]
const HUGE_PAGE: u64 = 1 << 7;
const NO_EXECUTE: u64 = 1 << 63;
const CACHE_DISABLE: u64 = 1 << 4;

#[allow(dead_code)]
pub const NORMAL_MEMORY: u64 = PRESENT | WRITABLE | NO_EXECUTE;
pub const CODE_MEMORY: u64 = PRESENT; // NX=0
pub const READ_ONLY_MEMORY: u64 = PRESENT | NO_EXECUTE;
pub const MMIO_MEMORY: u64 = PRESENT | WRITABLE | NO_EXECUTE | CACHE_DISABLE;

pub unsafe fn init_paging(framebuffer: Option<FramebufferInfo>) {
    serial_println!("TUFF-RADICAL-COMMANDER [PAG-01]: Establishing memory-map-scoped page protection...");

    enable_nx_bit();

    let pml4_phys = memory::allocate_page().expect("Failed to allocate PML4");
    let pml4 = pml4_phys as *mut u64;
    for i in 0..512 { *pml4.add(i) = 0; }

    let mut mapped_pages = 0u64;
    let mut writable_pages = 0u64;
    let mut mmio_pages = 0u64;
    let mut skipped_pages = 0u64;
    let mut skipped_regions = 0u64;

    for desc in memory::boot_memory_map() {
        if desc.page_count == 0 {
            continue;
        }

        let Some(flags) = paging_flags_for_memory_type(desc.ty) else {
            skipped_pages += desc.page_count;
            skipped_regions += 1;
            serial_println!(
                "=> Paging: skipped {:?} region at 0x{:x}, pages={} (not identity-mapped)",
                desc.ty,
                desc.phys_start,
                desc.page_count
            );
            continue;
        };

        map_range(pml4, desc.phys_start, desc.phys_start, desc.page_count, flags);
        mapped_pages += desc.page_count;
        if (flags & WRITABLE) != 0 {
            writable_pages += desc.page_count;
        }
        if (flags & MMIO_MEMORY) == MMIO_MEMORY {
            mmio_pages += desc.page_count;
        }
    }

    if let Some(fb) = framebuffer {
        let fb_pages = ((fb.size as u64) + PAGE_SIZE as u64 - 1) / PAGE_SIZE as u64;
        map_range(pml4, fb.base, fb.base, fb_pages, MMIO_MEMORY);
        mapped_pages += fb_pages;
        writable_pages += fb_pages;
        mmio_pages += fb_pages;
        serial_println!(
            "=> Paging: GOP framebuffer mapped UC/NX at 0x{:x}, size={} bytes, pages={}",
            fb.base,
            fb.size,
            fb_pages
        );
    }

    Cr3::write(pml4_phys);
    serial_println!(
        "=> Paging: mapped UEFI-described regions only (mapped_pages={} writable={} mmio={} skipped_pages={} skipped_regions={}); blind 4GB identity map disabled.",
        mapped_pages,
        writable_pages,
        mmio_pages,
        skipped_pages,
        skipped_regions
    );
    framebuffer_console::println(format_args!(
        "PAGING: mapped={} writable={} mmio={} skipped={} regions={}",
        mapped_pages,
        writable_pages,
        mmio_pages,
        skipped_pages,
        skipped_regions
    ));
}

fn paging_flags_for_memory_type(memory_type: MemoryType) -> Option<u64> {
    match memory_type {
        MemoryType::LOADER_CODE => Some(CODE_MEMORY),
        MemoryType::LOADER_DATA
        | MemoryType::BOOT_SERVICES_CODE
        | MemoryType::BOOT_SERVICES_DATA
        | MemoryType::RUNTIME_SERVICES_CODE
        | MemoryType::RUNTIME_SERVICES_DATA
        | MemoryType::CONVENTIONAL => Some(NORMAL_MEMORY),
        MemoryType::ACPI_RECLAIM | MemoryType::ACPI_NON_VOLATILE => Some(READ_ONLY_MEMORY),
        MemoryType::MMIO | MemoryType::MMIO_PORT_SPACE => Some(MMIO_MEMORY),
        MemoryType::RESERVED | MemoryType::UNUSABLE => None,
        _ => Some(READ_ONLY_MEMORY),
    }
}

unsafe fn enable_nx_bit() {
    let mut efer = EFER.read();
    efer |= 1 << 11;
    EFER.write(efer);
}

unsafe fn map_range(pml4: *mut u64, virt: u64, phys: u64, count: u64, flags: u64) {
    for i in 0..count {
        map_page(pml4, virt + (i * PAGE_SIZE as u64), phys + (i * PAGE_SIZE as u64), flags);
    }
}

unsafe fn map_page(pml4: *mut u64, virt: u64, phys: u64, flags: u64) {
    let pml4_idx = (virt >> 39) & 0x1FF;
    let pdpt_idx = (virt >> 30) & 0x1FF;
    let pd_idx = (virt >> 21) & 0x1FF;
    let pt_idx = (virt >> 12) & 0x1FF;

    let pdpt = get_or_create_table(pml4, pml4_idx);
    let pd = get_or_create_table(pdpt, pdpt_idx);
    let pt = get_or_create_table(pd, pd_idx);

    *pt.add(pt_idx as usize) = (phys & !0xFFF) | flags;
}

unsafe fn get_or_create_table(parent: *mut u64, index: u64) -> *mut u64 {
    let entry = *parent.add(index as usize);
    if (entry & PRESENT) != 0 && (entry & HUGE_PAGE) == 0 {
        *parent.add(index as usize) |= USER_ACCESSIBLE;
        (entry & !0xFFF & !NO_EXECUTE) as *mut u64
    } else {
        let new_table_phys = memory::allocate_page().expect("Failed to allocate table");
        let new_table = new_table_phys as *mut u64;
        for i in 0..512 { *new_table.add(i) = 0; }
        *parent.add(index as usize) = new_table_phys | PRESENT | WRITABLE | USER_ACCESSIBLE;
        new_table
    }
}

pub unsafe fn map_user_code(virt: u64, phys: u64) {
    let pml4 = Cr3::read() as *mut u64;
    map_page(pml4, virt, phys, PRESENT | WRITABLE | USER_ACCESSIBLE);
}

pub unsafe fn map_user_data(virt: u64, phys: u64) {
    let pml4 = Cr3::read() as *mut u64;
    map_page(pml4, virt, phys, PRESENT | WRITABLE | USER_ACCESSIBLE | NO_EXECUTE);
}
