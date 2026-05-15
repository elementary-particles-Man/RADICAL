use core::fmt::{self, Write};
use core::ptr::write_volatile;
use spin::Mutex;

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum FramebufferPixelFormat {
    Rgb,
    Bgr,
    Bitmask,
}

impl FramebufferPixelFormat {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Rgb => "RGB",
            Self::Bgr => "BGR",
            Self::Bitmask => "BITMASK",
        }
    }
}

#[derive(Copy, Clone, Debug)]
pub struct FramebufferInfo {
    pub base: u64,
    pub size: usize,
    pub width: usize,
    pub height: usize,
    pub stride: usize,
    pub pixel_format: FramebufferPixelFormat,
}

#[derive(Copy, Clone)]
pub struct BootDiagnostics {
    pub framebuffer: Option<FramebufferInfo>,
    pub memory_map_entries: usize,
    pub usable_regions: usize,
    pub reserved_regions: usize,
    pub mmio_regions: usize,
}

impl BootDiagnostics {
    pub const fn empty() -> Self {
        Self {
            framebuffer: None,
            memory_map_entries: 0,
            usable_regions: 0,
            reserved_regions: 0,
            mmio_regions: 0,
        }
    }
}

pub static BOOT_DIAGNOSTICS: Mutex<BootDiagnostics> = Mutex::new(BootDiagnostics::empty());
static CONSOLE: Mutex<Option<FramebufferConsole>> = Mutex::new(None);

struct FramebufferConsole {
    info: FramebufferInfo,
    cursor_x: usize,
    cursor_y: usize,
    fg: u32,
    bg: u32,
}

pub fn init(info: FramebufferInfo) {
    let mut console = FramebufferConsole {
        info,
        cursor_x: 1,
        cursor_y: 1,
        fg: 0x00f0_f0f0,
        bg: 0x0000_1020,
    };
    console.clear(0x0000_1020);
    *CONSOLE.lock() = Some(console);
}

pub fn set_boot_diagnostics(update: BootDiagnostics) {
    *BOOT_DIAGNOSTICS.lock() = update;
}

pub fn current_framebuffer() -> Option<FramebufferInfo> {
    BOOT_DIAGNOSTICS.lock().framebuffer
}

pub fn emit_boot_diagnostics_summary() {
    let diagnostics = *BOOT_DIAGNOSTICS.lock();
    println(format_args!(
        "BOOTINFO: MAP={} USABLE={} RESERVED={} MMIO={}",
        diagnostics.memory_map_entries,
        diagnostics.usable_regions,
        diagnostics.reserved_regions,
        diagnostics.mmio_regions
    ));
}

pub fn print(args: fmt::Arguments<'_>) {
    if let Some(console) = CONSOLE.lock().as_mut() {
        let _ = console.write_fmt(args);
    }
}

pub fn println(args: fmt::Arguments<'_>) {
    print(args);
    print(format_args!("\n"));
}

pub fn draw_panic_screen(args: fmt::Arguments<'_>) {
    if let Some(console) = CONSOLE.lock().as_mut() {
        console.fg = 0x00ff_ffff;
        console.bg = 0x0060_0000;
        console.clear(console.bg);
        console.cursor_x = 1;
        console.cursor_y = 1;
        let _ = console.write_str("RADICAL PANIC\n");
        let _ = console.write_str("-------------\n");
        let _ = console.write_fmt(args);
        let _ = console.write_str("\nSYSTEM HALTED. SEE SERIAL LOG IF AVAILABLE.\n");
    }
}

impl FramebufferConsole {
    fn clear(&mut self, color: u32) {
        for y in 0..self.info.height {
            for x in 0..self.info.width {
                self.put_pixel(x, y, color);
            }
        }
    }

    fn newline(&mut self) {
        self.cursor_x = 1;
        self.cursor_y += 1;
        let max_rows = self.info.height / 16;
        if self.cursor_y >= max_rows.saturating_sub(1) {
            self.cursor_y = 1;
            self.clear(self.bg);
        }
    }

