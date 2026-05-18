use crate::drivers::io;
use crate::drivers::gpu::SCREEN_LOGGER;
use core::fmt;
use core::fmt::Write;
use spin::Mutex;

pub struct SerialPort {
    base: u16,
    initialized: bool,
}

impl SerialPort {
    pub const fn new(base: u16) -> Self {
        Self { base, initialized: false }
    }

    pub unsafe fn init(&mut self) {
        self.out_b(4, 0x1E); 
        self.out_b(0, 0xAE); 
        if self.in_b(0) != 0xAE {
            return; 
        }
        
        self.out_b(4, 0x0F); 
        self.out_b(1, 0x00);    
        self.out_b(3, 0x80);    
        self.out_b(0, 0x03);    
        self.out_b(1, 0x00);
        self.out_b(3, 0x03);    
        self.out_b(2, 0xC7);    
        
        self.initialized = true;
    }

    unsafe fn out_b(&self, offset: u16, data: u8) {
        io::outb(self.base + offset, data);
    }

    unsafe fn in_b(&self, offset: u16) -> u8 {
        io::inb(self.base + offset)
    }

    fn is_transmit_empty(&self) -> bool {
        unsafe { (self.in_b(5) & 0x20) != 0 }
    }

    pub fn write_byte(&self, byte: u8) {
        if !self.initialized { return; }
        while !self.is_transmit_empty() {}
        unsafe { self.out_b(0, byte); }
    }

    pub fn write_str(&self, s: &str) {
        for byte in s.bytes() {
            if byte == b'\n' {
                self.write_byte(b'\r');
            }
            self.write_byte(byte);
        }
    }
}

impl fmt::Write for SerialPort {
    fn write_str(&mut self, s: &str) -> fmt::Result {
        SerialPort::write_str(self, s);
        Ok(())
    }
}

pub static COM1: Mutex<SerialPort> = Mutex::new(SerialPort::new(0x3F8));

#[doc(hidden)]
pub fn _print(args: fmt::Arguments) {
    let _ = COM1.lock().write_fmt(args);
    let _ = SCREEN_LOGGER.lock().write_fmt(args);
}

#[macro_export]
macro_rules! serial_print {
    ($($arg:tt)*) => ($crate::drivers::serial::_print(format_args!($($arg)*)));
}

#[macro_export]
macro_rules! serial_println {
    () => ($crate::serial_print!("\n"));
    ($fmt:expr) => ($crate::serial_print!(concat!($fmt, "\n")));
    ($fmt:expr, $($arg:tt)*) => ($crate::serial_print!(
        concat!($fmt, "\n"), $($arg)*));
}
