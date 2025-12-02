#!/bin/bash

# Modular rootfs build script for Xiaomi K20 Pro (Raphael)
# Enhanced with Armbian support, skip kernel build option, and better error handling

# Source configuration file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/build-config.sh"

# ----------------------------- 
# Global Variables
# ----------------------------- 

# Paths
WORKING_DIR=$(pwd)

# Rootfs configuration
ROOTFS_SIZE="6G"
ROOTFS_IMG="rootfs.img"
ROOTDIR="rootdir"

# Default cache settings
USE_CACHE="true"

# Kernel build settings
SKIP_KERNEL_BUILD="true"

# Ubuntu desktop environments
UBUNTU_DESKTOP_ENVS=("ubuntu-desktop" "kubuntu-desktop" "xubuntu-desktop" "lubuntu-desktop" "mate-desktop" "budgie-desktop")

# Default desktop environment for Ubuntu
DESKTOP_ENV=""

# Distribution settings (hardcoded as per requirements)
DISTRO="ubuntu"
VERSION="noble"
KERNEL_VERSION="6.18"

# ----------------------------- 
# Logging Functions
# ----------------------------- 
log_info() {
    echo -e "[INFO] $1"
}

log_success() {
    echo -e "[SUCCESS] $1"
}

log_warning() {
    echo -e "[WARNING] $1"
}

log_error() {
    echo -e "[ERROR] $1"
}

# Error handling function
handle_error() {
    local message=$1
    local exit_code=${2:-1}
    log_error "$message"
    cleanup
    exit $exit_code
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Unmount filesystems if mounted
    if mountpoint -q "$ROOTDIR/sys" 2>/dev/null; then
        umount "$ROOTDIR/sys" 2>/dev/null || true
    fi
    if mountpoint -q "$ROOTDIR/proc" 2>/dev/null; then
        umount "$ROOTDIR/proc" 2>/dev/null || true
    fi
    if mountpoint -q "$ROOTDIR/dev/pts" 2>/dev/null; then
        umount "$ROOTDIR/dev/pts" 2>/dev/null || true
    fi
    if mountpoint -q "$ROOTDIR/dev" 2>/dev/null; then
        umount "$ROOTDIR/dev" 2>/dev/null || true
    fi
    if mountpoint -q "$ROOTDIR" 2>/dev/null; then
        umount "$ROOTDIR" 2>/dev/null || true
    fi
    
    # Remove directories
    rm -rf "$ROOTDIR" 2>/dev/null || true
    
    # Cleanup QEMU if installed
    if [ -f "qemu-aarch64-static" ]; then
        rm -f "qemu-aarch64-static" 2>/dev/null || true
    fi
    
    # Cache directory is not cleaned up here to preserve cached files
}

# Parse command line arguments
parse_arguments() {
    log_info "Parsing command-line arguments..."
    
    # Set default values
    USE_CACHE="true"
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cache)
                USE_CACHE="true"
                shift 1
                ;;
            --no-cache)
                USE_CACHE="false"
                shift 1
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_success "Arguments parsed successfully"
    log_info "Cache enabled: $USE_CACHE"
}

# Show help information
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Build rootfs for Xiaomi K20 Pro (Raphael)

OPTIONS:
    --cache                  Enable cache for base system download
    --no-cache               Disable cache
    -h, --help               Show this help message

EXAMPLE:
    $0 --cache
EOF
}

# Validate distribution and version
validate_configuration() {
    echo "🔍 Validating configuration..."
    
    # Check root privileges
    if [ "$(id -u)" -ne 0 ]; then
        handle_error "RootFS can only be built as root"
    fi
    
    # Validate distribution and version
    if ! validate_distribution "$DISTRO" "$VERSION"; then
        handle_error "Distribution validation failed"
    fi
    
    # Validate desktop environment for Ubuntu
    if [ "$DISTRO" = "ubuntu" ] && [[ ! " ${UBUNTU_DESKTOP_ENVS[@]} " =~ " ${DESKTOP_ENV} " ]]; then
        echo "⚠️  Desktop environment '$DESKTOP_ENV' may not be fully supported"
    fi
}

# Create rootfs image
create_rootfs_image() {
    echo "📦 Creating rootfs image..."
    
    # Remove existing files
    rm -f "$ROOTFS_IMG" 2>/dev/null || true
    rm -rf "$ROOTDIR" 2>/dev/null || true
    
    # Create rootfs image
    truncate -s "$ROOTFS_SIZE" "$ROOTFS_IMG" || handle_error "Failed to create rootfs image"
    mkfs.ext4 "$ROOTFS_IMG" || handle_error "Failed to format rootfs image"
    mkdir -p "$ROOTDIR" || handle_error "Failed to create rootdir"
    mount -o loop "$ROOTFS_IMG" "$ROOTDIR" || handle_error "Failed to mount rootfs image"
    
    echo "✅ Rootfs image created successfully"
}

# Download and extract base system
download_base_system() {
    echo "📥 Downloading base system for $DISTRO $VERSION..."
    
    # Get download URL based on distribution
    case "$DISTRO" in
        "ubuntu")
            BASE_URL=$(get_ubuntu_url "$VERSION")
            ;;
        "armbian")
            BASE_URL=$(get_armbian_url "$VERSION")
            ;;
    esac
    
    if [ -z "$BASE_URL" ]; then
        handle_error "Failed to get download URL for $DISTRO $VERSION"
    fi
    
    # Create cache directory
    CACHE_BASE_DIR="${CACHE_DIR}/rootfs"
    mkdir -p "$CACHE_BASE_DIR"
    
    # Download base system with cache support
    local filename=$(basename "$BASE_URL")
    local cache_file="${CACHE_BASE_DIR}/${filename}"
    
    if [ "$USE_CACHE" = "true" ] && [ -f "$cache_file" ]; then
        echo "✅ Using cached base system: $cache_file"
    else
        echo "📥 Downloading base system to cache..."
        wget -q --show-progress "$BASE_URL" -O "$cache_file" || handle_error "Failed to download $DISTRO base"
    fi
    
    # Extract based on file type
    if [[ "$filename" == *.tar.gz ]]; then
        tar xzvf "$cache_file" -C "$ROOTDIR" || handle_error "Failed to extract $DISTRO base"
    elif [[ "$filename" == *.tar.xz ]]; then
        tar xJvf "$cache_file" -C "$ROOTDIR" || handle_error "Failed to extract $DISTRO base"
    else
        handle_error "Unsupported archive format: $filename"
    fi
    
    echo "✅ Base system downloaded and extracted"
}

# Setup chroot environment
setup_chroot_environment() {
    echo "🔧 Setting up chroot environment..."
    
    # Mount necessary filesystems
    mount --bind /dev "$ROOTDIR/dev"
    mount --bind /dev/pts "$ROOTDIR/dev/pts"
    mount --bind /proc "$ROOTDIR/proc"
    mount --bind /sys "$ROOTDIR/sys"
    
    # Setup basic system configuration
    echo "nameserver $DNS_SERVER" | tee "$ROOTDIR/etc/resolv.conf"
    echo "$HOSTNAME" | tee "$ROOTDIR/etc/hostname"
    echo "127.0.0.1 localhost
127.0.1.1 $HOSTNAME" | tee "$ROOTDIR/etc/hosts"
    
    # Setup QEMU if needed
    if ! uname -m | grep -q aarch64; then
        echo "🔧 Setting up QEMU for cross-architecture emulation..."
        wget "$QEMU_DOWNLOAD_URL/$QEMU_VERSION/qemu-aarch64-static" || handle_error "Failed to download QEMU"
        install -m755 qemu-aarch64-static "$ROOTDIR/"
        
        # Register binfmt handlers
        echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
        echo ':aarch64ld:M::\x7fELF\x02\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
    else
        echo "✅ Running on ARM64, skipping QEMU setup"
    fi
    
    # Set environment variables
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
    export DEBIAN_FRONTEND=noninteractive
    
    echo "✅ Chroot environment setup completed"
}

