#!/bin/bash

# Boot image creation script for Xiaomi K20 Pro (Raphael)
# Simplified version based on working example

set -e  # Exit on any error

# 加载统一日志格式库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/logging-utils.sh" ]; then
    source "${SCRIPT_DIR}/logging-utils.sh"
else
    echo "[ERROR] 日志库文件 logging-utils.sh 未找到"
    exit 1
fi

# 初始化日志系统
init_logging

# 执行命令并简化日志输出，仅在失败时显示完整日志
execute_quiet() {
    local cmd="$1"
    local description="$2"
    execute_command "$cmd" "$description" "false" || {
        log_error "命令执行失败: $description"
        return 1
    }
}

# Cleanup function
cleanup() {
    log_info "Cleaning up..."
    
    # Unmount if mounted
    if mountpoint -q "$BOOT_MOUNT_DIR" 2>/dev/null; then
        sudo umount "$BOOT_MOUNT_DIR" 2>/dev/null || log_warning "Failed to unmount $BOOT_MOUNT_DIR"
    fi
    
    if mountpoint -q "$ROOTFS_MOUNT_DIR" 2>/dev/null; then
        sudo umount "$ROOTFS_MOUNT_DIR" 2>/dev/null || log_warning "Failed to unmount $ROOTFS_MOUNT_DIR"
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
    log_title "🚀 Building boot image..."
    
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
    
    log_title "📋 Boot image build parameters:"
    log_info "   - Kernel version: $KERNEL_VERSION"
    log_info "   - Distribution: $DISTRIBUTION"
    log_info "   - Rootfs image: $ROOTFS_IMAGE"
    log_info "   - Output: $OUTPUT_FILE"
    
    # Create temporary directories
    TEMP_DIR=$(mktemp -d)
    BOOT_MOUNT_DIR="$TEMP_DIR/boot_tmp"
    ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs_mount"
    execute_quiet "mkdir -p '$BOOT_MOUNT_DIR' '$ROOTFS_MOUNT_DIR'" "Creating mount directories"
    
    log_success "Temporary directories created"
    
    # Step 1: Download boot image
    log_step_start "📥 Downloading boot image"
    
    BOOT_SOURCE_URL="https://github.com/cuicanmx/ubuntu-xiaomi-raphael/releases/download/xiaomi-k20pro-boot/xiaomi-k20pro-boot.img"
    BOOT_FILE="$TEMP_DIR/original-boot.img"
    
    execute_quiet "wget -O '$BOOT_FILE' '$BOOT_SOURCE_URL'" "Downloading original boot image"
    
    BOOT_SIZE=$(stat -c%s "$BOOT_FILE" 2>/dev/null || stat -f%z "$BOOT_FILE" 2>/dev/null)
    if [[ $BOOT_SIZE -eq 0 ]]; then
        log_error "Downloaded boot image is empty (0 bytes)"
    fi
    
    log_step_complete "Boot image downloaded (size: $BOOT_SIZE bytes)"
    
    # Step 2: Mount boot image
    log_step_start "🔗 Mounting boot image"
    
    execute_quiet "sudo mount -o loop '$BOOT_FILE' '$BOOT_MOUNT_DIR'" "Mounting boot image"
    
    log_step_complete "Boot image mounted successfully"
    log_info "Boot image contents (key files only):"
    ls -la "$BOOT_MOUNT_DIR/" | grep -E "(total|drwx|linux|initramfs|config|dtb)"  # 只显示关键文件
    
    # Step 3: Mount rootfs image
    log_step_start "🔗 Mounting rootfs image"
    
    execute_quiet "sudo mount -o loop '$ROOTFS_IMAGE' '$ROOTFS_MOUNT_DIR'" "Mounting rootfs image"
    
    log_step_complete "Rootfs image mounted successfully"
    
    # Step 4: Copy kernel files
    log_step_start "📂 Copying kernel files"
    
    # Create necessary directories
    execute_quiet "sudo mkdir -p '$BOOT_MOUNT_DIR/dtbs'" "Creating dtbs directory"
    
    # Copy device tree binaries (使用稳健的通配符处理)
    log_info "Copying device tree files..."
    set -- $ROOTFS_MOUNT_DIR/boot/dtb-*
    if [ $# -eq 0 ]; then
        # 检查dtbs目录
        if [ -d "$ROOTFS_MOUNT_DIR/boot/dtbs" ]; then
            execute_command "sudo cp -r \"$ROOTFS_MOUNT_DIR/boot/dtbs\"/* \"$BOOT_MOUNT_DIR/\"" "Copying dtbs directory" "false"
            log_success "Device tree files copied from dtbs directory"
        else
            log_warning "No dtb files found in rootfs/boot/"
        fi
    else
        # 复制第一个匹配的dtb文件到boot根目录
        execute_command "sudo cp \"$1\" $BOOT_MOUNT_DIR/" "Copying dtb file" "false"
        log_success "Device tree file copied"
    fi
    
    # Copy initrd image (使用稳健的通配符处理)
    log_info "Copying initrd image..."
    set -- $ROOTFS_MOUNT_DIR/boot/initrd.img-*
    if [ $# -eq 0 ]; then
        log_error "Initrd image not found at expected path: $ROOTFS_MOUNT_DIR/boot/initrd.img-*"
        exit 1
    fi
    execute_command "sudo cp \"$1\" $BOOT_MOUNT_DIR/initramfs" "Copying initrd image" "false"
    
    # Copy vmlinuz (使用稳健的通配符处理)
    log_info "Copying kernel image..."
    set -- $ROOTFS_MOUNT_DIR/boot/vmlinuz-*
    if [ $# -eq 0 ]; then
        log_error "Kernel image not found at expected path: $ROOTFS_MOUNT_DIR/boot/vmlinuz-*"
        exit 1
    fi
    execute_command "sudo cp \"$1\" $BOOT_MOUNT_DIR/linux.efi" "Copying kernel image" "false"
    
    # Copy kernel config (如果存在)
    log_info "Copying kernel config..."
    set -- $ROOTFS_MOUNT_DIR/boot/config-*
    if [ $# -eq 0 ]; then
        log_warning "Kernel config not found at expected path: $ROOTFS_MOUNT_DIR/boot/config-*"
    else
        execute_command "sudo cp \"$1\" $BOOT_MOUNT_DIR/" "Copying kernel config" "false"
        log_success "Kernel config copied"
    fi
    
    log_info "Displaying boot directory contents for verification:"
    ls -la "$ROOTFS_MOUNT_DIR/boot/"
    
    log_step_complete "Kernel files copied successfully"
    
    # Step 5: Unmount images
    log_step_start "🔓 Unmounting images"
    
    execute_quiet "sudo umount '$ROOTFS_MOUNT_DIR'" "Unmounting rootfs image"
    log_success "Rootfs image unmounted"
    
    execute_quiet "sudo umount '$BOOT_MOUNT_DIR'" "Unmounting boot image"
    log_success "Boot image unmounted"
    
    log_step_complete "Images unmounted successfully"
    
    # Step 6: Save boot image
    log_step_start "💾 Saving boot image"
    
    execute_quiet "cp '$BOOT_FILE' '$OUTPUT_FILE'" "Saving boot image"
    
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
    log_step_complete "Boot image saved: $OUTPUT_FILE (size: $OUTPUT_SIZE bytes)"
    
    # Step 7: Cleanup
    cleanup
    
    log_success "✅ Boot image creation completed successfully!"
    log_info "📁 Output file: $OUTPUT_FILE"
}

# Run main function
main "$@"