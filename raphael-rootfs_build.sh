#!/bin/bash

# Modular rootfs build script for Xiaomi K20 Pro (Raphael)
# Enhanced with Armbian support, skip kernel build option, and better error handling

# Source configuration file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/build-config.sh"

# Global variables
ROOTFS_IMG="rootfs.img"
ROOTDIR="rootdir"
SKIP_KERNEL_BUILD=false
DISTRO=""
VERSION=""
KERNEL_VERSION=""
DESKTOP_ENV=""

# Error handling function
handle_error() {
    local message=$1
    local exit_code=${2:-1}
    echo "❌ $message"
    cleanup
    exit $exit_code
}

# Cleanup function
cleanup() {
    echo "🧹 Cleaning up..."
    
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
}

# Parse command line arguments
parse_arguments() {
    if [ $# -lt 3 ]; then
        echo "Usage: $0 <distribution> <version> <kernel_version> [desktop_environment] [--skip-kernel-build]"
        echo "  distribution: ubuntu|armbian"
        echo "  version: for ubuntu: version name, for armbian: noble"
        echo "  kernel_version: e.g., 6.17"
        echo "  desktop_environment: (optional) for ubuntu only"
        echo "  --skip-kernel-build: (optional) use existing device packages instead of building kernel"
        exit 1
    fi

    DISTRO=$1
    VERSION=$2
    KERNEL_VERSION=$3
    
    # Parse optional arguments
    for arg in "${@:4}"; do
        case "$arg" in
            "--skip-kernel-build")
                SKIP_KERNEL_BUILD=true
                ;;
            *)
                if [ "$DISTRO" = "ubuntu" ] && [ -z "$DESKTOP_ENV" ]; then
                    DESKTOP_ENV="$arg"
                fi
                ;;
        esac
    done
    
    # Set default desktop environment for Ubuntu if not provided
    if [ "$DISTRO" = "ubuntu" ] && [ -z "$DESKTOP_ENV" ]; then
        DESKTOP_ENV="ubuntu-desktop"
    fi
    
    echo "✅ Parsed arguments: Distribution=$DISTRO, Version=$VERSION, Kernel=$KERNEL_VERSION"
    if [ "$DISTRO" = "ubuntu" ]; then
        echo "✅ Desktop environment: $DESKTOP_ENV"
    fi
    echo "✅ Skip kernel build: $SKIP_KERNEL_BUILD"
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
    
    # Download base system
    wget -q --show-progress "$BASE_URL" || handle_error "Failed to download $DISTRO base"
    
    # Extract based on file type
    local filename=$(basename "$BASE_URL")
    if [[ "$filename" == *.tar.gz ]]; then
        tar xzvf "$filename" -C "$ROOTDIR" || handle_error "Failed to extract $DISTRO base"
    elif [[ "$filename" == *.tar.xz ]]; then
        tar xJvf "$filename" -C "$ROOTDIR" || handle_error "Failed to extract $DISTRO base"
    else
        handle_error "Unsupported archive format: $filename"
    fi
    
    # Cleanup downloaded file
    rm -f "$filename"
    
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

# Main execution flow
main() {
    echo "🚀 Starting RootFS build for $DISTRO $VERSION"
    echo "🔧 Kernel version: $KERNEL_VERSION"
    
    # Set up error handling and cleanup
    trap cleanup EXIT
    
    # Execute build steps
    parse_arguments "$@"
    validate_configuration
    create_rootfs_image
    download_base_system
    setup_chroot_environment
    setup_distribution
    install_device_packages
    setup_boot_configuration
    finalize_build
    
    echo "🎉 RootFS build completed successfully!"
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi