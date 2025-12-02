#!/bin/bash

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
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

# 清理函数
cleanup() {
    log_info "Cleaning up..."
    
    # 卸载挂载点
    if mountpoint -q "$MOUNT_DIR"; then
        sudo umount "$MOUNT_DIR" 2>/dev/null || true
    fi
    
    if mountpoint -q "$ROOTFS_MOUNT_DIR"; then
        sudo umount "$ROOTFS_MOUNT_DIR" 2>/dev/null || true
    fi
    
    # 删除临时目录
    rm -rf "$MOUNT_DIR" "$ROOTFS_MOUNT_DIR" "$TEMP_DIR"
    
    log_success "Cleanup completed"
}

# 错误处理
trap cleanup EXIT

# 参数解析
parse_arguments() {
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

# 显示帮助
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Create boot image for Xiaomi K20 Pro (Raphael)

OPTIONS:
    -k, --kernel-version VERSION    Kernel version (e.g., 6.18)
    -d, --distribution DISTRO       Distribution (ubuntu/armbian)
    -b, --boot-source URL           Boot image source URL
    -r, --rootfs-image FILE         Rootfs image file
    -o, --output FILE               Output boot image file
    -h, --help                      Show this help message

EXAMPLES:
    $0 -k 6.18 -d ubuntu -r root-ubuntu-6.18.img
    $0 --kernel-version 6.18 --distribution ubuntu --output xiaomi-k20pro-boot.img

EOF
}

# 验证参数
validate_arguments() {
    if [[ -z "$KERNEL_VERSION" ]]; then
        log_error "Kernel version is required"
        show_help
        exit 1
    fi
    
    if [[ -z "$DISTRIBUTION" ]]; then
        DISTRIBUTION="ubuntu"
        log_warning "Distribution not specified, using default: $DISTRIBUTION"
    fi
    
    if [[ "$DISTRIBUTION" != "ubuntu" && "$DISTRIBUTION" != "armbian" ]]; then
        log_error "Unsupported distribution: $DISTRIBUTION"
        exit 1
    fi
    
    # 设置默认值
    if [[ -z "$BOOT_SOURCE" ]]; then
        BOOT_SOURCE="https://example.com/xiaomi-k20pro-boot.img"
        log_warning "Using default boot source: $BOOT_SOURCE"
    fi
    
    if [[ -z "$ROOTFS_IMAGE" ]]; then
        ROOTFS_IMAGE="root-${DISTRIBUTION}-${KERNEL_VERSION}.img"
        log_info "Using default rootfs image: $ROOTFS_IMAGE"
    fi
    
    if [[ -z "$OUTPUT_FILE" ]]; then
        OUTPUT_FILE="xiaomi-k20pro-boot-${DISTRIBUTION}-${KERNEL_VERSION}.img"
        log_info "Using default output: $OUTPUT_FILE"
    fi
    
    # 创建临时目录
    TEMP_DIR=$(mktemp -d)
    MOUNT_DIR="$TEMP_DIR/boot-mount"
    ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs-mount"
    
    mkdir -p "$MOUNT_DIR" "$ROOTFS_MOUNT_DIR"
}

# 下载boot镜像
download_boot_image() {
    local boot_file="$TEMP_DIR/original-boot.img"
    
    log_info "Downloading boot image from: $BOOT_SOURCE"
    
    if wget -O "$boot_file" "$BOOT_SOURCE" 2>/dev/null; then
        log_success "Boot image downloaded successfully"
        echo "$boot_file"
    else
        log_warning "Failed to download boot image, creating empty one"
        create_empty_boot_image "$boot_file"
        echo "$boot_file"
    fi
}

# 创建空的boot镜像
create_empty_boot_image() {
    local boot_file="$1"
    
    log_info "Creating empty boot image (64MB)..."
    
    # 创建空的镜像文件
    dd if=/dev/zero of="$boot_file" bs=1M count=64 status=none
    
    # 分区和格式化
    parted -s "$boot_file" mklabel gpt
    parted -s "$boot_file" mkpart primary fat32 1MiB 100%
    
    # 创建loop设备并格式化
    local loop_dev=$(sudo losetup --find --show "$boot_file")
    sudo mkfs.fat -F32 "${loop_dev}p1"
    sudo losetup -d "$loop_dev"
    
    log_success "Empty boot image created: $boot_file"
}

# 挂载boot镜像
mount_boot_image() {
    local boot_file="$1"
    
    log_info "Mounting boot image..."
    
    # 挂载boot镜像
    sudo mount -o loop "$boot_file" "$MOUNT_DIR" || {
        log_error "Failed to mount boot image"
        return 1
    }
    
    log_success "Boot image mounted at: $MOUNT_DIR"
    
    # 显示boot镜像内容
    log_info "Boot image contents:"
    ls -la "$MOUNT_DIR/"
}

# 获取rootfs UUID
extract_rootfs_uuid() {
    log_info "Extracting UUID from rootfs image: $ROOTFS_IMAGE"
    
    if [[ ! -f "$ROOTFS_IMAGE" ]]; then
        log_error "Rootfs image not found: $ROOTFS_IMAGE"
        return 1
    fi
    
    ROOTFS_UUID=$(sudo blkid -s UUID -o value "$ROOTFS_IMAGE")
    
    if [[ -z "$ROOTFS_UUID" ]]; then
        log_error "Failed to extract UUID from rootfs image"
        return 1
    fi
    
    log_success "Rootfs UUID: $ROOTFS_UUID"
}

# 挂载rootfs并复制内核文件
copy_kernel_files() {
    log_info "Mounting rootfs and copying kernel files..."
    
    # 挂载rootfs
    sudo mount -o loop "$ROOTFS_IMAGE" "$ROOTFS_MOUNT_DIR" || {
        log_error "Failed to mount rootfs image"
        return 1
    }
    
    # 查找内核文件
    local vmlinuz_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "vmlinuz-*" | head -1)
    local initrd_file=$(find "$ROOTFS_MOUNT_DIR/boot" -name "initrd.img-*" | head -1)
    
    if [[ -z "$vmlinuz_file" ]] || [[ -z "$initrd_file" ]]; then
        log_error "Kernel files not found in rootfs"
        ls -la "$ROOTFS_MOUNT_DIR/boot/"
        return 1
    fi
    
    log_info "Found kernel files:"
    echo "  - vmlinuz: $vmlinuz_file"
    echo "  - initrd: $initrd_file"
    
    # 复制到boot镜像
    sudo cp "$vmlinuz_file" "$MOUNT_DIR/linux.efi"
    sudo cp "$initrd_file" "$MOUNT_DIR/initramfs"
    
    log_success "Kernel files copied to boot image"
    
    # 卸载rootfs
    sudo umount "$ROOTFS_MOUNT_DIR"
}

# 更新boot loader配置
update_boot_config() {
    log_info "Updating boot loader configuration..."
    
    # 创建loader目录结构
    sudo mkdir -p "$MOUNT_DIR/loader/entries"
    
    # 创建Ubuntu启动配置
    sudo tee "$MOUNT_DIR/loader/entries/ubuntu.conf" > /dev/null << EOF
title  Ubuntu
sort-key ubuntu
linux   linux.efi
initrd  initramfs

options console=tty0 loglevel=3 splash root=UUID=$ROOTFS_UUID rw
EOF
    
    log_success "Boot loader configuration updated"
    
    # 显示配置内容
    log_info "Boot configuration:"
    cat "$MOUNT_DIR/loader/entries/ubuntu.conf"
}

# 验证boot镜像内容
verify_boot_image() {
    log_info "Verifying boot image contents..."
    
    # 检查关键文件
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
    
    # 显示最终内容
    log_info "Final boot image structure:"
    ls -la "$MOUNT_DIR/"
    echo "--- Loader entries ---"
    ls -la "$MOUNT_DIR/loader/entries/"
}

# 卸载并保存boot镜像
finalize_boot_image() {
    local original_boot="$1"
    
    log_info "Finalizing boot image..."
    
    # 卸载boot镜像
    sudo umount "$MOUNT_DIR"
    
    # 复制到输出文件
    cp "$original_boot" "$OUTPUT_FILE"
    
    log_success "Boot image finalized: $OUTPUT_FILE"
    
    # 显示文件信息
    ls -lh "$OUTPUT_FILE"
}

# 主函数
main() {
    log_info "Starting boot image creation for Xiaomi K20 Pro (Raphael)"
    log_info "Kernel: $KERNEL_VERSION, Distribution: $DISTRIBUTION"
    
    # 参数解析和验证
    parse_arguments "$@"
    validate_arguments
    
    # 执行构建步骤
    local boot_file=$(download_boot_image)
    mount_boot_image "$boot_file"
    extract_rootfs_uuid
    copy_kernel_files
    update_boot_config
    verify_boot_image
    finalize_boot_image "$boot_file"
    
    log_success "Boot image creation completed successfully!"
    log_info "Output file: $OUTPUT_FILE"
    log_info "RootFS UUID: $ROOTFS_UUID"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi