#!/bin/bash

# Boot image creation script for Xiaomi K20 Pro (Raphael)
# Optimized for GitHub Actions environment

set -e  # Exit on any error

# Load configuration
source "build-config.sh"

# Logging functions
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
log_info() { log "INFO: $1"; }
log_success() { log "SUCCESS: $1"; }
log_warning() { log "WARNING: $1"; }
log_error() { log "ERROR: $1"; exit 1; }

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Unmount mount points if they exist
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        sudo umount "$MOUNT_DIR" 2>/dev/null || true
    fi
    
    # Remove temporary directories
    rm -rf "$MOUNT_DIR" "$TEMP_DIR" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

trap cleanup EXIT

# Parameter parsing
parse_arguments() {
    # Set defaults
    KERNEL_VERSION="${KERNEL_VERSION:-${KERNEL_VERSION_DEFAULT}}"
    DISTRIBUTION="${DISTRIBUTION:-${DISTRIBUTION_DEFAULT:-ubuntu}}"
    ROOTFS_IMAGE="${ROOTFS_IMAGE:-}"
    OUTPUT_FILE="${OUTPUT_FILE:-}"
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
            -r|--rootfs-image)
                ROOTFS_IMAGE="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
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
}

# Show help information
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Create boot image for Xiaomi K20 Pro (Raphael)

OPTIONS:
    -k, --kernel-version VERSION    Kernel version (e.g., 6.18) [default: ${KERNEL_VERSION_DEFAULT}]
    -d, --distribution DISTRO       Distribution (ubuntu) [default: ubuntu]
    -r, --rootfs-image FILE         Rootfs image file (img format)
    -o, --output FILE               Output boot image file
    --dry-run                       Dry run mode (extract UUID only, no image creation)
    -h, --help                      Show this help message

EXAMPLES:
    $0 -k 6.18 -d ubuntu -r root-ubuntu-6.18.img
    $0 --kernel-version 6.18 --distribution ubuntu --output xiaomi-k20pro-boot.img
    $0 --kernel-version 6.18 --rootfs-image root-ubuntu-6.18.img --dry-run

EOF
}

