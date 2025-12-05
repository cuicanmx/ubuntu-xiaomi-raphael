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
BOOT_IMAGE_SIZE="64M"         # 启动镜像大小
BUILD_THREADS=$(nproc)         # 构建线程数（自动检测）

# ----------------------------- 
# 内核配置
# ----------------------------- 
KERNEL_REPO="https://github.com/GengWei1997/linux.git"       # 内核源码仓库
KERNEL_BRANCH_PREFIX="raphael-"                             # 内核仓库中的分支前缀
KERNEL_VERSION_DEFAULT="6.18"                               # 默认内核版本
CROSS_COMPILE="aarch64-linux-gnu-"                          # 交叉编译器前缀
KERNEL_CONFIG="sm8150.config"                                # 内核配置文件

# ----------------------------- 
# 启动镜像配置
# ----------------------------- 
BOOT_SOURCE_DEFAULT="https://github.com/GengWei1997/kernel-deb/releases/download/v1.0.0/xiaomi-k20pro-boot.img"  # 默认启动镜像源

# ----------------------------- 
# Ubuntu配置
# ----------------------------- 
UBUNTU_VERSION="24.04.3"                  # Ubuntu版本
UBUNTU_CODENAME="noble"                   # Ubuntu代号
UBUNTU_DOWNLOAD_BASE="https://cdimage.ubuntu.com/ubuntu-base/releases"  # Ubuntu基础下载地址
UBUNTU_ARCH="arm64"                       # Ubuntu架构

# ----------------------------- 
# 包配置
# ----------------------------- 
KERNEL_PACKAGE_NAME="linux-xiaomi-raphael"
KERNEL_PACKAGE_VERSION="${KERNEL_VERSION_DEFAULT}-1"
KERNEL_PACKAGE_ARCH="arm64"

# ----------------------------- 
# 目录配置
# ----------------------------- 
WORKING_DIR="$(pwd)"                 # 当前工作目录
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
SUPPORTED_DISTRIBUTIONS=("ubuntu")
SUPPORTED_UBUNTU_VERSIONS=("24.04.3" "noble")
DISTRIBUTION_DEFAULT="ubuntu"

# ----------------------------- 
# 依赖检查函数
# ----------------------------- 

# 检查命令是否可用
is_command_available() {
    local command="$1"
    command -v "$command" &>/dev/null
}

# 检查内核构建所需的所有依赖是否已安装
dependency_check_kernel_build() {
    local errors=0
    
    # 检查基本构建工具
    is_command_available "git" || ((errors++))
    is_command_available "make" || ((errors++))
    is_command_available "gcc" || ((errors++))
    is_command_available "bc" || ((errors++))
    is_command_available "bison" || ((errors++))
    is_command_available "flex" || ((errors++))
    is_command_available "dtc" || ((errors++))
    is_command_available "mkimage" || ((errors++))
    is_command_available "dpkg-deb" || ((errors++))
    
    # 检查交叉编译器
    is_command_available "${CROSS_COMPILE}gcc" || ((errors++))
    
    return $errors
}

# 检查根文件系统构建所需的所有依赖是否已安装
dependency_check_rootfs_build() {
    local errors=0
    
    # 检查基本工具
    is_command_available "wget" || ((errors++))
    is_command_available "parted" || ((errors++))
    is_command_available "mkfs.fat" || ((errors++))
    is_command_available "mount" || ((errors++))
    is_command_available "umount" || ((errors++))
    is_command_available "losetup" || ((errors++))
    is_command_available "blkid" || ((errors++))
    is_command_available "find" || ((errors++))
    is_command_available "cp" || ((errors++))
    is_command_available "mkdir" || ((errors++))
    is_command_available "rm" || ((errors++))
    is_command_available "cat" || ((errors++))
    is_command_available "dd" || ((errors++))
    
    return $errors
}

# ----------------------------- 
# 验证函数
# ----------------------------- 

# 验证发行版
validate_distribution() {
    local distribution="$1"
    local supported=false
    
    # 检查发行版是否在支持列表中
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
    
    return 0
}

# 验证内核版本格式
validate_kernel_version() {
    local kernel_version="$1"
    
    # 内核版本格式应为 X.Y 或 X.Y.Z
    if [[ ! "$kernel_version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        echo "❌ 错误: 无效的内核版本格式 '$kernel_version'"
        echo "   内核版本格式应为 X.Y 或 X.Y.Z"
        return 1
    fi
    
    return 0
}

# ----------------------------- 
# 实用函数
# ----------------------------- 

# 获取Ubuntu下载URL
get_ubuntu_url() {
    local version="$1"
    local arch="$2"
    
    # 生成Ubuntu基础下载URL
    local url="${UBUNTU_DOWNLOAD_BASE}/${version}/release/ubuntu-base-${version}-base-${arch}.tar.gz"
    echo "$url"
}

# ARM64原生环境设置
setup_arm64_environment() {
    echo "🔧 设置ARM64原生环境..."
    echo "当前运行在ARM64架构上，无需模拟"
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
    validate_kernel_version "${KERNEL_VERSION_DEFAULT}" || true
fi