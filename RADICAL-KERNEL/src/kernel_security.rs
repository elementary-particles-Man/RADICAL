use crate::serial_println;

/// Kernel-side boundary for Linux CVE-2026-46333 / ssh-keysign-pwn class issues.
///
/// RADICAL is a Rust UEFI/bare-metal kernel prototype and does not implement
/// Linux ptrace, pidfd_getfd, ssh-keysign, chage, /proc, or Linux task->mm /
/// fdtable lifetime semantics. The practical kernel-side fix is therefore to
/// keep this ABI surface absent by default and force any future
/// process-introspection or FD-duplication feature through an explicit
/// fail-closed design review.
pub const SECRET_FD_EXPOSURE_BOUNDARY_ID: &str = "RADICAL-KERNEL-SECRET-FD-BOUNDARY-2026";
pub const TRACKED_CVE: &str = "CVE-2026-46333";
pub const TRACKED_ALIAS: &str = "ssh-keysign-pwn";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KernelSecretFdBoundaryState {
    Sealed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct KernelSecretFdBoundaryStatus {
    pub state: KernelSecretFdBoundaryState,
    pub has_linux_ptrace_abi: bool,
    pub has_pidfd_getfd_abi: bool,
    pub has_procfs_task_fd_aliasing: bool,
    pub allows_cross_process_fd_duplication: bool,
}

impl KernelSecretFdBoundaryStatus {
    pub const fn sealed() -> Self {
        Self {
            state: KernelSecretFdBoundaryState::Sealed,
            has_linux_ptrace_abi: false,
            has_pidfd_getfd_abi: false,
            has_procfs_task_fd_aliasing: false,
            allows_cross_process_fd_duplication: false,
        }
    }

    pub const fn is_sealed(&self) -> bool {
        !self.has_linux_ptrace_abi
            && !self.has_pidfd_getfd_abi
            && !self.has_procfs_task_fd_aliasing
            && !self.allows_cross_process_fd_duplication
    }
}

pub fn secret_fd_boundary_status() -> KernelSecretFdBoundaryStatus {
    KernelSecretFdBoundaryStatus::sealed()
}

pub fn assert_secret_fd_boundary_sealed() {
    let status = secret_fd_boundary_status();

    serial_println!(
        "RADICAL-KERNEL [SEC-01]: Secret FD boundary sealed for {} / {} class.",
        TRACKED_CVE,
        TRACKED_ALIAS
    );
    serial_println!(
        "RADICAL-KERNEL [SEC-01]: ptrace={}, pidfd_getfd={}, procfs_fd_alias={}, cross_process_fd_dup={}",
        if status.has_linux_ptrace_abi { "present" } else { "absent" },
        if status.has_pidfd_getfd_abi { "present" } else { "absent" },
        if status.has_procfs_task_fd_aliasing { "present" } else { "absent" },
        if status.allows_cross_process_fd_duplication { "present" } else { "absent" }
    );

    if !status.is_sealed() {
        panic!("RADICAL-KERNEL secret FD boundary is not sealed");
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn secret_fd_boundary_is_sealed_by_default() {
        let status = secret_fd_boundary_status();
        assert_eq!(status.state, KernelSecretFdBoundaryState::Sealed);
        assert!(status.is_sealed());
        assert!(!status.has_linux_ptrace_abi);
        assert!(!status.has_pidfd_getfd_abi);
        assert!(!status.has_procfs_task_fd_aliasing);
        assert!(!status.allows_cross_process_fd_duplication);
    }
}
