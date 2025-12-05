#!/bin/bash

# Boot image creation script for Xiaomi K20 Pro (Raphael)
# Simplified version based on working example

set -e  # Exit on any error

# Simple logging
log() { echo "[$(date +'%H:%M:%S')] $1"; }
log_info() { log "INFO: $1"; }
log_success() { log "SUCCESS: $1"; }
log_error() { log "ERROR: $1"; exit 1; }

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Unmount if mounted
    if mountpoint -q "$BOOT_MOUNT_DIR" 2>/dev/null; then
        sudo umount "$BOOT_MOUNT_DIR" 2>/dev/null || log "Warning: Failed to unmount $BOOT_MOUNT_DIR"
    fi
    
    if mountpoint -q "$ROOTFS_MOUNT_DIR" 2>/dev/null; then
        sudo umount "$ROOTFS_MOUNT_DIR" 2>/dev/null || log "Warning: Failed to unmount $ROOTFS_MOUNT_DIR"
    fi
    
    # Remove temporary directories
    [[ -d "$BOOT_MOUNT_DIR" ]] && rm -rf "$BOOT_MOUNT_DIR" 2>/dev/null || true
    [[ -d "$ROOTFS_MOUNT_DIR" ]] && rm -rf "$ROOTFS_MOUNT_DIR" 2>/dev/null || true
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" 2>/dev/null || true
    
    log_success "Cleanup completed"
}

trap cleanup EXIT

# Show help information
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Create boot image for Xiaomi K20 Pro (Raphael)

OPTIONS:
    -k, --kernel-version VERSION    Kernel version (e.g., 6.18)
    -d, --distribution DISTRO       Distribution (ubuntu)
    -r, --rootfs-image FILE         Rootfs image file (img format)
    -o, --output FILE               Output boot image file
    -h, --help                      Show this help message

EXAMPLES:
    $0 -k 6.18 -d ubuntu -r root-ubuntu-6.18.img
    $0 --kernel-version 6.18 --distribution ubuntu --output xiaomi-k20pro-boot.img

EOF
}

# Main function
main() {
    log_info "Starting boot image creation process..."
    
    # Parse arguments
    KERNEL_VERSION=""
    DISTRIBUTION="ubuntu"
    ROOTFS_IMAGE=""
    OUTPUT_FILE=""
    
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
    
    # Validate arguments
    [[ -z "$KERNEL_VERSION" ]] && log_error "Kernel version is required (use -k)"
    [[ -z "$ROOTFS_IMAGE" ]] && log_error "Rootfs image is required (use -r)"
    [[ ! -f "$ROOTFS_IMAGE" ]] && log_error "Rootfs image not found: $ROOTFS_IMAGE"
    
    # Set default output file
    [[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="xiaomi-k20pro-boot-${DISTRIBUTION}-${KERNEL_VERSION}.img"
    
    log_info "Parameters:"
    log_info "  Kernel version: $KERNEL_VERSION"
    log_info "  Distribution: $DISTRIBUTION"
    log_info "  Rootfs image: $ROOTFS_IMAGE"
    log_info "  Output file: $OUTPUT_FILE"
    
    # Create temporary directories
    TEMP_DIR=$(mktemp -d)
    BOOT_MOUNT_DIR="$TEMP_DIR/boot_tmp"
    ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs_mount"
    mkdir -p "$BOOT_MOUNT_DIR" "$ROOTFS_MOUNT_DIR"
    
    log_success "Temporary directories created"
    
    # Step 1: Download boot image
    log_info "Step 1: Downloading boot image..."
    
    BOOT_SOURCE_URL="https://github.com/cuicanmx/ubuntu-xiaomi-raphael/releases/download/xiaomi-k20pro-boot/xiaomi-k20pro-boot.img"
    BOOT_FILE="$TEMP_DIR/original-boot.img"
    
    if ! wget -O "$BOOT_FILE" "$BOOT_SOURCE_URL"; then
        log_error "Failed to download boot image from $BOOT_SOURCE_URL"
    fi
    
    BOOT_SIZE=$(stat -c%s "$BOOT_FILE" 2>/dev/null || stat -f%z "$BOOT_FILE" 2>/dev/null)
    if [[ $BOOT_SIZE -eq 0 ]]; then
        log_error "Downloaded boot image is empty (0 bytes)"
    fi
    
    log_success "Boot image downloaded: $BOOT_FILE (size: $BOOT_SIZE bytes)"
    
    # Step 2: Mount boot image
    log_info "Step 2: Mounting boot image..."
    
    if ! sudo mount -o loop "$BOOT_FILE" "$BOOT_MOUNT_DIR"; then
        log_error "Failed to mount boot image"
    fi
    
    log_success "Boot image mounted successfully"
    log_info "Boot image contents:"
    ls -la "$BOOT_MOUNT_DIR/"
    
    # Step 3: Mount rootfs image
    log_info "Step 3: Mounting rootfs image..."
    
    if ! sudo mount -o loop "$ROOTFS_IMAGE" "$ROOTFS_MOUNT_DIR"; then
        log_error "Failed to mount rootfs image"
    fi
    
    log_success "Rootfs image mounted successfully"
    
    # Step 4: Copy kernel files
    log_info "Step 4: Copying kernel files..."
    
    # Create necessary directories
    sudo mkdir -p "$BOOT_MOUNT_DIR/dtbs"
    
    # Copy device tree binaries
    if [[ -d "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" ]]; then
        sudo cp -r "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" "$BOOT_MOUNT_DIR/dtbs/"
        log_success "Device tree binaries copied"
    else
        log "Warning: Device tree binaries not found"
    fi
    
    # Copy kernel config
    local config_files=$(find "$ROOTFS_MOUNT_DIR/boot" -name "config-*" 2>/dev/null || true)
    if [[ -n "$config_files" ]]; then
        sudo cp $config_files "$BOOT_MOUNT_DIR/" 2>/dev/null || true
        log_success "Kernel config copied"
    else
        log "Warning: Kernel config not found"
    fi
    
    # Copy initrd image
    local initrd_files=$(find "$ROOTFS_MOUNT_DIR/boot" -name "initrd.img-*" 2>/dev/null || true)
    if [[ -n "$initrd_files" ]]; then
        sudo cp $initrd_files "$BOOT_MOUNT_DIR/initramfs" 2>/dev/null || true
        log_success "Initrd image copied"
    else
        log_error "Initrd image not found - this is required"
    fi
    
    # Copy vmlinuz
    local vmlinuz_files=$(find "$ROOTFS_MOUNT_DIR/boot" -name "vmlinuz-*" 2>/dev/null || true)
    if [[ -n "$vmlinuz_files" ]]; then
        sudo cp $vmlinuz_files "$BOOT_MOUNT_DIR/linux.efi" 2>/dev/null || true
        log_success "Vmlinuz copied"
    else
        log_error "Vmlinuz not found - this is required"
    fi
    
    # Step 5: Unmount images
    log_info "Step 5: Unmounting images..."
    
    sudo umount "$ROOTFS_MOUNT_DIR"
    log_success "Rootfs image unmounted"
    
    sudo umount "$BOOT_MOUNT_DIR"
    log_success "Boot image unmounted"
    
    # Step 6: Save boot image
    log_info "Step 6: Saving boot image..."
    
    if ! cp "$BOOT_FILE" "$OUTPUT_FILE"; then
        log_error "Failed to save boot image to $OUTPUT_FILE"
    fi
    
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
    log_success "Boot image saved: $OUTPUT_FILE (size: $OUTPUT_SIZE bytes)"
    
    # Step 7: Cleanup
    cleanup
    
    log_success "Boot image creation completed successfully!"
    log_info "Output file: $OUTPUT_FILE"
}

# Run main function
main "$@"