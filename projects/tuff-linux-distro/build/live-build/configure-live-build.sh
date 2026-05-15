#!/bin/bash
# TUFF-RADICAL: Configure Live-Build Workspace v4 (Hardened Sync)
set -euo pipefail

export PATH=/usr/local/sbin:/usr/sbin:/sbin:${PATH}

DISTRO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
REPO_DIR="$(cd "${DISTRO_DIR}/../.." && pwd)"
RELEASE_DIR="${REPO_DIR}/release"
PACKAGE_RENDER="${DISTRO_DIR}/build/common/render-package-list.sh"
PREPARE_OVERLAY="${DISTRO_DIR}/build/common/prepare-overlay.sh"
PRESEED_FILE="${DISTRO_DIR}/build/live-build/tuff-installer.preseed"
LB_WORK_DIR=${LB_WORK_DIR:-/var/tmp/tuff-live-build-work}

if [ ! -x "${PACKAGE_RENDER}" ]; then
    echo "[ERROR] Missing package renderer: ${PACKAGE_RENDER}"
    exit 1
fi

mkdir -p "$LB_WORK_DIR"
cd "$LB_WORK_DIR"

echo "--- TUFF Linux Distro: Configuring Live-Build ---"

# Clean start to prevent "Zombie Configs"
rm -rf config auto local
lb clean --purge >/dev/null 2>&1 || true

# 1. Base Configuration with Robust USB Params
lb config \
    --distribution trixie \
    --debian-installer live \
    --debian-installer-gui false \
    --archive-areas "main contrib non-free non-free-firmware" \
    --binary-images iso-hybrid \
    --bootloaders "syslinux,grub-efi" \
    --loadlin false \
    --iso-application "RADICAL Bring-up / Installer" \
    --iso-publisher "RADICAL" \
    --iso-volume "RADICAL-BRINGUP" \
    --memtest none \
    --linux-packages "linux-image" \
    --linux-flavours "amd64" \
    --apt-recommends true \
    --firmware-binary true \
    --firmware-chroot true \
    --bootappend-live "boot=live components radical.installer=1 systemd.unit=multi-user.target locales=ja_JP.UTF-8 keyboard-layouts=jp timezone=Asia/Tokyo console=tty0 pcie_aspm=off pci=noaer random.trust_cpu=on amd_pstate=active" \
    --bootappend-install "auto=true priority=critical locale=ja_JP.UTF-8 console=tty0"

# 2. Package List Generation using the Unified Renderer
mkdir -p config/package-lists
"${PACKAGE_RENDER}" tuff-base > config/package-lists/tuff-live.list.chroot

# 3. Overlay Sync (Atomic)
OVERLAY_STAGE="$("${PREPARE_OVERLAY}")"
mkdir -p config/includes.chroot
cp -a "${OVERLAY_STAGE}/." config/includes.chroot/

# RADICAL bring-up entrypoint: the live image boots diagnostics first.
required_release_paths=(
    install.sh
    MANIFEST.toml
    kernel
    rad-gpgpu
    TUFF-Xwin
    BOOT-RADICAL
    TUFF-KAIRO
    bringup
    installer
    uninstaller
)
for release_path in "${required_release_paths[@]}"; do
    if [ ! -e "${RELEASE_DIR}/${release_path}" ]; then
        echo "[ERROR] Missing canonical RADICAL release path: ${RELEASE_DIR}/${release_path}"
        exit 1
    fi
done
if [ ! -x "${RELEASE_DIR}/bringup/radical-bringup.sh" ]; then
    echo "[ERROR] Missing RADICAL bring-up wrapper: ${RELEASE_DIR}/bringup/radical-bringup.sh"
    exit 1
fi
if [ ! -x "${RELEASE_DIR}/installer/radical-installer.sh" ]; then
    echo "[ERROR] Missing RADICAL installer wrapper: ${RELEASE_DIR}/installer/radical-installer.sh"
    exit 1
fi

