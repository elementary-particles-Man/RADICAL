use crate::serial_println;
use spin::Mutex;
use core::fmt;

#[derive(Clone, Copy)]
pub struct GopInfo {
    pub fb_base: u64,
    pub fb_size: u64,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
}

pub struct ScreenLogger {
    info: Option<GopInfo>,
    cursor_x: u32,
    cursor_y: u32,
}

impl ScreenLogger {
    pub const fn new() -> Self {
        Self {
            info: None,
            cursor_x: 0,
            cursor_y: 0,
        }
    }

    pub fn init(&mut self, info: GopInfo) {
        self.info = Some(info);
        self.cursor_x = 0;
        self.cursor_y = 0;
        unsafe { self.clear(0x001D212F); } // Deep Radical Blue
    }

    pub unsafe fn clear(&self, color: u32) {
        let Some(info) = self.info else { return; };
        let ptr = info.fb_base as *mut u32;
        for i in 0..(info.stride * info.height) {
            ptr.add(i as usize).write_volatile(color);
        }
    }

    pub fn put_char(&mut self, c: char, color: u32) {
        let Some(info) = self.info else { return; };
        
        if c == '\n' {
            self.newline();
            return;
        }

        if self.cursor_x + 8 > info.width {
            self.newline();
        }
        if self.cursor_y + 16 > info.height {
            // Simple scroll: just clear and reset for now
            unsafe { self.clear(0x001D212F); }
            self.cursor_y = 0;
        }

        draw_char(info, self.cursor_x, self.cursor_y, c, color);
        self.cursor_x += 8;
    }

    fn newline(&mut self) {
        self.cursor_x = 0;
        self.cursor_y += 16;
    }
}

impl fmt::Write for ScreenLogger {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        for c in s.chars() {
            self.put_char(c, 0x00FFFFFF); // White text
        }
        Ok(())
    }
}

pub static SCREEN_LOGGER: Mutex<ScreenLogger> = Mutex::new(ScreenLogger::new());

fn draw_char(info: GopInfo, x: u32, y: u32, c: char, color: u32) {
    let glyph = get_glyph(c);
    let ptr = info.fb_base as *mut u32;
    for dy in 0..16 {
        let row = glyph[dy as usize];
        for dx in 0..8 {
            if (row & (1 << (7 - dx))) != 0 {
                let px = x + dx;
                let py = y + dy;
                if px < info.width && py < info.height {
                    unsafe {
                        ptr.add((py * info.stride + px) as usize).write_volatile(color);
                    }
                }
            }
        }
    }
}

// Minimal 8x16 font (built-in for visibility)
fn get_glyph(c: char) -> [u8; 16] {
    // Very basic font representation for a few critical characters
    // Default to a block if unknown
    let mut glyph = [0u8; 16];
    let idx = c as usize;
    if (32..127).contains(&idx) {
        // Simple dot pattern for demonstration if no real font data
        // In a real implementation, we'd include a proper font header.
        // For now, let's just draw some recognizable patterns for debugging.
        match c {
            'A'..='Z' | 'a'..='z' => { glyph[4] = 0x3C; glyph[5] = 0x42; glyph[6] = 0x42; glyph[7] = 0x7E; glyph[8] = 0x42; glyph[9] = 0x42; }
            '0'..='9' => { glyph[4] = 0x3C; glyph[5] = 0x46; glyph[6] = 0x4A; glyph[7] = 0x52; glyph[8] = 0x62; glyph[9] = 0x3C; }
            '-' => { glyph[8] = 0x7E; }
            ':' => { glyph[6] = 0x18; glyph[10] = 0x18; }
            '.' => { glyph[12] = 0x18; }
            '[' => { glyph[4] = 0x3C; glyph[5] = 0x20; glyph[6] = 0x20; glyph[7] = 0x20; glyph[8] = 0x20; glyph[9] = 0x3C; }
            ']' => { glyph[4] = 0x3C; glyph[5] = 0x04; glyph[6] = 0x04; glyph[7] = 0x04; glyph[8] = 0x04; glyph[9] = 0x3C; }
            _ => { glyph[4] = 0xAA; glyph[5] = 0x55; glyph[6] = 0xAA; glyph[7] = 0x55; }
        }
    }
    glyph
}

pub struct GpuCommandRing {
    mmio_base: u64,
    command_buffer_phys: u64,
    tail: u32,
}

#[repr(C, align(64))]
pub struct GpuCommand {
    pub opcode: u32,
    pub shader_id: u32,
    pub data_phys: u64,
    pub result_phys: u64,
    pub flags: u64,
    pub reserved: [u64; 4],
}

impl GpuCommandRing {
    pub unsafe fn new(mmio_base: u64, command_buffer_phys: u64) -> Self {
        serial_println!("TUFF-RADICAL-GPU: Command Ring mapped at MMIO 0x{:x}", mmio_base);
        
        // Reset device command state
        (mmio_base as *mut u32).write_volatile(0); // Status reset
        
        Self { 
            mmio_base, 
            command_buffer_phys,
            tail: 0,
        }
    }

    pub fn submit_compute_batch(&mut self, shader_id: u32, data_ptr: u64, result_ptr: u64) -> bool {
        unsafe {
            let cmd_ptr = (self.command_buffer_phys + (self.tail as u64 * 64)) as *mut GpuCommand;
            cmd_ptr.write_volatile(GpuCommand {
                opcode: 0x1, // COMPUTE
                shader_id,
                data_phys: data_ptr,
                result_phys: result_ptr,
                flags: 0,
                reserved: [0; 4],
            });
            self.tail = (self.tail + 1) % 1024;
            let doorbell = (self.mmio_base + 0x10) as *mut u32;
            doorbell.write_volatile(self.tail);
            true
        }
    }

    pub fn wait_for_idle(&self) {
        unsafe {
            let status_reg = self.mmio_base as *mut u32;
            let mut timeout = 1000000;
            while status_reg.read_volatile() != 0 && timeout > 0 {
                timeout -= 1;
                core::hint::spin_loop();
            }
        }
    }
}
