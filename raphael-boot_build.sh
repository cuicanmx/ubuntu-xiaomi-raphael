#!/bin/bash

# Boot image creation script for Xiaomi K20 Pro (Raphael)
# Standardized implementation with centralized configuration

set -e  # Exit on any error

# ----------------------------- 
# Load centralized configuration
# ----------------------------- 
if [ -f "build-config.sh" ]; then
    source "build-config.sh"
else
    echo "❌ Error: build-config.sh not found!"
    exit 1
fi

# ----------------------------- 
# Color output functions
# ----------------------------- 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ----------------------------- 
# Cleanup function
# ----------------------------- 
cleanup() {
    log_info "Cleaning up..."
    
    # Unmount mount points if they exist
    if mountpoint -q "$MOUNT_DIR"; then
        sudo umount "$MOUNT_DIR" 2>/dev/null || true
    fi
    
    if mountpoint -q "$ROOTFS_MOUNT_DIR"; then
        sudo umount "$ROOTFS_MOUNT_DIR" 2>/dev/null || true
    fi
    
    # Remove temporary directories
    rm -rf "$MOUNT_DIR" "$ROOTFS_MOUNT_DIR" "$TEMP_DIR"
    
    log_success "Cleanup completed"
}

# ----------------------------- 
# Error handling setup
# ----------------------------- 
trap cleanup EXIT

# ----------------------------- 
# Parameter parsing
# ----------------------------- 
parse_arguments() {
    log_info "Parsing command-line arguments..."
    
    # Set default values from environment variables or centralized configuration
    KERNEL_VERSION="${KERNEL_VERSION:-${KERNEL_VERSION_DEFAULT}}"
    DISTRIBUTION="${DISTRIBUTION:-${DISTRIBUTION_DEFAULT:-ubuntu}}"
    BOOT_SOURCE="${BOOT_SOURCE:-${BOOT_SOURCE_DEFAULT}}"
    ROOTFS_IMAGE="${ROOTFS_IMAGE:-}"
    ROOTFS_ZIP="${ROOTFS_ZIP:-}"
    OUTPUT_FILE="${OUTPUT_FILE:-}"
    USE_CACHE="${USE_CACHE:-${CACHE_ENABLED_DEFAULT}}"
    DRY_RUN=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kernel-version)
                KERNEL_VERSION="$2"
                shift 2
                ;;
            -d|--distribution)
                DISTRIBUTION="$2"
                shift 2
                ;;
            -b|--boot-source)
                BOOT_SOURCE="$2"
                shift 2
                ;;
            -r|--rootfs-image)
                ROOTFS_IMAGE="$2"
                shift 2
                ;;
            -z|--rootfs-zip)
                ROOTFS_ZIP="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            --cache)
                USE_CACHE=true
                shift 1
                ;;
            --no-cache)
                USE_CACHE=false
                shift 1
                ;;
            --dry-run)
                DRY_RUN=true
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
}

# ----------------------------- 
# Show help information
# ----------------------------- 
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Create boot image for Xiaomi K20 Pro (Raphael)

OPTIONS:
    -k, --kernel-version VERSION    Kernel version (e.g., 6.18) [default: ${KERNEL_VERSION_DEFAULT}]
    -d, --distribution DISTRO       Distribution (ubuntu/armbian) [default: ubuntu]
    -b, --boot-source URL           Boot image source URL
    -r, --rootfs-image FILE         Rootfs image file (img format)
    -z, --rootfs-zip FILE           Rootfs image file (zip format)
    -o, --output FILE               Output boot image file
    --cache                         Enable build cache
    --no-cache                      Disable build cache [default: ${CACHE_ENABLED_DEFAULT}]
    --dry-run                       Dry run mode (extract UUID only, no image creation)
    -h, --help                      Show this help message

EXAMPLES:
    $0 -k 6.18 -d ubuntu -r root-ubuntu-6.18.img --cache
    $0 -k 6.18 -d ubuntu -z root-ubuntu-6.18.zip --no-cache
    $0 --kernel-version 6.18 --distribution ubuntu --output xiaomi-k20pro-boot.img
    $0 --kernel-version 6.18 --distribution ubuntu --rootfs-image root-ubuntu-6.18.img --dry-run

EOF
}

# ----------------------------- 
# Validate arguments
# ----------------------------- 
validate_arguments() {
    log_info "Validating arguments..."
    
    if [[ -z "$KERNEL_VERSION" ]]; then
        log_error "Kernel version is required"
        show_help
        exit 1
    fi
    
    if [[ -z "$DISTRIBUTION" ]]; then
        DISTRIBUTION="ubuntu"
        log_warning "Distribution not specified, using default: $DISTRIBUTION"
    fi
    
    # Validate distribution
    if ! validate_distribution "$DISTRIBUTION" "noble"; then
        log_error "Unsupported distribution: $DISTRIBUTION"
        exit 1
    fi
    
    # Check rootfs file parameters
    if [[ -z "$ROOTFS_IMAGE" && -z "$ROOTFS_ZIP" ]]; then
        ROOTFS_IMAGE="root-${DISTRIBUTION}-${KERNEL_VERSION}.img"
        log_info "Using default rootfs image: $ROOTFS_IMAGE"
    elif [[ -n "$ROOTFS_IMAGE" && -n "$ROOTFS_ZIP" ]]; then
        log_error "Cannot specify both --rootfs-image and --rootfs-zip"
        show_help
        exit 1
    fi
    
    # Set default output file if not specified
    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE=$(printf "${BOOT_OUTPUT_DEFAULT}" "$DISTRIBUTION" "$KERNEL_VERSION")
        log_info "Using default output: $OUTPUT_FILE"
    fi
    
    # Create cache directory
    BOOT_CACHE_DIR="${CACHE_DIR}/boot-images"
    mkdir -p "$BOOT_CACHE_DIR"
    
    # Create temporary directories
    TEMP_DIR=$(mktemp -d)
    MOUNT_DIR="$TEMP_DIR/boot-mount"
    ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs-mount"
    
    mkdir -p "$MOUNT_DIR" "$ROOTFS_MOUNT_DIR"
    
    log_success "Arguments validated successfully"
    log_info "Kernel version: $KERNEL_VERSION"
    log_info "Distribution: $DISTRIBUTION"
    log_info "Boot source: $BOOT_SOURCE"
    log_info "Output file: $OUTPUT_FILE"
    log_info "Use cache: $USE_CACHE"
}

# ----------------------------- 
# Download boot image
# ----------------------------- 
download_boot_image() {
    local boot_file="$TEMP_DIR/original-boot.img"
    
    # 使用固定的GitHub Releases URL
    local BOOT_SOURCE_URL="https://github.com/GengWei1997/kernel-deb/releases/download/v1.0.0/xiaomi-k20pro-boot.img"
    
    log_info "Downloading boot image from: $BOOT_SOURCE_URL"
    
    # 直接下载boot镜像
    if wget -O "$boot_file" "$BOOT_SOURCE_URL" 2>/dev/null; then
        log_success "Boot image downloaded successfully"
        echo "$boot_file"
    else
        log_warning "Failed to download boot image, creating empty one"
        create_empty_boot_image "$boot_file"
        echo "$boot_file"
    fi
}

# ----------------------------- 
# Create empty boot image
# ----------------------------- 
create_empty_boot_image() {
    local boot_file="$1"
    
    log_info "Creating empty boot image (${BOOT_IMAGE_SIZE})..."
    
    # Create empty image file
    dd if=/dev/zero of="$boot_file" bs=1M count=$(echo "${BOOT_IMAGE_SIZE}" | sed 's/[^0-9]//g') status=none
    
    # Partition and format
    parted -s "$boot_file" mklabel gpt
    parted -s "$boot_file" mkpart primary fat32 1MiB 100%
    
    # Create loop device and format
    local loop_dev=$(sudo losetup --find --show "$boot_file")
    sudo mkfs.fat -F32 "${loop_dev}p1"
    sudo losetup -d "$loop_dev"
    
    log_success "Empty boot image created: $boot_file"
}

# ----------------------------- 
# Mount boot image
# ----------------------------- 
mount_boot_image() {
    local boot_file="$1"
    
    log_info "Mounting boot image..."
    
    # Mount boot image
    sudo mount -o loop "$boot_file" "$MOUNT_DIR" || {
        log_error "Failed to mount boot image"
        return 1
    }
    
    log_success "Boot image mounted at: $MOUNT_DIR"
    
    # Show boot image contents
    log_info "Boot image contents:"
    ls -la "$MOUNT_DIR/"
}

# ----------------------------- 
# Handle rootfs file (supports img and zip formats)
# ----------------------------- 
handle_rootfs_file() {
    if [[ -n "$ROOTFS_ZIP" ]]; then
        log_info "Processing rootfs zip file: $ROOTFS_ZIP"
        
        if [[ ! -f "$ROOTFS_ZIP" ]]; then
            log_error "Rootfs zip file not found: $ROOTFS_ZIP"
            return 1
        fi
        
        # Extract zip file
        log_info "Extracting rootfs zip file..."
        unzip -q "$ROOTFS_ZIP" || {
            log_error "Failed to extract zip file: $ROOTFS_ZIP"
            return 1
        }
        
        # Find extracted img file
        ROOTFS_IMAGE=$(ls root-*.img | head -1)
        if [[ -z "$ROOTFS_IMAGE" ]]; then
            log_error "No img file found in zip archive"
            return 1
        fi
        
        log_success "Extracted rootfs image: $ROOTFS_IMAGE"
        
    elif [[ -n "$ROOTFS_IMAGE" ]]; then
        log_info "Using rootfs image file: $ROOTFS_IMAGE"
        
        if [[ ! -f "$ROOTFS_IMAGE" ]]; then
            log_error "Rootfs image file not found: $ROOTFS_IMAGE"
            return 1
        fi
    else
        log_error "No rootfs file specified"
        return 1
    fi
}

# ----------------------------- 
# Extract rootfs UUID and kernel files
# ----------------------------- 
extract_rootfs_uuid() {
    log_info "Extracting UUID from rootfs image..."
    
    if [[ ! -f "$ROOTFS_IMAGE" ]]; then
        log_error "Rootfs image not found: $ROOTFS_IMAGE"
        return 1
    fi
    
    # Extract UUID using blkid
    ROOTFS_UUID=$(sudo blkid -s UUID -o value "$ROOTFS_IMAGE")
    
    if [[ -z "$ROOTFS_UUID" ]]; then
        log_error "Failed to extract UUID from rootfs image"
        return 1
    fi
    
    log_success "Rootfs UUID extracted: $ROOTFS_UUID"
}

# ----------------------------- 
# Copy kernel files from rootfs to boot image
# ----------------------------- 
copy_kernel_files() {
    log_info "Copying kernel files from rootfs to boot image..."
    
    # Mount rootfs
    sudo mount -o loop "$ROOTFS_IMAGE" "$ROOTFS_MOUNT_DIR" || {
        log_error "Failed to mount rootfs image"
        return 1
    }
    
    # Create dtbs directory in boot image if it doesn't exist
    sudo mkdir -p "$MOUNT_DIR/dtbs"
    
    # Copy device tree binaries
    log_info "Copying device tree binaries..."
    if [ -d "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" ]; then
        sudo cp -r "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" "$MOUNT_DIR/dtbs/"
        log_success "Copied device tree binaries"
    else
        log_warning "Device tree binaries not found in rootfs"
    fi
    
    # Copy kernel config
    log_info "Copying kernel config..."
    local config_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "config-*" | head -1)
    if [[ -n "$config_file" ]]; then
        sudo cp "$config_file" "$MOUNT_DIR/"
        log_success "Copied kernel config: $(basename $config_file)"
    else
        log_warning "Kernel config not found in rootfs"
    fi
    
    # Copy initrd image
    log_info "Copying initrd image..."
    local initrd_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "initrd.img-*" | head -1)
    if [[ -n "$initrd_file" ]]; then
        sudo cp "$initrd_file" "$MOUNT_DIR/initramfs"
        log_success "Copied initrd image -> initramfs"
    else
        log_error "Initrd image not found in rootfs"
        sudo umount "$ROOTFS_MOUNT_DIR"
        return 1
    fi
    
    # Copy vmlinuz
    log_info "Copying vmlinuz..."
    local vmlinuz_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "vmlinuz-*" | head -1)
    if [[ -n "$vmlinuz_file" ]]; then
        sudo cp "$vmlinuz_file" "$MOUNT_DIR/linux.efi"
        log_success "Copied vmlinuz -> linux.efi"
    else
        log_error "Vmlinuz not found in rootfs"
        sudo umount "$ROOTFS_MOUNT_DIR"
        return 1
    fi
    
    # Unmount rootfs
    sudo umount "$ROOTFS_MOUNT_DIR"
    
    log_success "All kernel files copied successfully"
}

# ----------------------------- 
# Update boot loader configuration
# ----------------------------- 
update_boot_config() {
    log_info "Updating boot loader configuration..."
    
    # Create loader directory structure
    sudo mkdir -p "$MOUNT_DIR/loader/entries"
    
    # Create Ubuntu boot configuration
    sudo tee "$MOUNT_DIR/loader/entries/ubuntu.conf" > /dev/null << EOF
title  Ubuntu
sort-key ubuntu
linux   linux.efi
initrd  initramfs

options console=tty0 loglevel=3 splash root=UUID=$ROOTFS_UUID rw
EOF
    
    log_success "Boot loader configuration updated"
    
    # Show configuration content
    log_info "Boot configuration:"
    cat "$MOUNT_DIR/loader/entries/ubuntu.conf"
}

# ----------------------------- 
# Verify boot image contents
# ----------------------------- 
verify_boot_image() {
    log_info "Verifying boot image contents..."
    
    # Check critical files
    if [[ ! -f "$MOUNT_DIR/linux.efi" ]]; then
        log_error "linux.efi not found in boot image"
        return 1
    fi
    
    if [[ ! -f "$MOUNT_DIR/initramfs" ]]; then
        log_error "initramfs not found in boot image"
        return 1
    fi
    
    if [[ ! -f "$MOUNT_DIR/loader/entries/ubuntu.conf" ]]; then
        log_error "Boot configuration not found"
        return 1
    fi
    
    log_success "Boot image verification passed"
    
    # Show final content
    log_info "Final boot image structure:"
    ls -la "$MOUNT_DIR/"
    echo "--- Loader entries ---"
    ls -la "$MOUNT_DIR/loader/entries/"
}

# ----------------------------- 
# Unmount and save boot image
# ----------------------------- 
finalize_boot_image() {
    local original_boot="$1"
    
    log_info "Finalizing boot image..."
    
    # Unmount boot image
    sudo umount "$MOUNT_DIR"
    
    # Copy to output file
    cp "$original_boot" "$OUTPUT_FILE"
    
    log_success "Boot image finalized: $OUTPUT_FILE"
    
    # Show file information
    ls -lh "$OUTPUT_FILE"
}

# ----------------------------- 
# Main function
# ----------------------------- 
main() {
    log_info "Starting boot image creation for Xiaomi K20 Pro (Raphael)"
    
    # Step 1: Parse arguments
    parse_arguments "$@"
    
    # Step 2: Validate arguments
    validate_arguments
    
    # Step 3: Handle rootfs file (supports img and zip)
    handle_rootfs_file
    
    # Step 4: Extract rootfs UUID
    extract_rootfs_uuid
    
    # If dry-run mode, just output the UUID and exit
    if [[ "$DRY_RUN" == true ]]; then
        log_info "Dry run mode - UUID extraction only"
        echo "Rootfs UUID: $ROOTFS_UUID"
        log_success "Dry run completed successfully"
        exit 0
    fi
    
    # Step 5: Download or create boot image
    local boot_file=$(download_boot_image)
    
    # Step 6: Mount boot image
    mount_boot_image "$boot_file"
    
    # Step 7: Copy kernel files
    copy_kernel_files
    
    # Step 8: Update boot configuration
    update_boot_config
    
    # Step 9: Verify boot image
    verify_boot_image
    
    # Step 10: Finalize boot image
    finalize_boot_image "$boot_file"
    
    log_success "Boot image creation completed successfully!"
    log_info "Output file: $OUTPUT_FILE"
    log_info "RootFS UUID: $ROOTFS_UUID"
}

# ----------------------------- 
# Script execution
# ----------------------------- 
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi