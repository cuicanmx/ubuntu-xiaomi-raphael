#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/build-config.sh"

ROOTFS_SIZE="6G"
DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
KERNEL_VERSION="${KERNEL_VERSION:-6.18}"
ROOTFS_IMG="root-${DISTRIBUTION}-${KERNEL_VERSION}.img"
ROOTDIR="rootdir"
VERSION="noble"
UBUNTU_VERSION="24.04.3"

log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_error() {
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

main() {
    log_info "Starting rootfs build"
    
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
    
    execute_quiet "truncate -s '$ROOTFS_SIZE' '$ROOTFS_IMG'" "Creating rootfs image"
    execute_quiet "mkfs.ext4 '$ROOTFS_IMG'" "Formatting rootfs image"
    execute_quiet "mkdir -p '$ROOTDIR'" "Creating rootdir"
    execute_quiet "mount -o loop '$ROOTFS_IMG' '$ROOTDIR'" "Mounting rootfs image"
    
    execute_quiet "wget 'https://cdimage.ubuntu.com/ubuntu-base/releases/$VERSION/release/ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz'" "Downloading Ubuntu base image"
    execute_quiet "tar xzf ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz -C '$ROOTDIR'" "Extracting Ubuntu base image" &&
    
    execute_quiet "mount --bind /dev '$ROOTDIR/dev'" "Mounting /dev"
    execute_quiet "mount --bind /dev/pts '$ROOTDIR/dev/pts'" "Mounting /dev/pts"
    execute_quiet "mount --bind /proc '$ROOTDIR/proc'" "Mounting /proc"
    execute_quiet "mount --bind /sys '$ROOTDIR/sys'" "Mounting /sys"
    
    execute_quiet "echo 'nameserver 1.1.1.1' | tee '$ROOTDIR/etc/resolv.conf'" "Setting DNS"
    execute_quiet "echo 'xiaomi-raphael' | tee '$ROOTDIR/etc/hostname'" "Setting hostname"
    execute_quiet "echo -e '127.0.0.1 localhost\n127.0.1.1 xiaomi-raphael' | tee '$ROOTDIR/etc/hosts'" "Setting hosts file"
    
    # 跳过ARM64二进制格式支持设置
    
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
    export DEBIAN_FRONTEND=noninteractive
    
    execute_quiet "chroot '$ROOTDIR' apt update" "Updating package list"
    execute_quiet "chroot '$ROOTDIR' apt upgrade -y" "Upgrading system packages"
    execute_quiet "chroot '$ROOTDIR' apt install -y bash-completion sudo ssh nano initramfs-tools" "Installing basic tools"
    execute_quiet "chroot '$ROOTDIR' apt install -y rmtfs protection-domain-mapper tqftpserv" "Installing specific services"
    
    execute_quiet "sed -i '/ConditionKernelVersion/d' '$ROOTDIR/lib/systemd/system/pd-mapper.service'" "Modifying pd-mapper service"
    
    # Mount current directory to rootfs for direct deb package installation
    execute_quiet "mkdir -p '$ROOTDIR/tmp/build_dir'" "Creating build directory in rootfs"
    execute_quiet "mount --bind . '$ROOTDIR/tmp/build_dir'" "Mounting build directory to rootfs"
    
    # 安装deb包
    install_deb() {
        local pattern="$1"
        local description="$2"
        local deb_files=( $(find "$ROOTDIR/tmp/build_dir" -name "$pattern" -type f) )
        if [ ${#deb_files[@]} -eq 0 ]; then
            log_error "No $description package found (pattern: $pattern)"
            exit 1
        fi
        local deb_file="${deb_files[0]}"
        log_info "Installing $description package..."
        if ! chroot "$ROOTDIR" dpkg -i "/tmp/build_dir/$(basename "$deb_file")"; then
            log_error "Failed to install $description package"
            exit 1
        fi
    }
    
    install_deb "linux-xiaomi-raphael_*.deb" "linux kernel"
    install_deb "firmware-xiaomi-raphael_*.deb" "firmware"
    
    # 安装ALSA包的依赖
    execute_quiet "chroot '$ROOTDIR' apt install -y alsa-ucm-conf" "Installing ALSA dependencies"
    install_deb "alsa-xiaomi-raphael_*.deb" "ALSA"
    
    # 卸载构建目录
    execute_quiet "umount '$ROOTDIR/tmp/build_dir'" "Unmounting build directory"
    
    # 生成initramfs，显示详细信息以便调试
    log_info "Updating initramfs..."
    if ! chroot '$ROOTDIR' update-initramfs -c -k all; then
        log_error "Failed to update initramfs"
        exit 1
    fi
    log_success "Initramfs updated successfully"
    
    execute_quiet "chroot '$ROOTDIR' apt install -y grub-efi-arm64" "Installing GRUB"
    
    execute_quiet "sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' '$ROOTDIR/etc/default/grub'" "Enabling GRUB OS prober"
    execute_quiet "sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/' '$ROOTDIR/etc/default/grub'" "Modifying GRUB cmdline"
    
    execute_quiet "echo -e 'PARTLABEL=userdata / ext4 errors=remount-ro,x-systemd.growfs 0 1\nPARTLABEL=esp /boot/efi vfat umask=0077 0 1' | tee '$ROOTDIR/etc/fstab'" "Creating fstab"
    
    execute_quiet "mkdir -p '$ROOTDIR/var/lib/gdm'" "Creating GDM directory"
    execute_quiet "touch '$ROOTDIR/var/lib/gdm/run-initial-setup'" "Setting GDM initial setup flag"
    
    execute_quiet "chroot '$ROOTDIR' apt clean" "Cleaning package cache"
    
    # 跳过二进制格式注册清理
    
    # 检查boot目录内容 - 显示完整内容以便调试
    log_info "Checking boot directory content..."
    if [ -d "$ROOTDIR/boot" ]; then
        echo "Boot directory content:" 
        ls -la "$ROOTDIR/boot"
    fi
    
    # 列出安装的包 - 仅在GitHub Actions中显示关键包
    log_info "Listing key installed packages..."
    if [ -f "$ROOTDIR/var/lib/dpkg/status" ]; then
        chroot "$ROOTDIR" dpkg -l | grep -E "(linux-xiaomi|firmware-xiaomi|alsa-xiaomi|grub|sudo|ssh|systemd|initramfs)" || true
    fi
    
    # 卸载并清理
    execute_quiet "umount '$ROOTDIR/sys'" "Unmounting /sys"
    execute_quiet "umount '$ROOTDIR/proc'" "Unmounting /proc"
    execute_quiet "umount '$ROOTDIR/dev/pts'" "Unmounting /dev/pts"
    execute_quiet "umount '$ROOTDIR/dev'" "Unmounting /dev"
    execute_quiet "umount '$ROOTDIR'" "Unmounting rootfs"
    
    execute_quiet "rm -d '$ROOTDIR' 2>/dev/null || true" "Removing rootdir"
    execute_quiet "rm -f ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz 2>/dev/null || true" "Removing Ubuntu base archive"
    
    log_info "Compressing rootfs image..."
    if ! 7z a "${ROOTFS_IMG%.img}.7z" "$ROOTFS_IMG" >/dev/null; then
        log_error "Failed to compress rootfs image"
        exit 1
    fi
    
    log_success "Rootfs build completed"
    echo "Rootfs image: $ROOTFS_IMG"
    echo "Compressed rootfs: ${ROOTFS_IMG%.img}.7z"
}

[ "${BASH_SOURCE[0]}" = "$0" ] && main "$@"