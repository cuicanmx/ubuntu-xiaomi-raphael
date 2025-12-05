#!/bin/bash

# Boot image creation script for Xiaomi K20 Pro (Raphael)
# Enhanced version with complete validation and error handling

set -e  # Exit on any error

# Load configuration
source "build-config.sh"

# Logging functions with detailed output
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"; }
log_info() { log "INFO: $1"; }
log_success() { log "SUCCESS: $1"; }
log_warning() { log "WARNING: $1"; }
log_error() { log "ERROR: $1"; exit 1; }
log_debug() { [[ "$DEBUG" == "true" ]] && log "DEBUG: $1"; }

# Function to check file existence and size
check_file() {
    local file="$1"
    local description="$2"
    
    if [[ ! -f "$file" ]]; then
        log_error "$description not found: $file"
        return 1
    fi
    
    local size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    if [[ $size -eq 0 ]]; then
        log_error "$description is empty (0 bytes): $file"
        return 1
    fi
    
    log_success "$description verified: $file (size: $size bytes)"
    return 0
}

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary resources..."
    
    # Unmount mount points if they exist
    if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
        log_debug "Unmounting $MOUNT_DIR"
        sudo umount "$MOUNT_DIR" 2>/dev/null || log_warning "Failed to unmount $MOUNT_DIR"
    fi
    
    if mountpoint -q "$ROOTFS_MOUNT_DIR" 2>/dev/null; then
        log_debug "Unmounting $ROOTFS_MOUNT_DIR"
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
    log_info "Parsing command line arguments..."
    
    # Set defaults
    KERNEL_VERSION="${KERNEL_VERSION:-${KERNEL_VERSION_DEFAULT}}"
    DISTRIBUTION="${DISTRIBUTION:-${DISTRIBUTION_DEFAULT:-ubuntu}}"
    ROOTFS_IMAGE="${ROOTFS_IMAGE:-}"
    OUTPUT_FILE="${OUTPUT_FILE:-}"
    DRY_RUN=false
    DEBUG=false
    
    # Check if no arguments provided
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -k|--kernel-version)
                KERNEL_VERSION="$2"
                log_debug "Kernel version set to: $KERNEL_VERSION"
                shift 2
                ;;
            -d|--distribution)
                DISTRIBUTION="$2"
                log_debug "Distribution set to: $DISTRIBUTION"
                shift 2
                ;;
            -r|--rootfs-image)
                ROOTFS_IMAGE="$2"
                log_debug "Rootfs image set to: $ROOTFS_IMAGE"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                log_debug "Output file set to: $OUTPUT_FILE"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                log_debug "Dry run mode enabled"
                shift 1
                ;;
            --debug)
                DEBUG=true
                log_debug "Debug mode enabled"
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
    --debug                         Enable debug output
    -h, --help                      Show this help message

EXAMPLES:
    $0 -k 6.18 -d ubuntu -r root-ubuntu-6.18.img
    $0 --kernel-version 6.18 --distribution ubuntu --output xiaomi-k20pro-boot.img
    $0 --kernel-version 6.18 --rootfs-image root-ubuntu-6.18.img --dry-run

EOF
}

# Validate arguments
validate_arguments() {
    log_info "Validating arguments..."
    
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
    ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs-mount"
    mkdir -p "$MOUNT_DIR" "$ROOTFS_MOUNT_DIR"
    
    log_debug "TEMP_DIR: $TEMP_DIR"
    log_debug "MOUNT_DIR: $MOUNT_DIR"
    log_debug "ROOTFS_MOUNT_DIR: $ROOTFS_MOUNT_DIR"
    
    log_success "Arguments validated successfully"
}

# ----------------------------- 
# Download boot image with validation
# ----------------------------- 
download_boot_image() {
    local boot_file="$TEMP_DIR/original-boot.img"
    
    # 使用固定的GitHub Releases URL
    local BOOT_SOURCE_URL="https://github.com/GengWei1997/kernel-deb/releases/download/v1.0.0/xiaomi-k20pro-boot.img"
    
    log_info "Downloading boot image from: $BOOT_SOURCE_URL"
    
    # Download with progress and error handling
    if wget --progress=bar:force -O "$boot_file" "$BOOT_SOURCE_URL" 2>&1; then
        local size=$(stat -c%s "$boot_file" 2>/dev/null || stat -f%z "$boot_file" 2>/dev/null)
        log_success "Boot image downloaded successfully: $boot_file (size: $size bytes)"
        
        # Verify file integrity
        if [[ $size -eq 0 ]]; then
            log_error "Downloaded boot image is empty (0 bytes)"
            return 1
        fi
        
        # Check if file is a valid image
        if file "$boot_file" | grep -q "data"; then
            log_warning "Boot image appears to be raw data, checking if it's mountable..."
        fi
        
        echo "$boot_file"
    else
        log_error "Failed to download boot image from $BOOT_SOURCE_URL"
        return 1
    fi
}

# ----------------------------- 
# Mount boot image with enhanced error handling
# ----------------------------- 
mount_boot_image() {
    local boot_file="$1"
    
    log_info "Mounting boot image: $boot_file"
    
    # First, check if file exists and has content
    check_file "$boot_file" "Boot image" || return 1
    
    # Try different mount methods
    local mount_success=false
    
    # Method 1: Simple loop mount
    log_debug "Attempting simple loop mount..."
    if sudo mount -o loop "$boot_file" "$MOUNT_DIR" 2>/dev/null; then
        mount_success=true
        log_success "Boot image mounted successfully using simple loop"
    else
        log_warning "Simple loop mount failed, trying manual loop setup..."
        
        # Method 2: Manual loop device setup
        local loop_dev=$(sudo losetup --find --show -P "$boot_file" 2>/dev/null)
        if [[ -n "$loop_dev" ]]; then
            log_debug "Loop device created: $loop_dev"
            
            # Try to mount partitions
            if [[ -b "${loop_dev}p1" ]]; then
                if sudo mount "${loop_dev}p1" "$MOUNT_DIR" 2>/dev/null; then
                    mount_success=true
                    log_success "Boot image mounted successfully using partition p1"
                else
                    log_warning "Failed to mount partition p1"
                fi
            fi
            
            # If partition mount failed, try mounting the whole device
            if [[ "$mount_success" == "false" ]]; then
                if sudo mount "$loop_dev" "$MOUNT_DIR" 2>/dev/null; then
                    mount_success=true
                    log_success "Boot image mounted successfully using whole device"
                else
                    log_warning "Failed to mount whole device"
                fi
            fi
            
            # Cleanup loop device if mount failed
            if [[ "$mount_success" == "false" ]]; then
                sudo losetup -d "$loop_dev" 2>/dev/null || true
            fi
        fi
    fi
    
    if [[ "$mount_success" == "false" ]]; then
        log_error "All mount attempts failed. The boot image may be corrupted or in an unsupported format."
        log_info "File info: $(file "$boot_file")"
        return 1
    fi
    
    # Show boot image contents
    log_info "Boot image contents:"
    ls -la "$MOUNT_DIR/"
    
    return 0
}

# ----------------------------- 
# Handle rootfs file
# ----------------------------- 
handle_rootfs_file() {
    log_info "Handling rootfs file: $ROOTFS_IMAGE"
    
    if [[ -n "$ROOTFS_IMAGE" ]]; then
        check_file "$ROOTFS_IMAGE" "Rootfs image" || return 1
        log_success "Rootfs image verified: $ROOTFS_IMAGE"
    else
        log_error "No rootfs file specified"
        return 1
    fi
}

# ----------------------------- 
# Extract rootfs UUID
# ----------------------------- 
extract_rootfs_uuid() {
    log_info "Extracting UUID from rootfs image: $ROOTFS_IMAGE"
    
    check_file "$ROOTFS_IMAGE" "Rootfs image" || return 1
    
    # Extract UUID using blkid
    ROOTFS_UUID=$(sudo blkid -s UUID -o value "$ROOTFS_IMAGE" 2>/dev/null)
    
    if [[ -z "$ROOTFS_UUID" ]]; then
        log_error "Failed to extract UUID from rootfs image"
        log_info "Trying alternative methods..."
        
        # Alternative method: try to mount and check /etc/fstab
        if sudo mount -o loop "$ROOTFS_IMAGE" "$ROOTFS_MOUNT_DIR" 2>/dev/null; then
            if [[ -f "$ROOTFS_MOUNT_DIR/etc/fstab" ]]; then
                ROOTFS_UUID=$(grep -o 'UUID=[a-f0-9-]*' "$ROOTFS_MOUNT_DIR/etc/fstab" | head -1 | cut -d= -f2)
                sudo umount "$ROOTFS_MOUNT_DIR"
            fi
        fi
        
        if [[ -z "$ROOTFS_UUID" ]]; then
            log_error "Still unable to extract UUID. The rootfs image may be corrupted."
            return 1
        fi
    fi
    
    log_success "Rootfs UUID extracted: $ROOTFS_UUID"
    return 0
}

# ----------------------------- 
# Copy kernel files from rootfs to boot image
# ----------------------------- 
copy_kernel_files() {
    log_info "Copying kernel files from rootfs to boot image..."
    
    # Mount rootfs image
    if ! sudo mount -o loop "$ROOTFS_IMAGE" "$ROOTFS_MOUNT_DIR" 2>/dev/null; then
        log_error "Failed to mount rootfs image for file copying"
        return 1
    fi
    
    # Create directories in boot image
    sudo mkdir -p "$MOUNT_DIR/dtbs" "$MOUNT_DIR/loader/entries"
    
    local files_copied=0
    local files_missing=0
    
    # Copy device tree binaries
    if [[ -d "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" ]]; then
        sudo cp -r "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" "$MOUNT_DIR/dtbs/"
        ((files_copied++))
        log_success "Device tree binaries copied"
    else
        ((files_missing++))
        log_warning "Device tree binaries not found"
    fi
    
    # Copy kernel config
    local config_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "config-*" | head -1)
    if [[ -n "$config_file" ]]; then
        sudo cp "$config_file" "$MOUNT_DIR/"
        ((files_copied++))
        log_success "Kernel config copied: $(basename "$config_file")"
    else
        ((files_missing++))
        log_warning "Kernel config not found"
    fi
    
    # Copy initrd image
    local initrd_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "initrd.img-*" | head -1)
    if [[ -n "$initrd_file" ]]; then
        sudo cp "$initrd_file" "$MOUNT_DIR/initramfs"
        ((files_copied++))
        log_success "Initrd image copied: $(basename "$initrd_file")"
    else
        log_error "Initrd image not found - this is required"
        sudo umount "$ROOTFS_MOUNT_DIR"
        return 1
    fi
    
    # Copy vmlinuz
    local vmlinuz_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "vmlinuz-*" | head -1)
    if [[ -n "$vmlinuz_file" ]]; then
        sudo cp "$vmlinuz_file" "$MOUNT_DIR/linux.efi"
        ((files_copied++))
        log_success "Vmlinuz copied: $(basename "$vmlinuz_file")"
    else
        log_error "Vmlinuz not found - this is required"
        sudo umount "$ROOTFS_MOUNT_DIR"
        return 1
    fi
    
    sudo umount "$ROOTFS_MOUNT_DIR"
    
    log_success "File copy completed: $files_copied files copied, $files_missing files missing"
    return 0
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
    
    log_success "Boot configuration updated with UUID: $ROOTFS_UUID"
}

# ----------------------------- 
# Verify boot image contents
# ----------------------------- 
verify_boot_image() {
    log_info "Verifying boot image contents..."
    
    local verification_passed=true
    
    if [[ ! -f "$MOUNT_DIR/linux.efi" ]]; then
        log_error "linux.efi not found"
        verification_passed=false
    fi
    
    if [[ ! -f "$MOUNT_DIR/initramfs" ]]; then
        log_error "initramfs not found"
        verification_passed=false
    fi
    
    if [[ ! -f "$MOUNT_DIR/loader/entries/ubuntu.conf" ]]; then
        log_error "Boot configuration not found"
        verification_passed=false
    fi
    
    if [[ "$verification_passed" == "true" ]]; then
        log_success "Boot image verification passed"
        return 0
    else
        log_error "Boot image verification failed"
        return 1
    fi
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
    
    # Verify output file
    check_file "$OUTPUT_FILE" "Output boot image" || return 1
    
    log_success "Boot image creation completed: $OUTPUT_FILE"
}

# ----------------------------- 
# Main function
# ----------------------------- 
main() {
    log_info "Starting boot image creation process..."
    
    parse_arguments "$@"
    validate_arguments
    
    log_info "Starting boot image creation for $DISTRIBUTION (Kernel $KERNEL_VERSION)"
    log_info "Rootfs image: $ROOTFS_IMAGE"
    log_info "Output file: $OUTPUT_FILE"
    
    # Handle rootfs file
    handle_rootfs_file
    
    # Extract rootfs UUID
    extract_rootfs_uuid
    
    if [[ "$DRY_RUN" == "true" ]]; then
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
    
    log_success "Boot image creation process completed successfully!"
    log_info "Output file: $OUTPUT_FILE"
    log_info "Rootfs UUID: $ROOTFS_UUID"
}

# Run main function
main "$@"