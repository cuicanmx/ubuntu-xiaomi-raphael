#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/build-config.sh"

# 加载统一日志格式库
if [ -f "${SCRIPT_DIR}/logging-utils.sh" ]; then
    source "${SCRIPT_DIR}/logging-utils.sh"
else
    echo "[ERROR] 日志库文件 logging-utils.sh 未找到"
    exit 1
fi

# 配置参数
ROOTFS_SIZE="6G"
DISTRIBUTION="${DISTRIBUTION:-ubuntu}"
KERNEL_VERSION="${KERNEL_VERSION:-6.18}"
ROOTFS_IMG="root-${DISTRIBUTION}-${KERNEL_VERSION}.img"
ROOTDIR="rootdir"
VERSION="noble"
UBUNTU_VERSION="24.04.3"

# 初始化日志系统
init_logging

main() {
    log_info "开始构建RootFS系统镜像"
    log_info "目标发行版: $DISTRIBUTION"
    log_info "内核版本: $KERNEL_VERSION"
    log_info "镜像大小: $ROOTFS_SIZE"
    
    # 增强的命令执行函数
    execute_command() {
        local cmd="$1"
        local description="$2"
        
        log_info "执行: $description"
        log_debug "命令: $cmd"
        
        # 执行命令并捕获输出
        local output
        local exit_code
        
        output=$(eval "$cmd" 2>&1)
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            log_success "完成: $description"
            return 0
        else
            log_error "失败: $description (退出码: $exit_code)"
            log_error "错误信息:"
            echo "$output"
            
            # 根据错误类型提供特定建议
            if [[ "$description" == *chroot* ]] && [[ "$output" == *"No such file or directory"* ]]; then
                log_warning "chroot失败，检查ROOTDIR目录是否存在且已正确挂载"
                log_warning "检查命令: ls -la $ROOTDIR"
                if [ -d "$ROOTDIR" ]; then
                    log_info "ROOTDIR目录内容:"
                    ls -la "$ROOTDIR"
                fi
            elif [[ "$description" == *mount* ]]; then
                log_warning "挂载失败，检查设备或镜像文件是否存在"
            elif [[ "$description" == *download* ]]; then
                log_warning "下载失败，检查网络连接和URL有效性"
            fi
            
            exit $exit_code
        fi
    }
    
    # 检查ROOTDIR目录是否存在的专用函数
    check_rootdir() {
        if [ ! -d "$ROOTDIR" ]; then
            log_error "ROOTDIR目录不存在: $ROOTDIR"
            log_warning "请确保镜像文件已正确挂载"
            return 1
        fi
        
        # 检查关键目录是否存在
        local required_dirs=("$ROOTDIR/bin" "$ROOTDIR/etc" "$ROOTDIR/lib")
        for dir in "${required_dirs[@]}"; do
            if [ ! -d "$dir" ]; then
                log_error "关键目录不存在: $dir"
                log_warning "可能镜像文件未正确解压或挂载"
                return 1
            fi
        done
        
        log_success "ROOTDIR目录验证通过"
        return 0
    }
    
    # 创建和设置根文件系统
    execute_command "truncate -s '$ROOTFS_SIZE' '$ROOTFS_IMG'" "创建根文件系统镜像文件"
    execute_command "mkfs.ext4 '$ROOTFS_IMG'" "格式化根文件系统镜像为ext4文件系统"
    execute_command "mkdir -p '$ROOTDIR'" "创建根目录挂载点"
    execute_command "mount -o loop '$ROOTFS_IMG' '$ROOTDIR'" "挂载根文件系统镜像到根目录"
    
    # 下载和解压Ubuntu基础系统
    execute_command "wget -q 'https://cdimage.ubuntu.com/ubuntu-base/releases/$VERSION/release/ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz'" "下载Ubuntu基础系统镜像"
    execute_command "tar xzf ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz -C '$ROOTDIR'" "解压Ubuntu基础系统到根目录"
    
    # 验证根目录结构
    check_rootdir
    
    # 挂载必要的系统目录
    execute_command "mount --bind /dev '$ROOTDIR/dev'" "绑定挂载/dev目录"
    execute_command "mount --bind /dev/pts '$ROOTDIR/dev/pts'" "绑定挂载/dev/pts目录"
    execute_command "mount --bind /proc '$ROOTDIR/proc'" "绑定挂载/proc目录"
    execute_command "mount --bind /sys '$ROOTDIR/sys'" "绑定挂载/sys目录"
    
    # 配置系统基础设置
    execute_command "echo 'nameserver 223.5.5.5' | tee '$ROOTDIR/etc/resolv.conf'" "配置DNS服务器"
    execute_command "echo 'xiaomi-raphael' | tee '$ROOTDIR/etc/hostname'" "设置主机名"
    execute_command "echo -e '127.0.0.1 localhost\n127.0.1.1 xiaomi-raphael' | tee '$ROOTDIR/etc/hosts'" "配置hosts文件"
    
    # 设置环境变量
    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH
    export DEBIAN_FRONTEND=noninteractive
    
    # 更新和安装系统包
    execute_command "chroot '$ROOTDIR' apt update" "更新软件包列表"
    execute_command "chroot '$ROOTDIR' apt upgrade -y" "升级系统软件包"
    execute_command "chroot '$ROOTDIR' apt install -y bash-completion sudo ssh nano initramfs-tools" "安装基础工具包"
    execute_command "chroot '$ROOTDIR' apt install -y rmtfs protection-domain-mapper tqftpserv" "安装特定服务包"
    
    # 修改服务配置
    execute_command "sed -i '/ConditionKernelVersion/d' '$ROOTDIR/lib/systemd/system/pd-mapper.service'" "修改pd-mapper服务配置"
    
    # 挂载构建目录用于安装deb包
    execute_command "mkdir -p '$ROOTDIR/tmp/build_dir'" "在根文件系统中创建构建目录"
    execute_command "mount --bind . '$ROOTDIR/tmp/build_dir'" "挂载当前目录到根文件系统"
    
    # 安装deb包
    install_deb() {
        local pattern="$1"
        local description="$2"
        local deb_files=( $(find "$ROOTDIR/tmp/build_dir" -name "$pattern" -type f) )
        if [ ${#deb_files[@]} -eq 0 ]; then
            log_error "未找到$description包 (模式: $pattern)"
            log_warning "请确保已构建对应的deb包"
            return 1
        fi
        local deb_file="${deb_files[0]}"
        log_info "正在安装$description包..."
        execute_command "chroot '$ROOTDIR' dpkg -i '/tmp/build_dir/$(basename "$deb_file")'" "安装$description包"
    }
    
    install_deb "linux-xiaomi-raphael_*.deb" "Linux内核"
    install_deb "firmware-xiaomi-raphael_*.deb" "固件"
    
    # 安装ALSA包的依赖
    execute_command "chroot '$ROOTDIR' apt install -y alsa-ucm-conf" "安装ALSA依赖包"
    install_deb "alsa-xiaomi-raphael_*.deb" "ALSA"
    
    # 卸载构建目录
    execute_command "umount '$ROOTDIR/tmp/build_dir'" "卸载构建目录"
    
    # 生成initramfs - 使用execute_command确保错误处理
    log_info "正在更新initramfs..."
    execute_command "chroot '$ROOTDIR' update-initramfs -c -k all" "创建所有内核的initramfs"
    
    # 安装GRUB引导程序
    execute_command "chroot '$ROOTDIR' apt install -y grub-efi-arm64" "安装GRUB引导程序"
    
    # 配置GRUB
    execute_command "sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' '$ROOTDIR/etc/default/grub'" "启用GRUB OS检测器"
    execute_command "sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT=\"quiet splash\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\"/' '$ROOTDIR/etc/default/grub'" "修改GRUB命令行参数"
    
    # 创建fstab文件系统表
    execute_command "echo -e 'PARTLABEL=userdata / ext4 errors=remount-ro,x-systemd.growfs 0 1\nPARTLABEL=esp /boot/efi vfat umask=0077 0 1' | tee '$ROOTDIR/etc/fstab'" "创建fstab文件系统表"
    
    # 配置GDM显示管理器
    execute_command "mkdir -p '$ROOTDIR/var/lib/gdm'" "创建GDM目录"
    execute_command "touch '$ROOTDIR/var/lib/gdm/run-initial-setup'" "设置GDM初始设置标志"
    
    # 清理包缓存
    execute_command "chroot '$ROOTDIR' apt clean" "清理包缓存"
    
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
    execute_command "umount '$ROOTDIR/sys'" "卸载/sys目录"
    execute_command "umount '$ROOTDIR/proc'" "卸载/proc目录"
    execute_command "umount '$ROOTDIR/dev/pts'" "卸载/dev/pts目录"
    execute_command "umount '$ROOTDIR/dev'" "卸载/dev目录"
    execute_command "umount '$ROOTDIR'" "卸载根文件系统"
    
    execute_command "rm -d '$ROOTDIR' 2>/dev/null || true" "删除根目录"
    execute_command "rm -f ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz 2>/dev/null || true" "删除Ubuntu基础系统归档文件"
    
    # 压缩根文件系统镜像
    log_info "正在压缩根文件系统镜像..."
    execute_command "7z a '${ROOTFS_IMG%.img}.7z' '$ROOTFS_IMG' >/dev/null" "压缩根文件系统镜像为7z格式"
    
    log_success "RootFS构建成功完成！"
    echo "根文件系统镜像: $ROOTFS_IMG"
    echo "压缩后的镜像: ${ROOTFS_IMG%.img}.7z"
}

[ "${BASH_SOURCE[0]}" = "$0" ] && main "$@"