    fn put_byte(&mut self, byte: u8) {
        match byte {
            b'\n' => self.newline(),
            b'\r' => self.cursor_x = 1,
            byte => {
                self.draw_char(self.cursor_x * 8, self.cursor_y * 16, byte);
                self.cursor_x += 1;
                if (self.cursor_x + 1) * 8 >= self.info.width {
                    self.newline();
                }
            }
        }
    }

    fn draw_char(&mut self, x: usize, y: usize, byte: u8) {
        let glyph = glyph8(byte);
        for (row, bits) in glyph.iter().enumerate() {
            for col in 0..8 {
                let color = if (bits >> (7 - col)) & 1 == 1 { self.fg } else { self.bg };
                self.put_pixel(x + col, y + row * 2, color);
                self.put_pixel(x + col, y + row * 2 + 1, color);
            }
        }
    }

    fn put_pixel(&self, x: usize, y: usize, color: u32) {
        if x >= self.info.width || y >= self.info.height {
            return;
        }
        let pixel_index = y.saturating_mul(self.info.stride).saturating_add(x);
        let byte_offset = pixel_index.saturating_mul(4);
        if byte_offset + 3 >= self.info.size {
            return;
        }

        let base = self.info.base as *mut u8;
        let (r, g, b) = (((color >> 16) & 0xff) as u8, ((color >> 8) & 0xff) as u8, (color & 0xff) as u8);
        unsafe {
            match self.info.pixel_format {
                FramebufferPixelFormat::Rgb => {
                    write_volatile(base.add(byte_offset), r);
                    write_volatile(base.add(byte_offset + 1), g);
                    write_volatile(base.add(byte_offset + 2), b);
                    write_volatile(base.add(byte_offset + 3), 0);
                }
                FramebufferPixelFormat::Bgr | FramebufferPixelFormat::Bitmask => {
                    write_volatile(base.add(byte_offset), b);
                    write_volatile(base.add(byte_offset + 1), g);
                    write_volatile(base.add(byte_offset + 2), r);
                    write_volatile(base.add(byte_offset + 3), 0);
                }
            }
        }
    }
}

impl Write for FramebufferConsole {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        for byte in s.bytes() {
            self.put_byte(byte);
        }
        Ok(())
    }
}

