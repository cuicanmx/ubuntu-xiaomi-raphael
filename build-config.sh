#!/bin/bash

# ----------------------------- 
# 小米K20 Pro (Raphael) Ubuntu项目的构建配置
# ----------------------------- 
# 此文件包含构建系统的所有集中式配置参数。
# 所有构建脚本在执行前都应引用此文件。

# ----------------------------- 
# 系统配置
# ----------------------------- 
SYSTEM_ARCH="arm64"            # 目标架构
ROOTFS_SIZE="6G"              # 根文件系统大小
SWAP_SIZE="2G"                # 交换分区大小
BOOT_IMAGE_SIZE="64M"         # 启动镜像大小
BUILD_THREADS=$(nproc)         # 构建线程数（自动检测）

# ----------------------------- 
# 内核配置
# ----------------------------- 
KERNEL_REPO="https://github.com/GengWei1997/linux.git"       # 内核源码仓库
KERNEL_BRANCH_PREFIX="raphael-"                             # 内核仓库中的分支前缀
KERNEL_VERSION_DEFAULT="6.18"                               # 默认内核版本
RELEASE_TAG_DEFAULT="v6.18"                                 # 默认发布标签
CROSS_COMPILE="aarch64-linux-gnu-"                          # 交叉编译器前缀
KERNEL_CONFIG="sm8150.config"                                # 内核配置文件

# ----------------------------- 
# 启动镜像配置
# ----------------------------- 
BOOT_SOURCE_DEFAULT="https://example.com/xiaomi-k20pro-boot.img"  # 默认启动镜像源
BOOT_OUTPUT_DEFAULT="xiaomi-k20pro-boot-%s-%s.img"                # 输出启动镜像格式

# ----------------------------- 
# 版本管理器配置
# ----------------------------- 
GITHUB_REPO="GengWei1997/ubuntu-xiaomi-raphael"    # GitHub仓库
KERNEL_WORKFLOW="kernel-build.yml"                 # 内核构建工作流
ROOTFS_WORKFLOW="main.yml"                          # 根文件系统构建工作流

# ----------------------------- 
# Ubuntu配置
# ----------------------------- 
UBUNTU_VERSION="24.04.3"                  # Ubuntu版本
UBUNTU_CODENAME="noble"                   # Ubuntu代号
UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"  # Ubuntu镜像源
UBUNTU_DOWNLOAD_BASE="https://cdimage.ubuntu.com/ubuntu-base/releases"  # Ubuntu基础下载地址
UBUNTU_IMAGE_TYPE="ubuntu-base"           # Ubuntu镜像类型
UBUNTU_ARCH="arm64"                       # Ubuntu架构

# ----------------------------- 
# QEMU配置
# ----------------------------- 
QEMU_SYSTEM="qemu-system-aarch64"        # QEMU系统模拟器
QEMU_MACHINE="virt"                      # QEMU机器类型
QEMU_CPU="cortex-a72"                    # QEMU CPU类型
QEMU_MEMORY="4G"                         # QEMU内存分配
QEMU_DISK="ubuntu-arm64.img"             # QEMU磁盘镜像
QEMU_NET="user,hostfwd=tcp::2222-:22"    # QEMU网络配置

# ----------------------------- 
# 包配置
# ----------------------------- 
KERNEL_PACKAGE_NAME="linux-image-raphael"
KERNEL_PACKAGE_VERSION="${KERNEL_VERSION_DEFAULT}-1"
KERNEL_PACKAGE_ARCH="arm64"

# ----------------------------- 
# 目录配置
# ----------------------------- 
WORKING_DIR="$(pwd)"                 # 当前工作目录
TEMP_DIR="${WORKING_DIR}/temp"      # 临时目录
OUTPUT_DIR="${WORKING_DIR}/output"   # 输出目录

# ----------------------------- 
# 缓存配置
# ----------------------------- 
CACHE_ENABLED_DEFAULT=true           # 默认启用构建缓存
CCACHE_DIR="${GITHUB_WORKSPACE:-$HOME}/.ccache"  # ccache目录（如果可用则使用GitHub工作空间）
CCACHE_MAXSIZE="5G"                  # ccache最大大小

# ----------------------------- 
# 支持的发行版
# ----------------------------- 
SUPPORTED_DISTRIBUTIONS=("ubuntu" "armbian")
SUPPORTED_UBUNTU_VERSIONS=("22.04" "24.04")

# ----------------------------- 
# 依赖检查函数
# ----------------------------- 