# Validate arguments
validate_arguments() {
    [[ -z "$KERNEL_VERSION" ]] && log_error "Kernel version is required"
    
    DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
    [[ "$DISTRIBUTION" != "ubuntu" ]] && log_error "Only 'ubuntu' distribution is supported"
    
    # Set default rootfs image if not specified
    [[ -z "$ROOTFS_IMAGE" ]] && ROOTFS_IMAGE="root-${DISTRIBUTION}-${KERNEL_VERSION}.img"
    
    # Set default output file
    [[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="xiaomi-k20pro-boot-${DISTRIBUTION}-${KERNEL_VERSION}.img"
    
    # Create temporary directories
    TEMP_DIR=$(mktemp -d)
    MOUNT_DIR="$TEMP_DIR/boot-mount"
    mkdir -p "$MOUNT_DIR"
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
        log_error "Failed to download boot image"
        return 1
    fi
}

# ----------------------------- 
# Mount boot image
# ----------------------------- 
mount_boot_image() {
    local boot_file="$1"
    
    log_info "Mounting boot image..."
    
    # Simple mount using loop device
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
# Handle rootfs file
# ----------------------------- 
handle_rootfs_file() {
    if [[ -n "$ROOTFS_IMAGE" ]]; then
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
# Extract rootfs UUID
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
    
    # Mount rootfs image temporarily
    local rootfs_mount="$TEMP_DIR/rootfs-mount"
    mkdir -p "$rootfs_mount"
    
    sudo mount -o loop "$ROOTFS_IMAGE" "$rootfs_mount" || {
        log_error "Failed to mount rootfs image"
        return 1
    }
    
    # Create directories in boot image
    sudo mkdir -p "$MOUNT_DIR/dtbs"
    sudo mkdir -p "$MOUNT_DIR/loader/entries"
    
    # Copy device tree binaries
    if [ -d "$rootfs_mount/boot/dtbs/qcom" ]; then
        sudo cp -r "$rootfs_mount/boot/dtbs/qcom" "$MOUNT_DIR/dtbs/"
        log_success "Device tree binaries copied"
    else
        log_warning "Device tree binaries not found"
    fi
    
    # Copy kernel config
    local config_file=$(find "$rootfs_mount/boot" -name "config-*" | head -1)
    if [[ -n "$config_file" ]]; then
        sudo cp "$config_file" "$MOUNT_DIR/"
        log_success "Kernel config copied"
    else
        log_warning "Kernel config not found"
    fi
    
    # Copy initrd image
    local initrd_file=$(find "$rootfs_mount/boot" -name "initrd.img-*" | head -1)
    if [[ -n "$initrd_file" ]]; then
        sudo cp "$initrd_file" "$MOUNT_DIR/initramfs"
        log_success "Initrd image copied"
    else
        log_error "Initrd image not found"
        sudo umount "$rootfs_mount"
        return 1
    fi
    
    # Copy vmlinuz
    local vmlinuz_file=$(find "$rootfs_mount/boot" -name "vmlinuz-*" | head -1)
    if [[ -n "$vmlinuz_file" ]]; then
        sudo cp "$vmlinuz_file" "$MOUNT_DIR/linux.efi"
        log_success "Vmlinuz copied"
    else
        log_error "Vmlinuz not found"
        sudo umount "$rootfs_mount"
        return 1
    fi
    
    sudo umount "$rootfs_mount"
    rmdir "$rootfs_mount"
}

# ----------------------------- 
# Update boot loader configuration
# ----------------------------- 
update_boot_config() {
    log_info "Updating boot loader configuration..."
    
    sudo tee "$MOUNT_DIR/loader/entries/ubuntu.conf" > /dev/null << EOF
title  Ubuntu
sort-key ubuntu
linux   linux.efi
initrd  initramfs

options console=tty0 loglevel=3 splash root=UUID=$ROOTFS_UUID rw
EOF
    
    log_success "Boot configuration updated"
}

# ----------------------------- 
# Verify boot image contents
# ----------------------------- 
verify_boot_image() {
    log_info "Verifying boot image contents..."
    
    [[ ! -f "$MOUNT_DIR/linux.efi" ]] && log_error "linux.efi not found" && return 1
    [[ ! -f "$MOUNT_DIR/initramfs" ]] && log_error "initramfs not found" && return 1
    [[ ! -f "$MOUNT_DIR/loader/entries/ubuntu.conf" ]] && log_error "Boot configuration not found" && return 1
    
    log_success "Boot image verification passed"
}

# ----------------------------- 
# Finalize boot image
# ----------------------------- 
finalize_boot_image() {
    local original_boot="$1"
    
    log_info "Finalizing boot image..."
    
    # Unmount boot image
    sudo umount "$MOUNT_DIR"
    
    # Copy to output file
    cp "$original_boot" "$OUTPUT_FILE"
    
    log_success "Boot image created: $OUTPUT_FILE"
}

# ----------------------------- 
# Main function
# ----------------------------- 
main() {
    parse_arguments "$@"
    validate_arguments
    
    log_info "Starting boot image creation for $DISTRIBUTION (Kernel $KERNEL_VERSION)"
    
    # Handle rootfs file
    handle_rootfs_file
    
    # Extract rootfs UUID
    extract_rootfs_uuid
    
    if [[ "$DRY_RUN" == true ]]; then
        log_success "Dry run completed - UUID extracted: $ROOTFS_UUID"
        exit 0
    fi
    
    # Download boot image
    local boot_file=$(download_boot_image)
    
    # Mount boot image
    mount_boot_image "$boot_file"
    
    # Copy kernel files
    copy_kernel_files
    
    # Update boot configuration
    update_boot_config
    
    # Verify boot image
    verify_boot_image
    
    # Finalize boot image
    finalize_boot_image "$boot_file"
    
    log_success "Boot image creation completed successfully"
}

# Run main function
main "$@"