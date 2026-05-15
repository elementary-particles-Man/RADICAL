#![forbid(unsafe_code)]

//! RADICAL GPGPU substrate.
//!
//! The package is named `rad-gpgpu`; the Rust library keeps the
//! `tuff_gpgpu` crate name for source compatibility with existing users.

/// Returns the stable RADICAL GPGPU package identifier.
pub fn package_name() -> &'static str {
    "rad-gpgpu"
}

/// Returns the exported Rust library crate name.
pub fn rust_library_name() -> &'static str {
    "tuff_gpgpu"
}
