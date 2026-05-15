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
    --iso-application "RADICAL Installer" \
    --iso-publisher "RADICAL" \
    --iso-volume "RADICAL-INSTALLER" \
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

# RADICAL installer entrypoint: the live image is only a carrier.
if [ ! -x "${RELEASE_DIR}/install.sh" ]; then
    echo "[ERROR] Missing canonical RADICAL install backend: ${RELEASE_DIR}/install.sh"
    exit 1
fi
if [ ! -x "${RELEASE_DIR}/installer/radical-installer.sh" ]; then
    echo "[ERROR] Missing RADICAL installer wrapper: ${RELEASE_DIR}/installer/radical-installer.sh"
    exit 1
fi
install -D -m 0755 "${RELEASE_DIR}/install.sh" config/includes.chroot/opt/radical/release/install.sh
install -D -m 0755 "${RELEASE_DIR}/installer/radical-installer.sh" config/includes.chroot/usr/local/sbin/radical-installer
install -D -m 0644 "${RELEASE_DIR}/installer/radical-installer.service" config/includes.chroot/etc/systemd/system/radical-installer.service
install -D -m 0644 "${RELEASE_DIR}/installer/README.md" config/includes.chroot/opt/radical/release/installer/README.md
mkdir -p config/includes.chroot/etc/systemd/system/multi-user.target.wants
ln -s ../radical-installer.service config/includes.chroot/etc/systemd/system/multi-user.target.wants/radical-installer.service
ln -sfn /lib/systemd/system/multi-user.target config/includes.chroot/etc/systemd/system/default.target
ln -sfn /dev/null config/includes.chroot/etc/systemd/system/display-manager.service
ln -sfn /dev/null config/includes.chroot/etc/systemd/system/sddm.service

mkdir -p config/hooks/normal
cat > config/hooks/normal/0900-radical-installer.hook.chroot <<'HOOK_CHROOT'
#!/bin/sh
set -eu
systemctl set-default multi-user.target
systemctl enable radical-installer.service
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
        -e 's/Debian GNU\/Linux Live/RADICAL Installer/g' \
        -e 's/Debian Live/RADICAL Installer/g' \
        -e 's/Live system/RADICAL Installer/g' \
        -e 's/Start installer/RADICAL Installer/g' \
        -e 's/Graphical install/RADICAL Installer/g' \
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
