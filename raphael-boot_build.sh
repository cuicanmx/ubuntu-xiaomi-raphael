#!/bin/bash

# Boot image creation script for Xiaomi K20 Pro (Raphael)
# Simplified version based on working example

set -e  # Exit on any error

# Load configuration
source "build-config.sh"

# Simple logging
log() { echo "[$(date +'%H:%M:%S')] $1"; }
log_info() { log "INFO: $1"; }
log_success() { log "SUCCESS: $1"; }
log_error() { log "ERROR: $1"; exit 1; }

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Unmount if mounted
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        sudo umount "$MOUNT_DIR" 2>/dev/null || log_warning "Failed to unmount $MOUNT_DIR"
    fi
    
    # Unmount rootfs mount point if it exists
    local ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs_mount"
    if mountpoint -q "$ROOTFS_MOUNT_DIR" 2>/dev/null; then
        sudo umount "$ROOTFS_MOUNT_DIR" 2>/dev/null || log_warning "Failed to unmount $ROOTFS_MOUNT_DIR"
    fi
    
    # Remove temporary directories
    [[ -d "$MOUNT_DIR" ]] && rm -rf "$MOUNT_DIR" 2>/dev/null || true
    [[ -d "$ROOTFS_MOUNT_DIR" ]] && rm -rf "$ROOTFS_MOUNT_DIR" 2>/dev/null || true
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR" 2>/dev/null || true
    
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
    
    # Check if no arguments provided
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
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
    -h, --help                      Show this help message

EXAMPLES:
    $0 -k 6.18 -d ubuntu -r root-ubuntu-6.18.img
    $0 --kernel-version 6.18 --distribution ubuntu --output xiaomi-k20pro-boot.img

EOF
}

# Validate arguments
validate_arguments() {
    [[ -z "$KERNEL_VERSION" ]] && log_error "Kernel version is required"
    [[ "$DISTRIBUTION" != "ubuntu" ]] && log_error "Only 'ubuntu' distribution is supported"
    [[ -z "$ROOTFS_IMAGE" ]] && log_error "Rootfs image is required"
    [[ ! -f "$ROOTFS_IMAGE" ]] && log_error "Rootfs image not found: $ROOTFS_IMAGE"
    
    # Set default output file
    [[ -z "$OUTPUT_FILE" ]] && OUTPUT_FILE="xiaomi-k20pro-boot-${DISTRIBUTION}-${KERNEL_VERSION}.img"
    
    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    MOUNT_DIR="$TEMP_DIR/boot_tmp"
    mkdir -p "$MOUNT_DIR"
}

# Download boot image
download_boot_image() {
    local boot_file="$TEMP_DIR/original-boot.img"
    local BOOT_SOURCE_URL="https://github.com/GengWei1997/kernel-deb/releases/download/v1.0.0/xiaomi-k20pro-boot.img"
    
    log_info "Downloading boot image from: $BOOT_SOURCE_URL"
    
    if wget -O "$boot_file" "$BOOT_SOURCE_URL"; then
        local size=$(stat -c%s "$boot_file" 2>/dev/null || stat -f%z "$boot_file" 2>/dev/null)
        if [[ $size -gt 0 ]]; then
            log_success "Boot image downloaded: $boot_file (size: $size bytes)"
            echo "$boot_file"
        else
            log_error "Downloaded boot image is empty"
        fi
    else
        log_error "Failed to download boot image"
    fi
}

# Mount boot image
mount_boot_image() {
    local boot_file="$1"
    
    log_info "Mounting boot image: $boot_file"
    
    if sudo mount -o loop "$boot_file" "$MOUNT_DIR"; then
        log_success "Boot image mounted successfully"
        
        # Show boot image contents
        log_info "Boot image contents:"
        ls -la "$MOUNT_DIR/"
    else
        log_error "Failed to mount boot image"
    fi
}

