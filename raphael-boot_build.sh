#!/bin/bash

# Boot image creation script for Xiaomi K20 Pro (Raphael)
# Simplified version based on working example

set -e  # Exit on any error

# Simple logging
log() { echo "[$(date +'%H:%M:%S')] $1"; }
log_info() { log "INFO: $1"; }
log_success() { log "SUCCESS: $1"; }
log_error() { log "ERROR: $1"; exit 1; }

# 执行命令并简化日志输出，仅在失败时显示完整日志
execute_quiet() {
    local cmd="$1"
    local description="$2"
    log_info "$description..."
    if ! eval "$cmd" >/dev/null 2>&1; then
        log_error "Failed: $description"
        log_info "Full command: $cmd"
        eval "$cmd"  # 再次执行以显示完整错误信息
        exit 1
    fi
}

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
    execute_quiet "TEMP_DIR=$(mktemp -d)" "Creating temporary directory"
    BOOT_MOUNT_DIR="$TEMP_DIR/boot_tmp"
    ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs_mount"
    execute_quiet "mkdir -p '$BOOT_MOUNT_DIR' '$ROOTFS_MOUNT_DIR'" "Creating mount directories"
    
    log_success "Temporary directories created"
    
    # Step 1: Download boot image
    log_info "Step 1: Downloading boot image..."
    
    BOOT_SOURCE_URL="https://github.com/cuicanmx/ubuntu-xiaomi-raphael/releases/download/xiaomi-k20pro-boot/xiaomi-k20pro-boot.img"
    BOOT_FILE="$TEMP_DIR/original-boot.img"
    
    execute_quiet "wget -O '$BOOT_FILE' '$BOOT_SOURCE_URL'" "Downloading original boot image"
    
    BOOT_SIZE=$(stat -c%s "$BOOT_FILE" 2>/dev/null || stat -f%z "$BOOT_FILE" 2>/dev/null)
    if [[ $BOOT_SIZE -eq 0 ]]; then
        log_error "Downloaded boot image is empty (0 bytes)"
    fi
    
    log_success "Boot image downloaded (size: $BOOT_SIZE bytes)"
    
    # Step 2: Mount boot image
    log_info "Step 2: Mounting boot image..."
    
    execute_quiet "sudo mount -o loop '$BOOT_FILE' '$BOOT_MOUNT_DIR'" "Mounting boot image"
    
    log_success "Boot image mounted successfully"
    log_info "Boot image contents (key files only):"
    ls -la "$BOOT_MOUNT_DIR/" | grep -E "(total|drwx|linux|initramfs|config|dtb)"  # 只显示关键文件
    
    # Step 3: Mount rootfs image
    log_info "Step 3: Mounting rootfs image..."
    
    execute_quiet "sudo mount -o loop '$ROOTFS_IMAGE' '$ROOTFS_MOUNT_DIR'" "Mounting rootfs image"
    
    log_success "Rootfs image mounted successfully"
    
    # Step 4: Copy kernel files
    log_info "Step 4: Copying kernel files..."
    
    # Create necessary directories
    execute_quiet "sudo mkdir -p '$BOOT_MOUNT_DIR/dtbs'" "Creating dtbs directory"
    
    # Copy device tree binaries (exact path check)
    DEVICE_TREE_FOUND=false
    if [[ -d "$ROOTFS_MOUNT_DIR/boot/dtbs/qcom" ]]; then
        execute_quiet "sudo cp -r '$ROOTFS_MOUNT_DIR/boot/dtbs/qcom' '$BOOT_MOUNT_DIR/dtbs/'" "Copying device tree binaries from /boot/dtbs/qcom"
        log_success "Device tree binaries copied"
        DEVICE_TREE_FOUND=true
    else
        # Try alternative paths
        log "Warning: Device tree binaries not found at expected path - checking alternatives..."
        # 检查根文件系统中是否存在任何dtb文件
        DTB_FILES=($(find "$ROOTFS_MOUNT_DIR" -name "*.dtb" 2>/dev/null))
        if [ ${#DTB_FILES[@]} -gt 0 ]; then
            execute_quiet "sudo cp ${DTB_FILES[@]} '$BOOT_MOUNT_DIR/dtbs/'" "Copying all found device tree binaries"
            log_success "Device tree binaries copied from alternative locations"
            DEVICE_TREE_FOUND=true
        else
            log "Warning: Device tree binaries not found in any location"
        fi
    fi
    
    # Copy kernel config (exact pattern check)
    if ls "$ROOTFS_MOUNT_DIR/boot/config-*" 1> /dev/null 2>&1; then
        execute_quiet "sudo cp '$ROOTFS_MOUNT_DIR/boot/config-*' '$BOOT_MOUNT_DIR/' 2>/dev/null" "Copying kernel config files"
        log_success "Kernel config copied"
    else
        log "Warning: Kernel config not found"
        # 尝试在其他位置查找内核配置
        CONFIG_FILES=($(find "$ROOTFS_MOUNT_DIR" -name "config-*" 2>/dev/null))
        if [ ${#CONFIG_FILES[@]} -gt 0 ]; then
            execute_quiet "sudo cp ${CONFIG_FILES[@]} '$BOOT_MOUNT_DIR/'" "Copying kernel config from alternative location"
            log_success "Kernel config copied from alternative location"
        fi
    fi
    
    # Copy initrd image (exact pattern check)
    INITRD_FOUND=false
    if ls "$ROOTFS_MOUNT_DIR/boot/initrd.img-*" 1> /dev/null 2>&1; then
        execute_quiet "sudo cp '$ROOTFS_MOUNT_DIR/boot/initrd.img-*' '$BOOT_MOUNT_DIR/initramfs' 2>/dev/null" "Copying initrd image"
        log_success "Initrd image copied"
        INITRD_FOUND=true
    else
        # 尝试查找其他名称的Initrd镜像
        log "Warning: Initrd image not found at expected path - checking alternatives..."
        INITRD_FILES=($(find "$ROOTFS_MOUNT_DIR/boot" -name "init*" 2>/dev/null | grep -E "(initramfs|initrd)"))
        if [ ${#INITRD_FILES[@]} -gt 0 ]; then
            execute_quiet "sudo cp ${INITRD_FILES[0]} '$BOOT_MOUNT_DIR/initramfs'" "Copying initrd image from alternative location"
            log_success "Initrd image copied from alternative location"
            INITRD_FOUND=true
        else
            log_error "Initrd image not found - this is required"
        fi
    fi
    
    # Copy vmlinuz (exact pattern check)
    VMLINUZ_FOUND=false
    if ls "$ROOTFS_MOUNT_DIR/boot/vmlinuz-*" 1> /dev/null 2>&1; then
        execute_quiet "sudo cp '$ROOTFS_MOUNT_DIR/boot/vmlinuz-*' '$BOOT_MOUNT_DIR/linux.efi' 2>/dev/null" "Copying vmlinuz"
        log_success "Vmlinuz copied"
        VMLINUZ_FOUND=true
    else
        # 尝试查找其他名称的内核镜像
        log "Warning: Vmlinuz not found at expected path - checking alternatives..."
        VMLINUZ_FILES=($(find "$ROOTFS_MOUNT_DIR/boot" -name "vmlinuz*" -o -name "Image*" 2>/dev/null))
        if [ ${#VMLINUZ_FILES[@]} -gt 0 ]; then
            execute_quiet "sudo cp ${VMLINUZ_FILES[0]} '$BOOT_MOUNT_DIR/linux.efi'" "Copying kernel image from alternative location"
            log_success "Kernel image copied from alternative location"
            VMLINUZ_FOUND=true
        else
            log_error "Kernel image not found - this is required"
        fi
    fi
    
    # 检查是否找到了关键文件
    if [ "$VMLINUZ_FOUND" = false ] || [ "$INITRD_FOUND" = false ]; then
        log_error "Failed to find essential kernel files"
    fi
    
    log_info "Displaying boot directory contents for verification:"
    ls -la "$ROOTFS_MOUNT_DIR/boot/"
    
    # Step 5: Unmount images
    log_info "Step 5: Unmounting images..."
    
    execute_quiet "sudo umount '$ROOTFS_MOUNT_DIR'" "Unmounting rootfs image"
    log_success "Rootfs image unmounted"
    
    execute_quiet "sudo umount '$BOOT_MOUNT_DIR'" "Unmounting boot image"
    log_success "Boot image unmounted"
    
    # Step 6: Save boot image
    log_info "Step 6: Saving boot image..."
    
    execute_quiet "cp '$BOOT_FILE' '$OUTPUT_FILE'" "Saving boot image"
    
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
    log_success "Boot image saved: $OUTPUT_FILE (size: $OUTPUT_SIZE bytes)"
    
    # Step 7: Cleanup
    cleanup
    
    log_success "Boot image creation completed successfully!"
    log_info "Output file: $OUTPUT_FILE"
}

# Run main function
main "$@"