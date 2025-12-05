#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/build-config.sh"

ROOTFS_SIZE="6G"
DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
KERNEL_VERSION="${KERNEL_VERSION:-6.18}"
ROOTFS_IMG="root-${DISTRIBUTION}-${KERNEL_VERSION}.img"
ROOTDIR="rootdir"
VERSION="noble"
UBUNTU_VERSION="24.04.3"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

main() {
    log_info "Starting rootfs build"
    
    truncate -s "$ROOTFS_SIZE" "$ROOTFS_IMG" &&
    mkfs.ext4 "$ROOTFS_IMG" &&
    mkdir -p "$ROOTDIR" &&
    mount -o loop "$ROOTFS_IMG" "$ROOTDIR" &&
    
    wget "https://cdimage.ubuntu.com/ubuntu-base/releases/$VERSION/release/ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz" &&
    tar xzvf ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz -C "$ROOTDIR" &&
    
    mount --bind /dev "$ROOTDIR/dev" &&
    mount --bind /dev/pts "$ROOTDIR/dev/pts" &&
    mount --bind /proc "$ROOTDIR/proc" &&
    mount --bind /sys "$ROOTDIR/sys" &&
    
    echo "nameserver 1.1.1.1" | tee "$ROOTDIR/etc/resolv.conf" &&
    echo "xiaomi-raphael" | tee "$ROOTDIR/etc/hostname" &&
    echo -e "127.0.0.1 localhost\n127.0.1.1 xiaomi-raphael" | tee "$ROOTDIR/etc/hosts" &&
    
    # 跳过ARM64二进制格式支持设置
    
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
    export DEBIAN_FRONTEND=noninteractive
    
    chroot "$ROOTDIR" apt update &&
    chroot "$ROOTDIR" apt upgrade -y &&
    chroot "$ROOTDIR" apt install -y bash-completion sudo ssh nano initramfs-tools &&
    chroot "$ROOTDIR" apt install -y rmtfs protection-domain-mapper tqftpserv &&
    
    sed -i '/ConditionKernelVersion/d' "$ROOTDIR/lib/systemd/system/pd-mapper.service"
    
    cp linux-xiaomi-raphael_*.deb "$ROOTDIR/tmp/" 2>/dev/null || (echo "Failed to copy linux package" && exit 1) &&
    cp firmware-xiaomi-raphael_*.deb "$ROOTDIR/tmp/" 2>/dev/null || (echo "Failed to copy firmware package" && exit 1) &&
    cp alsa-xiaomi-raphael_*.deb "$ROOTDIR/tmp/" 2>/dev/null || (echo "Failed to copy alsa package" && exit 1) &&
    
    LINUX_PKG=$(chroot "$ROOTDIR" find /tmp -name "linux-xiaomi-raphael_*_arm64.deb" -type f | head -1) &&
    FIRMWARE_PKG=$(chroot "$ROOTDIR" find /tmp -name "firmware-xiaomi-raphael_*_arm64.deb" -type f | head -1) &&
    ALSA_PKG=$(chroot "$ROOTDIR" find /tmp -name "alsa-xiaomi-raphael_*_arm64.deb" -type f | head -1) &&
    
    [ -n "$LINUX_PKG" ] && chroot "$ROOTDIR" dpkg -i "$LINUX_PKG" || (echo "Linux kernel package not found" && exit 1) &&
    [ -n "$FIRMWARE_PKG" ] && chroot "$ROOTDIR" dpkg -i "$FIRMWARE_PKG" || (echo "Firmware package not found" && exit 1) &&
    [ -n "$ALSA_PKG" ] && chroot "$ROOTDIR" dpkg -i "$ALSA_PKG" || (echo "ALSA package not found" && exit 1) &&
    
    rm -f "$ROOTDIR/tmp/*-xiaomi-raphael*.deb"
    
    chroot "$ROOTDIR" update-initramfs -c -k all &&
    
    chroot "$ROOTDIR" apt install -y grub-efi-arm64 &&
    
    sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' "$ROOTDIR/etc/default/grub" &&
    sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT=""/' "$ROOTDIR/etc/default/grub" &&
    
    echo -e "PARTLABEL=userdata / ext4 errors=remount-ro,x-systemd.growfs 0 1\nPARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee "$ROOTDIR/etc/fstab" &&
    
    mkdir -p "$ROOTDIR/var/lib/gdm" &&
    touch "$ROOTDIR/var/lib/gdm/run-initial-setup" &&
    
    chroot "$ROOTDIR" apt clean &&
    
    # 跳过二进制格式注册清理
    
    # 检查boot目录内容
    log_info "Checking boot directory content..."
    if [ -d "$ROOTDIR/boot" ]; then
        echo "Boot directory content:";
        ls -la "$ROOTDIR/boot";
    fi
    
    # 列出安装的包
    log_info "Listing installed packages..."
    if [ -f "$ROOTDIR/var/lib/dpkg/status" ]; then
        chroot "$ROOTDIR" dpkg -l | head -20;
        echo "... showing first 20 packages, use 'chroot $ROOTDIR dpkg -l' to see all";
    fi
    
    umount "$ROOTDIR/sys" &&
    umount "$ROOTDIR/proc" &&
    umount "$ROOTDIR/dev/pts" &&
    umount "$ROOTDIR/dev" &&
    umount "$ROOTDIR" &&
    
    rm -d "$ROOTDIR" 2>/dev/null || true
    rm -f ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz 2>/dev/null || true
    
    7z a "${ROOTFS_IMG%.img}.7z" "$ROOTFS_IMG" &&
    
    log_success "Rootfs build completed"
    echo "Rootfs image: $ROOTFS_IMG"
    echo "Compressed rootfs: ${ROOTFS_IMG%.img}.7z"
}

[ "${BASH_SOURCE[0]}" = "$0" ] && main "$@"