# Distribution-specific setup
setup_distribution() {
    echo "🔧 Setting up $DISTRO system..."
    
    case "$DISTRO" in
        "ubuntu")
            setup_ubuntu
            ;;
        "armbian")
            setup_armbian
            ;;
    esac
    
    echo "✅ $DISTRO setup completed"
}

# Ubuntu-specific setup
setup_ubuntu() {
    chroot "$ROOTDIR" apt update || handle_error "Failed to update package lists"
    chroot "$ROOTDIR" apt upgrade -y || echo "⚠️  Package upgrade had issues"
    
    # Install basic packages
    chroot "$ROOTDIR" apt install -y bash-completion sudo ssh nano initramfs-tools u-boot-tools || echo "⚠️  Some packages installation had issues"
    
    # Install device specific packages
    chroot "$ROOTDIR" apt install -y rmtfs protection-domain-mapper tqftpserv || echo "⚠️  Some device packages installation had issues"
    
    # Remove laptop-specific service check
    if [ -f "$ROOTDIR/lib/systemd/system/pd-mapper.service" ]; then
        sed -i '/ConditionKernelVersion/d' "$ROOTDIR/lib/systemd/system/pd-mapper.service"
    fi
}

# Armbian-specific setup
setup_armbian() {
    # Armbian already has a functional system, just update package lists
    chroot "$ROOTDIR" apt update || echo "⚠️  Package update had issues"
    
    # Install additional packages needed for Xiaomi K20 Pro
    chroot "$ROOTDIR" apt install -y sudo ssh nano initramfs-tools || echo "⚠️  Some packages installation had issues"
    
    # Try to install device-specific packages (may not be available in Armbian)
    chroot "$ROOTDIR" apt install -y rmtfs-mgr protection-domain-mapper tqftpserv || {
        echo "⚠️  Some device packages not available in Armbian, continuing..."
    }
    
    # Remove laptop-specific service check if the service exists
    if [ -f "$ROOTDIR/lib/systemd/system/pd-mapper.service" ]; then
        sed -i '/ConditionKernelVersion/d' "$ROOTDIR/lib/systemd/system/pd-mapper.service"
    fi
}