# Copy kernel files from rootfs to boot image
copy_kernel_files() {
    log_info "Copying kernel files from rootfs to boot image..."
    
    # Create mount point for rootfs
    local ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs_mount"
    mkdir -p "$ROOTFS_MOUNT_DIR"
    
    # Mount rootfs image
    if ! sudo mount -o loop "$ROOTFS_IMAGE" "$ROOTFS_MOUNT_DIR"; then
        log_error "Failed to mount rootfs image for file copying"
        return 1
    fi
    
    # Create necessary directories in boot image
    sudo mkdir -p "$MOUNT_DIR/dtbs"
    
    # Copy device tree binaries
    if [[ -d "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" ]]; then
        sudo cp -r "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" "$MOUNT_DIR/dtbs/"
        log_success "Device tree binaries copied"
    else
        log_warning "Device tree binaries not found"
    fi
    
    # Copy kernel config
    local config_files=$(find "$ROOTFS_MOUNT_DIR/boot" -name "config-*" 2>/dev/null || true)
    if [[ -n "$config_files" ]]; then
        sudo cp "$config_files" "$MOUNT_DIR/" 2>/dev/null || true
        log_success "Kernel config copied"
    else
        log_warning "Kernel config not found"
    fi
    
    # Copy initrd image
    local initrd_files=$(find "$ROOTFS_MOUNT_DIR/boot" -name "initrd.img-*" 2>/dev/null || true)
    if [[ -n "$initrd_files" ]]; then
        sudo cp "$initrd_files" "$MOUNT_DIR/initramfs" 2>/dev/null || true
        log_success "Initrd image copied"
    else
        log_error "Initrd image not found - this is required"
        sudo umount "$ROOTFS_MOUNT_DIR"
        return 1
    fi
    
    # Copy vmlinuz
    local vmlinuz_files=$(find "$ROOTFS_MOUNT_DIR/boot" -name "vmlinuz-*" 2>/dev/null || true)
    if [[ -n "$vmlinuz_files" ]]; then
        sudo cp "$vmlinuz_files" "$MOUNT_DIR/linux.efi" 2>/dev/null || true
        log_success "Vmlinuz copied"
    else
        log_error "Vmlinuz not found - this is required"
        sudo umount "$ROOTFS_MOUNT_DIR"
        return 1
    fi
    
    # Unmount rootfs
    sudo umount "$ROOTFS_MOUNT_DIR"
    
    log_success "Kernel files copied successfully"
}

# Unmount boot image
unmount_boot_image() {
    log_info "Unmounting boot image..."
    
    if sudo umount "$MOUNT_DIR"; then
        log_success "Boot image unmounted successfully"
    else
        log_error "Failed to unmount boot image"
    fi
}

# Save boot image
save_boot_image() {
    local boot_file="$1"
    
    log_info "Saving boot image to: $OUTPUT_FILE"
    
    if cp "$boot_file" "$OUTPUT_FILE"; then
        local size=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
        log_success "Boot image saved: $OUTPUT_FILE (size: $size bytes)"
    else
        log_error "Failed to save boot image"
    fi
}

# Main function
main() {
    log_info "Starting boot image creation process..."
    
    # Parse arguments
    parse_arguments "$@"
    
    # Validate arguments
    validate_arguments
    
    log_info "Parameters:"
    log_info "  Kernel version: $KERNEL_VERSION"
    log_info "  Distribution: $DISTRIBUTION"
    log_info "  Rootfs image: $ROOTFS_IMAGE"
    log_info "  Output file: $OUTPUT_FILE"
    
    # Download boot image
    local boot_file=$(download_boot_image)
    
    # Mount boot image
    mount_boot_image "$boot_file"
    
    # Copy kernel files
    copy_kernel_files
    
    # Unmount boot image
    unmount_boot_image
    
    # Save boot image
    save_boot_image "$boot_file"
    
    log_success "Boot image creation completed successfully!"
    log_info "Output file: $OUTPUT_FILE"
}

# Run main function
main "$@"