# 检查命令是否可用
is_command_available() {
    local command="$1"
    local description="$2"
    
    if command -v "$command" &>/dev/null; then
        return 0
    else
        echo "❌ 错误: $description ($command) 未安装!"
        return 1
    fi
}

# 检查内核构建所需的所有依赖是否已安装
dependency_check_kernel_build() {
    local errors=0
    
    echo "🔍 检查内核构建依赖..."
    
    # 检查基本构建工具
    is_command_available "git" "Git版本控制" || ((errors++))
    is_command_available "make" "GNU Make" || ((errors++))
    is_command_available "gcc" "GCC编译器" || ((errors++))
    is_command_available "bc" "基础计算器" || ((errors++))
    is_command_available "bison" "Bison解析器生成器" || ((errors++))
    is_command_available "flex" "Flex词法分析器" || ((errors++))
    is_command_available "dtc" "设备树编译器" || ((errors++))
    is_command_available "mkimage" "U-Boot镜像创建器" || ((errors++))
    is_command_available "dpkg-deb" "Debian包构建器" || ((errors++))
    
    # 检查交叉编译器
    is_command_available "${CROSS_COMPILE}gcc" "AArch64交叉编译器" || ((errors++))
    
    if ((errors == 0)); then
        echo "✅ 所有内核构建依赖已安装"
        return 0
    else
        echo "❌ 缺少 $errors 个必需依赖"
        return 1
    fi
}

# 检查根文件系统构建所需的所有依赖是否已安装
dependency_check_rootfs_build() {
    local errors=0
    
    echo "🔍 检查根文件系统构建依赖..."
    
    # 检查基本工具
    is_command_available "wget" "Wget下载工具" || ((errors++))
    is_command_available "parted" "Parted磁盘分区工具" || ((errors++))
    is_command_available "mkfs.fat" "FAT文件系统创建器" || ((errors++))
    is_command_available "mount" "挂载命令" || ((errors++))
    is_command_available "umount" "卸载命令" || ((errors++))
    is_command_available "losetup" "循环设备设置" || ((errors++))
    is_command_available "blkid" "块设备识别工具" || ((errors++))
    is_command_available "find" "查找命令" || ((errors++))
    is_command_available "cp" "复制命令" || ((errors++))
    is_command_available "mkdir" "创建目录" || ((errors++))
    is_command_available "rm" "删除命令" || ((errors++))
    is_command_available "cat" "显示文件内容" || ((errors++))
    is_command_available "dd" "DD磁盘复制工具" || ((errors++))
    
    if ((errors == 0)); then
        echo "✅ 所有根文件系统构建依赖已安装"
        return 0
    else
        echo "❌ 缺少 $errors 个必需依赖"
        return 1
    fi
}

# 检查版本管理器所需的所有依赖是否已安装
dependency_check_version_manager() {
    local errors=0
    
    echo "🔍 检查版本管理器依赖..."
    
    # 检查基本工具
    is_command_available "gh" "GitHub CLI" || ((errors++))
    is_command_available "curl" "CURL工具" || ((errors++))
    is_command_available "git" "Git版本控制" || ((errors++))
    is_command_available "sed" "流编辑器" || ((errors++))
    is_command_available "grep" "Grep模式匹配器" || ((errors++))
    is_command_available "date" "日期命令" || ((errors++))
    
    if ((errors == 0)); then
        echo "✅ 所有版本管理器依赖已安装"
        return 0
    else
        echo "❌ 缺少 $errors 个必需依赖"
        return 1
    fi
}

# ----------------------------- 
# 验证函数
# ----------------------------- 

# 验证发行版
validate_distribution() {
    local distribution="$1"
    local version="$2"
    local supported=false
    
    # 检查发行版是否受支持
    for supported_distro in "${SUPPORTED_DISTRIBUTIONS[@]}"; do
        if [[ "$distribution" == "$supported_distro" ]]; then
            supported=true
            break
        fi
    done
    
    if [[ "$supported" == false ]]; then
        echo "❌ 不支持的发行版: $distribution"
        echo "✅ 支持的发行版: ${SUPPORTED_DISTRIBUTIONS[*]}"
        return 1
    fi
    
    # 检查Ubuntu版本（如果适用）
    if [[ "$distribution" == "ubuntu" && -n "$version" ]]; then
        local version_supported=false
        for supported_ubuntu_version in "${SUPPORTED_UBUNTU_VERSIONS[@]}"; do
            if [[ "$version" == "$supported_ubuntu_version"* ]]; then
                version_supported=true
                break
            fi
        done
        
        if [[ "$version_supported" == false ]]; then
            echo "❌ 不支持的Ubuntu版本: $version"
            echo "✅ 支持的Ubuntu版本: ${SUPPORTED_UBUNTU_VERSIONS[*]}"
            return 1
        fi
    fi
    
    return 0
}