# Install device packages
install_device_packages() {
    echo "📦 Installing device packages..."
    
    local device_debs_dir=$(get_device_debs_dir "$KERNEL_VERSION")
    
    if [ "$SKIP_KERNEL_BUILD" = "true" ]; then
        echo "🔧 Skipping kernel build, using existing device packages..."
        
        if [ -d "$device_debs_dir" ]; then
            cp "$device_debs_dir"/*-xiaomi-raphael.deb "$ROOTDIR/tmp/" || handle_error "Failed to copy existing device packages"
        else
            handle_error "Device packages directory not found: $device_debs_dir"
        fi
    else
        echo "🔧 Using freshly built device packages..."
        
        if [ ! -d "$KERNEL_DEBS_DIR" ]; then
            handle_error "Kernel packages directory not found: $KERNEL_DEBS_DIR"
        fi
        cp "$KERNEL_DEBS_DIR"/*-xiaomi-raphael.deb "$ROOTDIR/tmp/" || handle_error "Failed to copy kernel packages"
    fi
    
    # Install packages with error tolerance
    chroot "$ROOTDIR" dpkg -i "/tmp/$KERNEL_PACKAGE.deb" || echo "⚠️  Kernel package installation had issues"
    chroot "$ROOTDIR" dpkg -i "/tmp/$FIRMWARE_PACKAGE.deb" || echo "⚠️  Firmware package installation had issues"
    chroot "$ROOTDIR" dpkg -i "/tmp/$ALSA_PACKAGE.deb" || echo "⚠️  ALSA package installation had issues"
    
    # Cleanup temporary files
    rm "$ROOTDIR/tmp"/*-xiaomi-raphael.deb 2>/dev/null || true
    
    # Update initramfs
    chroot "$ROOTDIR" update-initramfs -c -k all || echo "⚠️  Initramfs update had issues"
    
    echo "✅ Device packages installed"
}

# Setup boot configuration
setup_boot_configuration() {
    echo "🔧 Setting up boot configuration..."
    
    case "$DISTRO" in
        "ubuntu")
            setup_ubuntu_boot
            ;;
        "armbian")
            setup_armbian_boot
            ;;
    esac
    
    echo "✅ Boot configuration completed"
}

# Ubuntu boot setup
setup_ubuntu_boot() {
    # Install GRUB for EFI
    chroot "$ROOTDIR" apt install -y grub-efi-arm64 || echo "⚠️  GRUB installation had issues"
    
    # Configure GRUB
    if [ -f "$ROOTDIR/etc/default/grub" ]; then
        sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' "$ROOTDIR/etc/default/grub"
        sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT=""/' "$ROOTDIR/etc/default/grub"
    fi
    
    # Create fstab
    echo "PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee "$ROOTDIR/etc/fstab"
    
    # Setup GDM for Ubuntu desktop
    if [ "$DESKTOP_ENV" != "ubuntu-server" ]; then
        mkdir -p "$ROOTDIR/var/lib/gdm"
        touch "$ROOTDIR/var/lib/gdm/run-initial-setup"
    fi
}

# Armbian boot setup
setup_armbian_boot() {
    # Create fstab
    echo "PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee "$ROOTDIR/etc/fstab"
    
    # Ensure Armbian has necessary boot tools
    chroot "$ROOTDIR" apt install -y u-boot-tools || echo "⚠️  U-Boot tools installation had issues"
}

# Finalize and cleanup
finalize_build() {
    echo "🔧 Finalizing build..."
    
    # Clean up packages
    chroot "$ROOTDIR" apt clean || echo "⚠️  Package cleanup had issues"
    
    # Cleanup QEMU if installed
    if ! uname -m | grep -q aarch64; then
        echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64 2>/dev/null || true
        echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64ld 2>/dev/null || true
        rm -f "$ROOTDIR/qemu-aarch64-static" 2>/dev/null || true
        rm -f "qemu-aarch64-static" 2>/dev/null || true
    fi
    
    # Unmount filesystems
    umount "$ROOTDIR/sys" 2>/dev/null || true
    umount "$ROOTDIR/proc" 2>/dev/null || true
    umount "$ROOTDIR/dev/pts" 2>/dev/null || true
    umount "$ROOTDIR/dev" 2>/dev/null || true
    umount "$ROOTDIR" 2>/dev/null || true
    
    # Remove directory
    rm -rf "$ROOTDIR" 2>/dev/null || true
    
    # Compress rootfs image
    echo "📦 Compressing rootfs image..."
    7z a rootfs.7z "$ROOTFS_IMG" || echo "⚠️  Compression had issues"
    
    echo "✅ Build finalized successfully"
    echo "💡 Boot command for legacy boot: \"root=PARTLABEL=linux\""
}

# ----------------------------- 
# Main function
# ----------------------------- 
main() {
    log_info "Starting rootfs build for Xiaomi K20 Pro (Raphael)"
    
    # Step 1: Parse command-line arguments
    parse_arguments "$@"
    
    # Step 2: Validate parameters
    validate_parameters
    
    # Step 3: Check root permissions
    if [ "$(id -u)" -ne 0 ]; then
        log_error "Rootfs can only be built as root"
        exit 1
    fi
    
    # Set Ubuntu version information
    VERSION="noble"
    UBUNTU_VERSION="24.04.3"
    
    # Step 4: Create rootfs image file
    log_info "Creating rootfs image file..."
    truncate -s 6G rootfs.img
    mkfs.ext4 rootfs.img
    mkdir -p rootdir
    mount -o loop rootfs.img rootdir
    
    # Step 5: Download base system
    log_info "Downloading Ubuntu base system..."
    wget "https://cdimage.ubuntu.com/ubuntu-base/releases/$VERSION/release/ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz"
    
    # Step 6: Extract base system
    log_info "Extracting base system..."
    tar xzvf ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz -C rootdir
    
    # Step 7: Mount necessary filesystems
    log_info "Mounting necessary filesystems..."
    mount --bind /dev rootdir/dev
    mount --bind /dev/pts rootdir/dev/pts
    mount --bind /proc rootdir/proc
    mount --bind /sys rootdir/sys
    
    # Step 8: Configure network and system settings
    log_info "Configuring network and system settings..."
    echo "nameserver 1.1.1.1" | tee rootdir/etc/resolv.conf
    echo "xiaomi-raphael" | tee rootdir/etc/hostname
    echo "127.0.0.1 localhost\n127.0.1.1 xiaomi-raphael" | tee rootdir/etc/hosts
    
    # Step 9: Install QEMU for emulation (if not on ARM64)
    if [ "$(uname -m)" != "aarch64" ]; then
        log_info "Installing QEMU for ARM64 emulation..."
        wget "https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static"
        install -m755 qemu-aarch64-static rootdir/
        
        echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
        echo ':aarch64ld:M::\x7fELF\x02\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
    else
        log_info "Running on ARM64, skipping QEMU installation"
    fi
    
    # Step 10: Configure environment variables for chroot
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
    export DEBIAN_FRONTEND=noninteractive
    
    # Step 11: Update package lists and upgrade
    log_info "Updating package lists and upgrading system..."
    chroot rootdir apt update
    chroot rootdir apt upgrade -y
    
    # Step 12: Install basic packages
    log_info "Installing basic packages..."
    chroot rootdir apt install -y bash-completion sudo ssh nano initramfs-tools
    
    # Step 13: Install device-specific packages
    log_info "Installing device-specific packages..."
    chroot rootdir apt install -y rmtfs protection-domain-mapper tqftpserv
    
    # Step 14: Remove check for laptop kernel version
    sed -i '/ConditionKernelVersion/d' rootdir/lib/systemd/system/pd-mapper.service
    
    # Step 15: Install custom kernel packages
    log_info "Installing custom kernel packages..."
    cp xiaomi-raphael-debs_*/\*-xiaomi-raphael.deb rootdir/tmp/
    chroot rootdir dpkg -i /tmp/linux-xiaomi-raphael.deb
    chroot rootdir dpkg -i /tmp/firmware-xiaomi-raphael.deb
    chroot rootdir dpkg -i /tmp/alsa-xiaomi-raphael.deb
    rm rootdir/tmp/*-xiaomi-raphael.deb
    
    # Step 16: Update initramfs
    chroot rootdir update-initramfs -c -k all
    
    # Step 17: Install EFI bootloader
    log_info "Installing EFI bootloader..."
    chroot rootdir apt install -y grub-efi-arm64
    
    # Step 18: Configure GRUB
    sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' rootdir/etc/default/grub
    sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT=""/' rootdir/etc/default/grub
    
    # Step 19: Create fstab
    log_info "Creating fstab..."
    echo "PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1\nPARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee rootdir/etc/fstab
    
    # Step 20: Create GDM directories
    mkdir -p rootdir/var/lib/gdm
    touch rootdir/var/lib/gdm/run-initial-setup
    
    # Step 21: Clean up apt cache
    chroot rootdir apt clean
    
    # Step 22: Remove QEMU emulation if installed
    if [ "$(uname -m)" != "aarch64" ]; then
        log_info "Removing QEMU emulation..."
        echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64 2>/dev/null || true
        echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64ld 2>/dev/null || true
        rm -f rootdir/qemu-aarch64-static
        rm -f qemu-aarch64-static
    fi
    
    # Step 23: Unmount filesystems
    log_info "Unmounting filesystems..."
    umount rootdir/sys
    umount rootdir/proc
    umount rootdir/dev/pts
    umount rootdir/dev
    umount rootdir
    
    # Step 24: Clean up
    rm -d rootdir 2>/dev/null || true
    
    # Step 25: Compress rootfs image
    log_info "Compressing rootfs image..."
    7z a rootfs.7z rootfs.img
    
    log_success "Rootfs build completed successfully!"
    log_info "Boot command line for legacy boot: root=PARTLABEL=linux"
    log_info "Rootfs image: rootfs.img"
    log_info "Compressed rootfs: rootfs.7z"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi