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
    
    if mountpoint -q "$ROOTFS_MOUNT_DIR" 2>/dev/null; then
        sudo umount "$ROOTFS_MOUNT_DIR" 2>/dev/null || true
    fi
    
    # Remove temporary directories
    rm -rf "$MOUNT_DIR" "$ROOTFS_MOUNT_DIR" "$TEMP_DIR" 2>/dev/null || true
    
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
    ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs-mount"
    mkdir -p "$MOUNT_DIR" "$ROOTFS_MOUNT_DIR"
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
    
    # First, try to setup loop device manually
    local loop_dev=$(sudo losetup --find --show -P "$boot_file" 2>/dev/null)
    if [[ -n "$loop_dev" ]]; then
        # Try to mount the first partition
        if [[ -b "${loop_dev}p1" ]]; then
            sudo mount "${loop_dev}p1" "$MOUNT_DIR" || {
                log_warning "Failed to mount partition, trying to format..."
                sudo mkfs.fat -F32 "${loop_dev}p1"
                sudo mount "${loop_dev}p1" "$MOUNT_DIR" || {
                    sudo losetup -d "$loop_dev"
                    log_error "Failed to mount boot image after formatting"
                    return 1
                }
            }
        else
            # No partitions found, try to mount the entire device
            sudo mount "$loop_dev" "$MOUNT_DIR" || {
                log_warning "No partitions found, creating new partition..."
                sudo mkfs.fat -F32 "$loop_dev"
                sudo mount "$loop_dev" "$MOUNT_DIR" || {
                    sudo losetup -d "$loop_dev"
                    log_error "Failed to mount boot image"
                    return 1
                }
            }
        fi
    else
        # Fallback to direct mount
        sudo mount -o loop "$boot_file" "$MOUNT_DIR" || {
            log_error "Failed to mount boot image"
            return 1
        }
    fi
    
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

# Copy kernel files from rootfs to boot image
copy_kernel_files() {
    sudo mount -o loop "$ROOTFS_IMAGE" "$ROOTFS_MOUNT_DIR" || {
        log_error "Failed to mount rootfs image"
        return 1
    }
    
    sudo mkdir -p "$MOUNT_DIR/dtbs"
    
    # Copy device tree binaries
    [ -d "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" ] && sudo cp -r "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" "$MOUNT_DIR/dtbs/"
    
    # Copy kernel config
    local config_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "config-*" | head -1)
    [[ -n "$config_file" ]] && sudo cp "$config_file" "$MOUNT_DIR/"
    
    # Copy initrd image
    local initrd_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "initrd.img-*" | head -1)
    [[ -n "$initrd_file" ]] && sudo cp "$initrd_file" "$MOUNT_DIR/initramfs" || {
        log_error "Initrd image not found"
        sudo umount "$ROOTFS_MOUNT_DIR"
        return 1
    }
    
    # Copy vmlinuz
    local vmlinuz_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "vmlinuz-*" | head -1)
    [[ -n "$vmlinuz_file" ]] && sudo cp "$vmlinuz_file" "$MOUNT_DIR/linux.efi" || {
        log_error "Vmlinuz not found"
        sudo umount "$ROOTFS_MOUNT_DIR"
        return 1
    }
    
    sudo umount "$ROOTFS_MOUNT_DIR"
}

# Update boot loader configuration
update_boot_config() {
    sudo mkdir -p "$MOUNT_DIR/loader/entries"
    
    sudo tee "$MOUNT_DIR/loader/entries/ubuntu.conf" > /dev/null << EOF
title  Ubuntu
sort-key ubuntu
linux   linux.efi
initrd  initramfs

options console=tty0 loglevel=3 splash root=UUID=$ROOTFS_UUID rw
EOF
}

# Verify boot image contents
verify_boot_image() {
    [[ ! -f "$MOUNT_DIR/linux.efi" ]] && log_error "linux.efi not found" && return 1
    [[ ! -f "$MOUNT_DIR/initramfs" ]] && log_error "initramfs not found" && return 1
    [[ ! -f "$MOUNT_DIR/loader/entries/ubuntu.conf" ]] && log_error "Boot configuration not found" && return 1
}

# Unmount and save boot image
finalize_boot_image() {
    local original_boot="$1"
    sudo umount "$MOUNT_DIR"
    cp "$original_boot" "$OUTPUT_FILE"
}

# Main function
main() {
    parse_arguments "$@"
    validate_arguments
    
    handle_rootfs_file
    extract_rootfs_uuid
    
    if [[ "$DRY_RUN" == true ]]; then
        echo "Rootfs UUID: $ROOTFS_UUID"
        exit 0
    fi
    
    local boot_file=$(download_boot_image)
    mount_boot_image "$boot_file"
    copy_kernel_files
    update_boot_config
    verify_boot_image
    finalize_boot_image "$boot_file"
}

# ----------------------------- 
# Script execution
# ----------------------------- 
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi