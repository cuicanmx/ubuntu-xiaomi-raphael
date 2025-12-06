#!/bin/bash

set -e  # Exit on any error

# 加载项目配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/build-config.sh" ]; then
    source "${SCRIPT_DIR}/build-config.sh"
else
    echo "[ERROR] build-config.sh not found"
    exit 1
fi

# 配置参数（可从环境变量覆盖）
ROOTFS_SIZE="${ROOTFS_SIZE:-6G}"
DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
KERNEL_VERSION="${KERNEL_VERSION:-6.18}"
ROOTFS_IMG="root-${DISTRIBUTION}-${KERNEL_VERSION}.img"
ROOTDIR="rootdir"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.3}"
UBUNTU_CODENAME="${UBUNTU_CODENAME:-noble}"

# 简单日志函数
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

# 检查root权限
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log_error "This script must be run as root. Use sudo."
    fi
}

# 执行命令并检查错误
execute() {
    local cmd="$1"
    local desc="$2"
    log_info "执行: $desc"
    echo "命令: $cmd"
    if eval "$cmd"; then
        log_success "完成: $desc"
    else
        log_error "失败: $desc"
    fi
}

# 主函数
main() {
    echo "🚀 开始构建RootFS系统镜像"
    echo "目标发行版: $DISTRIBUTION"
    echo "内核版本: $KERNEL_VERSION"
    echo "镜像大小: $ROOTFS_SIZE"
    echo "镜像文件: $ROOTFS_IMG"

    # 检查root权限
    check_root

    # 如果镜像已存在，提示用户
    if [ -f "$ROOTFS_IMG" ]; then
        echo "[WARNING] 镜像文件 $ROOTFS_IMG 已存在，将被覆盖。"
        rm -f "$ROOTFS_IMG"
    fi

    # 1. 创建镜像文件并格式化
    execute "truncate -s '$ROOTFS_SIZE' '$ROOTFS_IMG'" "创建根文件系统镜像文件"
    execute "mkfs.ext4 '$ROOTFS_IMG'" "格式化镜像为ext4"

    # 2. 创建挂载点并挂载镜像
    execute "mkdir -p '$ROOTDIR'" "创建根目录挂载点"
    execute "mount -o loop '$ROOTFS_IMG' '$ROOTDIR'" "挂载镜像到根目录"

    # 3. 下载Ubuntu基础系统（如果尚未下载）
    local ubuntu_tarball="ubuntu-base-${UBUNTU_VERSION}-base-${UBUNTU_ARCH}.tar.gz"
    local ubuntu_url="${UBUNTU_DOWNLOAD_BASE}/${UBUNTU_CODENAME}/release/ubuntu-base-${UBUNTU_VERSION}-base-${UBUNTU_ARCH}.tar.gz"
    if [ ! -f "$ubuntu_tarball" ]; then
        execute "wget -q '$ubuntu_url'" "下载Ubuntu基础系统"
    else
        log_info "使用现有的Ubuntu基础系统归档: $ubuntu_tarball"
    fi

    # 4. 解压Ubuntu基础系统到根目录
    execute "tar xzf '$ubuntu_tarball' -C '$ROOTDIR'" "解压Ubuntu基础系统到根目录"

    # 5. 挂载必要的系统目录
    execute "mount --bind /dev '$ROOTDIR/dev'" "挂载/dev目录"
    execute "mount --bind /dev/pts '$ROOTDIR/dev/pts'" "挂载/dev/pts目录"
    execute "mount --bind /proc '$ROOTDIR/proc'" "挂载/proc目录"
    execute "mount --bind /sys '$ROOTDIR/sys'" "挂载/sys目录"
    execute "mount --bind /run '$ROOTDIR/run'" "挂载/run目录"

    # 6. 配置系统基础设置
    execute "echo 'nameserver 223.5.5.5' > '$ROOTDIR/etc/resolv.conf'" "配置DNS服务器"
    execute "echo 'xiaomi-raphael' > '$ROOTDIR/etc/hostname'" "设置主机名"
    execute "echo -e '127.0.0.1 localhost\n127.0.1.1 xiaomi-raphael' > '$ROOTDIR/etc/hosts'" "配置hosts文件"

    # 7. 设置环境变量
    export DEBIAN_FRONTEND=noninteractive

    # 8. 配置APT源（使用Ubuntu官方源）
    execute "echo 'deb http://ports.ubuntu.com/ubuntu-ports $UBUNTU_CODENAME main restricted universe multiverse' > '$ROOTDIR/etc/apt/sources.list'" "配置APT源"
    execute "echo 'deb http://ports.ubuntu.com/ubuntu-ports $UBUNTU_CODENAME-updates main restricted universe multiverse' >> '$ROOTDIR/etc/apt/sources.list'" "添加更新源"
    execute "echo 'deb http://ports.ubuntu.com/ubuntu-ports $UBUNTU_CODENAME-security main restricted universe multiverse' >> '$ROOTDIR/etc/apt/sources.list'" "添加安全源"

    # 9. 更新软件包列表并安装基础软件
    execute "chroot '$ROOTDIR' apt update" "更新软件包列表"
    execute "chroot '$ROOTDIR' apt upgrade -y" "升级系统软件包"
    execute "chroot '$ROOTDIR' apt install -y bash-completion sudo ssh nano initramfs-tools systemd-sysv" "安装基础工具包"
    execute "chroot '$ROOTDIR' apt install -y network-manager wpasupplicant" "安装网络工具"

    # 10. 安装项目特定的内核、固件和ALSA包
    # 首先安装依赖
    execute "chroot '$ROOTDIR' apt install -y alsa-ucm-conf" "安装ALSA依赖包"

    # 查找并安装项目特定的deb包
    install_project_deb() {
        local pattern="$1"
        local desc="$2"
        local deb_files=( $(find . -name "$pattern" -type f) )
        if [ ${#deb_files[@]} -eq 0 ]; then
            log_error "未找到 $desc 包 (模式: $pattern)"
        fi
        local deb_file="${deb_files[0]}"
        log_info "安装 $desc: $(basename "$deb_file")"
        cp "$deb_file" "$ROOTDIR/tmp/"
        execute "chroot '$ROOTDIR' dpkg -i '/tmp/$(basename "$deb_file")'" "安装 $desc"
        rm -f "$ROOTDIR/tmp/$(basename "$deb_file")"
    }

    # 安装内核、固件和ALSA包
    install_project_deb "linux-xiaomi-raphael_*.deb" "Linux内核"
    install_project_deb "firmware-xiaomi-raphael_*.deb" "固件"
    install_project_deb "alsa-xiaomi-raphael_*.deb" "ALSA"

    # 11. 生成initramfs
    execute "chroot '$ROOTDIR' update-initramfs -c -k all" "生成initramfs"

    # 12. 安装GRUB引导程序
    execute "chroot '$ROOTDIR' apt install -y grub-efi-arm64" "安装GRUB引导程序"

    # 13. 配置GRUB
    execute "sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' '$ROOTDIR/etc/default/grub'" "启用GRUB OS检测器"
    execute "sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/' '$ROOTDIR/etc/default/grub'" "修改GRUB命令行参数"

    # 14. 创建fstab文件
    execute "echo -e 'PARTLABEL=userdata / ext4 errors=remount-ro,x-systemd.growfs 0 1\\nPARTLABEL=esp /boot/efi vfat umask=0077 0 1' > '$ROOTDIR/etc/fstab'" "创建fstab文件"

    # 15. 清理包缓存
    execute "chroot '$ROOTDIR' apt clean" "清理包缓存"

    # 16. 检查boot目录内容
    log_info "检查boot目录内容..."
    if [ -d "$ROOTDIR/boot" ]; then
        ls -la "$ROOTDIR/boot"
    fi

    # 17. 卸载系统目录
    execute "umount '$ROOTDIR/run'" "卸载/run目录"
    execute "umount '$ROOTDIR/sys'" "卸载/sys目录"
    execute "umount '$ROOTDIR/proc'" "卸载/proc目录"
    execute "umount '$ROOTDIR/dev/pts'" "卸载/dev/pts目录"
    execute "umount '$ROOTDIR/dev'" "卸载/dev目录"

    # 18. 卸载根文件系统
    execute "umount '$ROOTDIR'" "卸载根文件系统"

    # 19. 清理临时目录和文件
    execute "rmdir '$ROOTDIR' 2>/dev/null || true" "删除挂载点目录"
    # 保留Ubuntu基础系统归档以备后用
    # execute "rm -f '$ubuntu_tarball'" "删除Ubuntu基础系统归档"

    log_success "RootFS构建完成! 镜像文件: $ROOTFS_IMG"
    echo "镜像大小: $(du -h $ROOTFS_IMG | cut -f1)"
}

# 如果脚本直接运行，则执行main函数
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