release_include_root=config/includes.chroot/opt/radical/release
mkdir -p "${release_include_root}"
install -D -m 0755 "${RELEASE_DIR}/install.sh" "${release_include_root}/install.sh"
install -D -m 0644 "${RELEASE_DIR}/MANIFEST.toml" "${release_include_root}/MANIFEST.toml"
for component in kernel rad-gpgpu TUFF-Xwin BOOT-RADICAL TUFF-KAIRO bringup installer uninstaller; do
    rm -rf "${release_include_root}/${component}"
    cp -a "${RELEASE_DIR}/${component}" "${release_include_root}/${component}"
done
find "${release_include_root}" -type d \( -name target -o -name out \) -prune -exec rm -rf {} +
find "${release_include_root}" -type f -name MANIFEST.generated.toml -delete

install -D -m 0755 "${RELEASE_DIR}/bringup/radical-bringup.sh" config/includes.chroot/usr/local/sbin/radical-bringup
install -D -m 0755 "${RELEASE_DIR}/installer/radical-installer.sh" config/includes.chroot/usr/local/sbin/radical-installer
install -D -m 0644 "${RELEASE_DIR}/bringup/radical-bringup.service" config/includes.chroot/etc/systemd/system/radical-bringup.service
install -D -m 0644 "${RELEASE_DIR}/installer/radical-installer.service" config/includes.chroot/etc/systemd/system/radical-installer.service
mkdir -p config/includes.chroot/etc/systemd/system/multi-user.target.wants
ln -s ../radical-bringup.service config/includes.chroot/etc/systemd/system/multi-user.target.wants/radical-bringup.service
rm -f config/includes.chroot/etc/systemd/system/multi-user.target.wants/radical-installer.service
ln -sfn /lib/systemd/system/multi-user.target config/includes.chroot/etc/systemd/system/default.target
ln -sfn /dev/null config/includes.chroot/etc/systemd/system/display-manager.service
ln -sfn /dev/null config/includes.chroot/etc/systemd/system/sddm.service

mkdir -p config/hooks/normal
cat > config/hooks/normal/0900-radical-installer.hook.chroot <<'HOOK_CHROOT'
#!/bin/sh
set -eu
systemctl set-default multi-user.target
systemctl enable radical-bringup.service
systemctl mask display-manager.service sddm.service || true
HOOK_CHROOT
chmod 0755 config/hooks/normal/0900-radical-installer.hook.chroot

cat > config/hooks/normal/0990-radical-boot-menu.hook.binary <<'HOOK_BINARY'
#!/bin/sh
set -eu

patch_file() {
    file="$1"
    [ -f "$file" ] || return 0
    sed -i \
        -e 's/Debian GNU\/Linux Live/RADICAL Bring-up / RADICAL Installer/g' \
        -e 's/Debian Live/RADICAL Bring-up / RADICAL Installer/g' \
        -e 's/Live system/RADICAL Bring-up / RADICAL Installer/g' \
        -e 's/Start installer/RADICAL Bring-up / RADICAL Installer/g' \
        -e 's/Graphical install/RADICAL Bring-up / RADICAL Installer/g' \
        "$file"
    if grep -q 'boot=live' "$file" && ! grep -q 'radical.installer=1' "$file"; then
        sed -i 's/boot=live/boot=live radical.installer=1 systemd.unit=multi-user.target/g' "$file"
    fi
}

find binary -type f \
    \( -path '*/isolinux/*.cfg' -o -path '*/syslinux/*.cfg' -o -path '*/boot/grub/*.cfg' -o -name 'grub.cfg' \) \
    -print | while IFS= read -r cfg; do
    patch_file "$cfg"
done
HOOK_BINARY
chmod 0755 config/hooks/normal/0990-radical-boot-menu.hook.binary

# DNS Fix for firmware-chroot
mkdir -p config/includes.chroot/etc
cp /etc/resolv.conf config/includes.chroot/etc/resolv.conf

# 4. Preseed Application
if [ -f "${PRESEED_FILE}" ]; then
    mkdir -p config/preseed
    install -m 0644 "${PRESEED_FILE}" config/preseed/tuff.preseed.binary
    install -m 0644 "${PRESEED_FILE}" config/preseed/tuff.preseed.chroot
fi

echo "--- Live-Build Configured successfully ---"