# 验证内核版本格式
validate_kernel_version() {
    local version="$1"
    
    # 基本内核版本验证（x.y或x.y.z格式）
    if [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        return 0
    else
        echo "❌ 无效的内核版本格式: $version"
        echo "✅ 期望格式: x.y 或 x.y.z (例如: 6.18 或 6.18.1)"
        return 1
    fi
}

# 验证GitHub仓库格式
validate_github_repo() {
    local repo="$1"
    
    # 基本GitHub仓库格式验证（所有者/仓库）
    if [[ "$repo" =~ ^[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+$ ]]; then
        return 0
    else
        echo "❌ 无效的GitHub仓库格式: $repo"
        echo "✅ 期望格式: 所有者/仓库 (例如: GengWei1997/ubuntu-xiaomi-raphael)"
        return 1
    fi
}

# ----------------------------- 
# 实用函数
# ----------------------------- 

# 获取Ubuntu下载URL
get_ubuntu_url() {
    local version="$1"
    local arch="$2"
    
    # 生成Ubuntu基础下载URL
    local url="${UBUNTU_DOWNLOAD_BASE}/${version}/release/${UBUNTU_IMAGE_TYPE}-${version}-base-${arch}.tar.gz"
    echo "$url"
}

# 设置QEMU进行模拟
setup_qemu() {
    local image="$1"
    
    echo "🔧 设置QEMU进行模拟..."
    echo "命令: qemu-system-aarch64 -machine ${QEMU_MACHINE} -cpu ${QEMU_CPU} -m ${QEMU_MEMORY} -drive format=raw,file=${image} -net ${QEMU_NET} -nographic -append 'console=ttyAMA0 root=/dev/vda2'"
    
    # 检查QEMU是否已安装
    is_command_available "${QEMU_SYSTEM}" "QEMU系统模拟器" || return 1
    
    return 0
}

# 生成时间戳
generate_timestamp() {
    date +"%Y%m%d-%H%M%S"
}

# 创建必要目录
create_directories() {
    echo "📁 创建必要目录..."
    mkdir -p "${TEMP_DIR}" "${OUTPUT_DIR}" "${OUTPUT_DIR}/kernel" "${OUTPUT_DIR}/rootfs" "${OUTPUT_DIR}/boot"
}

# ----------------------------- 
# 参数验证函数
# ----------------------------- 

# 验证根文件系统大小
validate_rootfs_size() {
    local size="$1"
    
    # 检查大小是否具有有效格式（例如：4G, 10G）
    if [[ "$size" =~ ^[0-9]+[GM]$ ]]; then
        local numeric_size=${size::-1}
        
        # 确保最小大小为2G
        if ((numeric_size >= 2)); then
            return 0
        else
            echo "❌ 根文件系统大小太小。最小大小为2G"
            return 1
        fi
    else
        echo "❌ 无效的根文件系统大小格式: $size"
        echo "✅ 期望格式: [数字][G|M] (例如: 6G, 4096M)"
        return 1
    fi
}

# 验证构建线程数
validate_build_threads() {
    local threads="$1"
    
    # 检查线程数是否为正整数
    if [[ "$threads" =~ ^[0-9]+$ ]] && ((threads > 0)); then
        return 0
    else
        echo "❌ 无效的构建线程数: $threads"
        echo "✅ 期望一个正整数 (例如: 4, 8)"
        return 1
    fi
}

# ----------------------------- 
# 错误处理函数
# ----------------------------- 

# 打印错误消息并退出
fatal_error() {
    local message="$1"
    echo -e "\033[0;31m❌ 致命错误: $message\033[0m"
    exit 1
}

# 检查命令执行状态
check_status() {
    local status="$1"
    local success_message="$2"
    local error_message="$3"
    
    if ((status == 0)); then
        echo -e "\033[0;32m✅ $success_message\033[0m"
        return 0
    else
        echo -e "\033[0;31m❌ $error_message\033[0m"
        return 1
    fi
}

# ----------------------------- 
# 初始化
# ----------------------------- 

# 引用此文件以加载所有配置和函数
# 使用示例: source build-config.sh

# 加载时验证关键配置
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # 此文件正在被引用，执行基本验证
    validate_github_repo "${GITHUB_REPO}" || true
    validate_kernel_version "${KERNEL_VERSION_DEFAULT}" || true
fi