fn glyph8(byte: u8) -> [u8; 8] {
    match byte {
        b' ' => [0, 0, 0, 0, 0, 0, 0, 0],
        b'!' => [0x18, 0x18, 0x18, 0x18, 0x18, 0x00, 0x18, 0x00],
        b'-' => [0, 0, 0, 0x7e, 0, 0, 0, 0],
        b'_' => [0, 0, 0, 0, 0, 0, 0x7e, 0],
        b'=' => [0, 0, 0x7e, 0, 0x7e, 0, 0, 0],
        b':' => [0, 0x18, 0x18, 0, 0, 0x18, 0x18, 0],
        b'.' => [0, 0, 0, 0, 0, 0x18, 0x18, 0],
        b',' => [0, 0, 0, 0, 0, 0x18, 0x18, 0x30],
        b'/' => [0x02, 0x06, 0x0c, 0x18, 0x30, 0x60, 0x40, 0],
        b'(' => [0x0c, 0x18, 0x30, 0x30, 0x30, 0x18, 0x0c, 0],
        b')' => [0x30, 0x18, 0x0c, 0x0c, 0x0c, 0x18, 0x30, 0],
        b'[' => [0x3c, 0x30, 0x30, 0x30, 0x30, 0x30, 0x3c, 0],
        b']' => [0x3c, 0x0c, 0x0c, 0x0c, 0x0c, 0x0c, 0x3c, 0],
        b'0' => [0x3c, 0x66, 0x6e, 0x76, 0x66, 0x66, 0x3c, 0],
        b'1' => [0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7e, 0],
        b'2' => [0x3c, 0x66, 0x06, 0x1c, 0x30, 0x66, 0x7e, 0],
        b'3' => [0x3c, 0x66, 0x06, 0x1c, 0x06, 0x66, 0x3c, 0],
        b'4' => [0x0c, 0x1c, 0x3c, 0x6c, 0x7e, 0x0c, 0x0c, 0],
        b'5' => [0x7e, 0x60, 0x7c, 0x06, 0x06, 0x66, 0x3c, 0],
        b'6' => [0x1c, 0x30, 0x60, 0x7c, 0x66, 0x66, 0x3c, 0],
        b'7' => [0x7e, 0x66, 0x0c, 0x18, 0x18, 0x18, 0x18, 0],
        b'8' => [0x3c, 0x66, 0x66, 0x3c, 0x66, 0x66, 0x3c, 0],
        b'9' => [0x3c, 0x66, 0x66, 0x3e, 0x06, 0x0c, 0x38, 0],
        b'A' | b'a' => [0x18, 0x3c, 0x66, 0x66, 0x7e, 0x66, 0x66, 0],
        b'B' | b'b' => [0x7c, 0x66, 0x66, 0x7c, 0x66, 0x66, 0x7c, 0],
        b'C' | b'c' => [0x3c, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3c, 0],
        b'D' | b'd' => [0x78, 0x6c, 0x66, 0x66, 0x66, 0x6c, 0x78, 0],
        b'E' | b'e' => [0x7e, 0x60, 0x60, 0x78, 0x60, 0x60, 0x7e, 0],
        b'F' | b'f' => [0x7e, 0x60, 0x60, 0x78, 0x60, 0x60, 0x60, 0],
        b'G' | b'g' => [0x3c, 0x66, 0x60, 0x6e, 0x66, 0x66, 0x3c, 0],
        b'H' | b'h' => [0x66, 0x66, 0x66, 0x7e, 0x66, 0x66, 0x66, 0],
        b'I' | b'i' => [0x3c, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3c, 0],
        b'J' | b'j' => [0x1e, 0x0c, 0x0c, 0x0c, 0x6c, 0x6c, 0x38, 0],
        b'K' | b'k' => [0x66, 0x6c, 0x78, 0x70, 0x78, 0x6c, 0x66, 0],
        b'L' | b'l' => [0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x7e, 0],
        b'M' | b'm' => [0x63, 0x77, 0x7f, 0x6b, 0x63, 0x63, 0x63, 0],
        b'N' | b'n' => [0x66, 0x76, 0x7e, 0x7e, 0x6e, 0x66, 0x66, 0],
        b'O' | b'o' => [0x3c, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3c, 0],
        b'P' | b'p' => [0x7c, 0x66, 0x66, 0x7c, 0x60, 0x60, 0x60, 0],
        b'Q' | b'q' => [0x3c, 0x66, 0x66, 0x66, 0x6e, 0x3c, 0x0e, 0],
        b'R' | b'r' => [0x7c, 0x66, 0x66, 0x7c, 0x78, 0x6c, 0x66, 0],
        b'S' | b's' => [0x3c, 0x66, 0x60, 0x3c, 0x06, 0x66, 0x3c, 0],
        b'T' | b't' => [0x7e, 0x5a, 0x18, 0x18, 0x18, 0x18, 0x3c, 0],
        b'U' | b'u' => [0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3c, 0],
        b'V' | b'v' => [0x66, 0x66, 0x66, 0x66, 0x66, 0x3c, 0x18, 0],
        b'W' | b'w' => [0x63, 0x63, 0x63, 0x6b, 0x7f, 0x77, 0x63, 0],
        b'X' | b'x' => [0x66, 0x66, 0x3c, 0x18, 0x3c, 0x66, 0x66, 0],
        b'Y' | b'y' => [0x66, 0x66, 0x66, 0x3c, 0x18, 0x18, 0x3c, 0],
        b'Z' | b'z' => [0x7e, 0x06, 0x0c, 0x18, 0x30, 0x60, 0x7e, 0],
        _ => [0x7e, 0x42, 0x5a, 0x5a, 0x5a, 0x42, 0x7e, 0],
    }
}
