#!/bin/bash

set -e  # Exit on any error

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

# Simple logging functions
log_info() {
    echo "[INFO] $*"
}

log_error() {
    echo "[ERROR] $*" >&2
    exit 1
}

log_success() {
    echo "[SUCCESS] $*"
}

# Main function
main() {
    echo "🚀 Building boot image..."
    
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
    
    echo "📋 Boot image build parameters:"
    echo "   - Kernel version: $KERNEL_VERSION"
    echo "   - Distribution: $DISTRIBUTION"
    echo "   - Rootfs image: $ROOTFS_IMAGE"
    echo "   - Output: $OUTPUT_FILE"
    
    # Create temporary directories
    TEMP_DIR=$(mktemp -d)
    BOOT_MOUNT_DIR="$TEMP_DIR/boot_tmp"
    ROOTFS_MOUNT_DIR="$TEMP_DIR/rootfs_mount"
    mkdir -p "$BOOT_MOUNT_DIR" "$ROOTFS_MOUNT_DIR"
    
    # Cleanup function
    cleanup() {
        local exit_code=$?
        echo "Cleaning up..."
        
        # Unmount if mounted (silently ignore errors)
        if mountpoint -q "$BOOT_MOUNT_DIR" 2>/dev/null; then
            sudo umount "$BOOT_MOUNT_DIR" 2>/dev/null || true
        fi
        
        if mountpoint -q "$ROOTFS_MOUNT_DIR" 2>/dev/null; then
            sudo umount "$ROOTFS_MOUNT_DIR" 2>/dev/null || true
        fi
        
        # Remove temporary directories (silently ignore errors)
        rm -rf "$BOOT_MOUNT_DIR" 2>/dev/null || true
        rm -rf "$ROOTFS_MOUNT_DIR" 2>/dev/null || true
        rm -rf "$TEMP_DIR" 2>/dev/null || true
        
        echo "Cleanup completed"
        return $exit_code
    }
    
    trap cleanup EXIT
    
    # Step 1: Download boot image
    echo "📥 Downloading boot image"
    
    BOOT_SOURCE_URL="https://github.com/cuicanmx/ubuntu-xiaomi-raphael/releases/download/xiaomi-k20pro-boot/xiaomi-k20pro-boot.img"
    BOOT_FILE="$TEMP_DIR/original-boot.img"
    
    wget -O "$BOOT_FILE" "$BOOT_SOURCE_URL"
    
    BOOT_SIZE=$(stat -c%s "$BOOT_FILE" 2>/dev/null || stat -f%z "$BOOT_FILE" 2>/dev/null)
    if [[ $BOOT_SIZE -eq 0 ]]; then
        log_error "Downloaded boot image is empty (0 bytes)"
    fi
    
    echo "Boot image downloaded (size: $BOOT_SIZE bytes)"
    
    # Step 2: Mount boot image
    echo "🔗 Mounting boot image"
    
    sudo mount -o loop "$BOOT_FILE" "$BOOT_MOUNT_DIR"
    
    echo "Boot image mounted successfully"
    echo "Boot image contents (key files only):"
    ls -la "$BOOT_MOUNT_DIR/" | grep -E "(total|drwx|linux|initramfs|config|dtb)"  # 只显示关键文件
    
    # Step 3: Mount rootfs image
    echo "🔗 Mounting rootfs image"
    
    sudo mount -o loop "$ROOTFS_IMAGE" "$ROOTFS_MOUNT_DIR"
    
    echo "Rootfs image mounted successfully"
    
    # Step 4: Copy kernel files
    echo "📂 Copying kernel files"
    
    # Copy initrd image
    echo "Copying initrd image..."
    set -- $ROOTFS_MOUNT_DIR/boot/initrd.img-*
    if [ $# -eq 0 ]; then
        log_error "Initrd image not found at expected path: $ROOTFS_MOUNT_DIR/boot/initrd.img-*"
    fi
    sudo cp "$1" "$BOOT_MOUNT_DIR/initramfs"
    
    # Copy vmlinuz
    echo "Copying kernel image..."
    set -- $ROOTFS_MOUNT_DIR/boot/vmlinuz-*
    if [ $# -eq 0 ]; then
        log_error "Kernel image not found at expected path: $ROOTFS_MOUNT_DIR/boot/vmlinuz-*"
    fi
    sudo cp "$1" "$BOOT_MOUNT_DIR/linux.efi"
    
    echo "Displaying boot directory contents for verification:"
    ls -la "$ROOTFS_MOUNT_DIR/boot/"
    
    echo "Kernel files copied successfully"
    
    # Step 5: Update boot configuration with rootfs UUID
    echo "🔄 Updating boot configuration"
    
    BOOT_CONFIG_DIR="$BOOT_MOUNT_DIR/loader/entries"
    BOOT_CONFIG_FILE="$BOOT_CONFIG_DIR/ubuntu.conf"
    
    if [ -f "$BOOT_CONFIG_FILE" ]; then
        echo "✅ Found: $BOOT_CONFIG_FILE"
        
        # Get rootfs image UUID
        echo "Extracting UUID from rootfs image: $ROOTFS_IMAGE"
        ROOTFS_UUID=$(sudo blkid -s UUID -o value "$ROOTFS_IMAGE")
        
        if [ -n "$ROOTFS_UUID" ]; then
            echo "Rootfs UUID: $ROOTFS_UUID"
            
            # Update UUID in boot configuration
            echo "Updating UUID in boot configuration..."
            sudo sed -i "s/root=UUID=[a-f0-9\-]*/root=UUID=$ROOTFS_UUID/g" "$BOOT_CONFIG_FILE"
            
            # Verify the update
            echo "✅ Updated boot entry:"
            cat "$BOOT_CONFIG_FILE"
            
            # Check kernel version in boot entry
            if grep -q "$KERNEL_VERSION" "$BOOT_CONFIG_FILE"; then
                echo "✅ Kernel version in boot entry matches expected: $KERNEL_VERSION"
            else
                echo "⚠️ Kernel version in boot entry does not match expected: $KERNEL_VERSION"
                grep -E "title|sort-key|linux|initrd|options" "$BOOT_CONFIG_FILE"
            fi
        else
            echo "⚠️ Could not extract UUID from rootfs image"
            echo "Boot configuration will use existing UUID"
        fi
    else
        echo "⚠️ Boot configuration file not found: $BOOT_CONFIG_FILE"
        echo "Creating default boot configuration..."
        
        # Create directory if it doesn't exist
        sudo mkdir -p "$BOOT_CONFIG_DIR"
        
        # Get rootfs UUID
        ROOTFS_UUID=$(sudo blkid -s UUID -o value "$ROOTFS_IMAGE" 2>/dev/null)
        
        # Create default boot configuration
        sudo cat > /tmp/ubuntu.conf.tmp << EOF
title	 Ubuntu
sort-key ubuntu
linux	 linux.efi
initrd	 initramfs

options console=tty0 loglevel=3 splash root=UUID=${ROOTFS_UUID:-ee8d3593-59b1-480e-a3b6-4fefb17ee7d8} rw
EOF
        
        sudo cp /tmp/ubuntu.conf.tmp "$BOOT_CONFIG_FILE"
        rm -f /tmp/ubuntu.conf.tmp
        
        echo "✅ Created default boot configuration"
        cat "$BOOT_CONFIG_FILE"
    fi
    
    echo "Boot configuration updated"
    
    # Step 6: Unmount images
    echo "🔓 Unmounting images"
    
    sudo umount "$ROOTFS_MOUNT_DIR"
    echo "Rootfs image unmounted"
    
    sudo umount "$BOOT_MOUNT_DIR"
    echo "Boot image unmounted"
    
    echo "Images unmounted successfully"
    
    # Step 7: Save boot image
    echo "💾 Saving boot image"
    
    cp "$BOOT_FILE" "$OUTPUT_FILE"
    
    OUTPUT_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || stat -f%z "$OUTPUT_FILE" 2>/dev/null)
    echo "Boot image saved: $OUTPUT_FILE (size: $OUTPUT_SIZE bytes)"
    
    # Cleanup will be triggered by trap
    echo "✅ Boot image creation completed successfully!"
    echo "📁 Output file: $OUTPUT_FILE"
    return 0
}

# Run main function
main "$@"
