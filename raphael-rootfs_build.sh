#!/bin/bash

# Rootfs build script for Xiaomi K20 Pro (Raphael)
# Designed specifically for GitHub Actions environment

# Source configuration file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/build-config.sh"

# ----------------------------- 
# Global Variables
# ----------------------------- 

# Rootfs configuration
ROOTFS_SIZE="6G"

# Set default values if environment variables are not provided
DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
KERNEL_VERSION="${KERNEL_VERSION:-6.18}"

ROOTFS_IMG="root-${DISTRIBUTION}-${KERNEL_VERSION}.img"
ROOTDIR="rootdir"

# Ubuntu version information
VERSION="noble"
UBUNTU_VERSION="24.04.3"

# ----------------------------- 
# Logging Functions
# ----------------------------- 
log_info() {
    echo -e "[INFO] $1"
}

log_success() {
    echo -e "[SUCCESS] $1"
}

# ----------------------------- 
# Main function
# ----------------------------- 
main() {
    log_info "Starting rootfs build for Xiaomi K20 Pro (Raphael)"
    
    # Step 1: Create rootfs image file
    log_info "Creating rootfs image file..."
    truncate -s "$ROOTFS_SIZE" "$ROOTFS_IMG"
    mkfs.ext4 "$ROOTFS_IMG"
    mkdir -p "$ROOTDIR"
    mount -o loop "$ROOTFS_IMG" "$ROOTDIR"
    
    # Step 2: Download base system
    log_info "Downloading Ubuntu base system..."
    wget "https://cdimage.ubuntu.com/ubuntu-base/releases/$VERSION/release/ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz"
    
    # Step 3: Extract base system
    log_info "Extracting base system..."
    tar xzvf ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz -C "$ROOTDIR"
    
    # Step 4: Mount necessary filesystems
    log_info "Mounting necessary filesystems..."
    mount --bind /dev "$ROOTDIR/dev"
    mount --bind /dev/pts "$ROOTDIR/dev/pts"
    mount --bind /proc "$ROOTDIR/proc"
    mount --bind /sys "$ROOTDIR/sys"
    
    # Step 5: Configure network and system settings
    log_info "Configuring network and system settings..."
    echo "nameserver 1.1.1.1" | tee "$ROOTDIR/etc/resolv.conf"
    echo "xiaomi-raphael" | tee "$ROOTDIR/etc/hostname"
    echo -e "127.0.0.1 localhost\n127.0.1.1 xiaomi-raphael" | tee "$ROOTDIR/etc/hosts"
    
    # Step 6: Install QEMU for emulation (if not on ARM64)
    if [ "$(uname -m)" != "aarch64" ]; then
        log_info "Running on $(uname -m), installing QEMU for ARM64 emulation..."
        wget "https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static"
        install -m755 qemu-aarch64-static "$ROOTDIR/"
        
        echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
        echo ':aarch64ld:M::\x7fELF\x02\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
    else
        log_info "Running on ARM64, using native execution - no QEMU needed"
        # 在ARM64上，确保binfmt支持已启用
        if [ ! -f /proc/sys/fs/binfmt_misc/aarch64 ]; then
            log_info "Enabling binfmt support for ARM64 native execution"
            echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff::' | tee /proc/sys/fs/binfmt_misc/register
        fi
    fi
    
    # Step 7: Configure environment variables for chroot
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
    export DEBIAN_FRONTEND=noninteractive
    
    # Step 8: Update package lists and upgrade
    log_info "Updating package lists and upgrading system..."
    chroot "$ROOTDIR" apt update
    chroot "$ROOTDIR" apt upgrade -y
    
    # Step 9: Install basic packages
    log_info "Installing basic packages..."
    chroot "$ROOTDIR" apt install -y bash-completion sudo ssh nano initramfs-tools
    
    # Step 10: Install device-specific packages
    log_info "Installing device-specific packages..."
    chroot "$ROOTDIR" apt install -y rmtfs protection-domain-mapper tqftpserv
    
    # Step 11: Remove check for laptop kernel version
    sed -i '/ConditionKernelVersion/d' "$ROOTDIR/lib/systemd/system/pd-mapper.service"
    
    # Step 12: Install custom kernel packages
    log_info "Installing custom kernel packages..."
    
    # List available kernel packages before copying
    log_info "Available kernel packages in current directory:"
    ls -la *.deb 2>/dev/null || echo "No .deb files found"
    
    # Copy kernel packages to chroot with proper path
    log_info "Copying kernel packages to chroot..."
    cp linux-xiaomi-raphael_*.deb "$ROOTDIR/tmp/" 2>/dev/null || (echo "❌ Failed to copy linux package" && exit 1)
    cp firmware-xiaomi-raphael_*.deb "$ROOTDIR/tmp/" 2>/dev/null || (echo "❌ Failed to copy firmware package" && exit 1)
    cp alsa-xiaomi-raphael_*.deb "$ROOTDIR/tmp/" 2>/dev/null || (echo "❌ Failed to copy alsa package" && exit 1)
    
    # Verify packages were copied successfully
    log_info "Verifying packages in chroot tmp directory:"
    chroot "$ROOTDIR" ls -la /tmp/ | grep -i xiaomi || echo "No kernel packages found in chroot"
    
    # Install kernel packages with proper path
    log_info "Installing kernel packages..."
    
    # Install specific arm64 packages using exact filenames
    log_info "Installing kernel packages with exact filenames..."
    
    # Find the exact arm64 package filenames in chroot
    LINUX_PKG=$(chroot "$ROOTDIR" find /tmp -name "linux-xiaomi-raphael_*_arm64.deb" -type f | head -1)
    FIRMWARE_PKG=$(chroot "$ROOTDIR" find /tmp -name "firmware-xiaomi-raphael_*_arm64.deb" -type f | head -1)
    ALSA_PKG=$(chroot "$ROOTDIR" find /tmp -name "alsa-xiaomi-raphael_*_arm64.deb" -type f | head -1)
    
    # Install packages with exact filenames
    if [ -n "$LINUX_PKG" ]; then
        chroot "$ROOTDIR" dpkg -i "$LINUX_PKG"
    else
        echo "❌ Linux kernel package not found"
        exit 1
    fi
    
    if [ -n "$FIRMWARE_PKG" ]; then
        chroot "$ROOTDIR" dpkg -i "$FIRMWARE_PKG"
    else
        echo "❌ Firmware package not found"
        exit 1
    fi
    
    if [ -n "$ALSA_PKG" ]; then
        chroot "$ROOTDIR" dpkg -i "$ALSA_PKG"
    else
        echo "❌ ALSA package not found"
        exit 1
    fi
    
    # Verify kernel installation
    log_info "Verifying kernel package installation..."
    chroot "$ROOTDIR" dpkg -l | grep xiaomi-raphael || echo "No xiaomi-raphael packages installed"
    
    # Clean up
    rm -f "$ROOTDIR/tmp/*-xiaomi-raphael*.deb"
    
    # Step 13: Verify kernel installation and update initramfs
    log_info "Verifying kernel installation..."
    chroot "$ROOTDIR" dpkg -l | grep -i linux || echo "No kernel packages found"
    
    log_info "Checking /boot directory structure..."
    chroot "$ROOTDIR" ls -la /boot/ || echo "Boot directory not accessible"
    
    log_info "Updating initramfs..."
    chroot "$ROOTDIR" update-initramfs -c -k all
    
    # Verify initramfs was created
    log_info "Verifying initramfs creation..."
    chroot "$ROOTDIR" ls -la /boot/ | grep -i initrd || echo "No initrd files found"
    chroot "$ROOTDIR" ls -la /boot/ | grep -i vmlinuz || echo "No vmlinuz files found"
    
    # Step 14: Install EFI bootloader
    log_info "Installing EFI bootloader..."
    chroot "$ROOTDIR" apt install -y grub-efi-arm64
    
    # Step 15: Configure GRUB
    sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' "$ROOTDIR/etc/default/grub"
    sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT=""/' "$ROOTDIR/etc/default/grub"
    
    # Step 16: Create fstab
    log_info "Creating fstab..."
    echo -e "PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1\nPARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee "$ROOTDIR/etc/fstab"
    
    # Step 17: Create GDM directories
    mkdir -p "$ROOTDIR/var/lib/gdm"
    touch "$ROOTDIR/var/lib/gdm/run-initial-setup"
    
    # Step 18: Clean up apt cache
    chroot "$ROOTDIR" apt clean
    
    # Step 19: Remove QEMU emulation if installed
    if [ "$(uname -m)" != "aarch64" ]; then
        log_info "Removing QEMU emulation..."
        echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64 2>/dev/null || true
        echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64ld 2>/dev/null || true
        rm -f "$ROOTDIR/qemu-aarch64-static" 2>/dev/null || true
        rm -f qemu-aarch64-static 2>/dev/null || true
    fi
    
    # Step 20: Unmount filesystems
    log_info "Unmounting filesystems..."
    umount "$ROOTDIR/sys"
    umount "$ROOTDIR/proc"
    umount "$ROOTDIR/dev/pts"
    umount "$ROOTDIR/dev"
    umount "$ROOTDIR"
    
    # Step 21: Clean up
    log_info "Cleaning up..."
    rm -d "$ROOTDIR" 2>/dev/null || true
    rm -f ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz 2>/dev/null || true
    
    # Step 22: Compress rootfs image
    log_info "Compressing rootfs image..."
    7z a "${ROOTFS_IMG%.img}.7z" "$ROOTFS_IMG"
    
    log_success "Rootfs build completed successfully!"
    log_info "Boot command line for legacy boot: root=PARTLABEL=linux"
    log_info "Rootfs image: $ROOTFS_IMG"
    log_info "Compressed rootfs: ${ROOTFS_IMG%.img}.7z"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi