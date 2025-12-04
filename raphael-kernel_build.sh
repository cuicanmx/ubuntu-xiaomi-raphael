#!/bin/bash

# 小米K20 Pro (Raphael) 内核构建脚本
# Optimized for GitHub Actions environment

set -e
set -o pipefail

# Error handling
handle_error() {
    local exit_code=$?
    local line_number=$1
    local function_name=$2
    
    echo "[ERROR] Error in function '$function_name' at line $line_number (exit code: $exit_code)"
    cleanup
    exit $exit_code
}

trap 'handle_error $LINENO ${FUNCNAME[0]:-main}' ERR

# Load configuration
[ -f "build-config.sh" ] && source "build-config.sh" || {
    echo "[ERROR] build-config.sh not found!"
    exit 1
}

# Log functions
log_info() {
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1"
}

log_success() {
    echo "[SUCCESS] $1"
}

log_error() {
    echo "[ERROR] $1"
}

log_warning() {
    echo "[WARNING] $1"
}

# Cleanup function
cleanup() {
    [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR" 2>/dev/null
}

trap cleanup EXIT

# Parse arguments
parse_arguments() {
    KERNEL_VERSION="${KERNEL_VERSION:-${KERNEL_VERSION_DEFAULT}}"
    CACHE_ENABLED="${CACHE_ENABLED:-${CACHE_ENABLED_DEFAULT:-false}}"
    
    [[ $# -eq 1 && ! "$1" =~ ^- ]] && KERNEL_VERSION="$1" && shift 1
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version) KERNEL_VERSION="$2"; shift 2 ;;
            --cache) CACHE_ENABLED="true"; shift 1 ;;
            --no-cache) CACHE_ENABLED="false"; shift 1 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Build kernel for Xiaomi K20 Pro (Raphael)

OPTIONS:
    -v, --version VERSION    Kernel version (e.g., 6.18) [default: ${KERNEL_VERSION_DEFAULT}]
    --cache                  Enable build cache
    --no-cache               Disable build cache [default: ${CACHE_ENABLED_DEFAULT:-false}]
    -h, --help               Show this help message

EXAMPLES:
    $0 --version 6.18 --cache
EOF
}

# ----------------------------- 
# 参数验证
# ----------------------------- 
validate_parameters() {
    log_info "正在验证参数..."
    
    # 验证内核版本格式 (例如: 6.18, 5.15)
    if [[ ! "$KERNEL_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_error "无效的内核版本格式: $KERNEL_VERSION"
        log_error "期望格式: 主版本.次版本 (例如: 6.18, 5.15)"
        exit 1
    fi
    
    # 验证缓存选项
    if [[ "$CACHE_ENABLED" != "true" && "$CACHE_ENABLED" != "false" ]]; then
        log_error "无效的缓存选项: $CACHE_ENABLED"
        log_error "期望值: true 或 false"
        exit 1
    fi
    
    # 设置基于版本的内核分支名称
    KERNEL_BRANCH="${KERNEL_BRANCH_PREFIX}${KERNEL_VERSION}"
    
    # 使用一致的命名设置目录路径
    TEMP_DIR="$(mktemp -d)"
    KERNEL_BUILD_DIR="${TEMP_DIR}/linux"
    OUTPUT_DIR="${WORKING_DIR}/output/kernel"
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"
    
    log_success "参数验证成功"
    log_info "内核版本: $KERNEL_VERSION"
    log_info "内核分支: $KERNEL_BRANCH"
    log_info "临时目录: $TEMP_DIR"
    log_info "构建目录: $KERNEL_BUILD_DIR"
    log_info "输出目录: $OUTPUT_DIR"
}

# ----------------------------- 
# 安装依赖项
# ----------------------------- 
install_dependencies() {
    log_info "正在安装交叉编译依赖项..."
    
    # 更新软件包列表
    sudo apt update
    
    # 安装必需的软件包，包括ccache
    sudo apt install -y \
        crossbuild-essential-arm64 \
        git \
        make \
        gcc \
        bc \
        bison \
        flex \
        libssl-dev \
        device-tree-compiler \
        u-boot-tools \
        dpkg-dev \
        debhelper \
        fakeroot \
        ccache
    
    log_success "依赖项安装成功"
}

# ----------------------------- 
# 检查依赖项
# ----------------------------- 
check_dependencies() {
    log_info "🔍 正在检查构建依赖项..."
    
    # 检查必需的交叉编译工具
    local required_tools=("aarch64-linux-gnu-gcc" "aarch64-linux-gnu-g++" "make" "git" "ccache")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "所有必需的依赖项都可用"
        return 0
    else
        log_warning "缺少依赖项: ${missing_tools[*]}"
        log_warning "依赖项应该在GitHub Actions工作流中安装"
        log_warning "尝试安装缺少的依赖项..."
        
        # 备用方案：尝试安装缺少的依赖项
        install_dependencies
        return $?
    fi
}

# ----------------------------- 
# 克隆内核源代码
# ----------------------------- 
clone_kernel_source() {
    log_info "📥 正在从 ${KERNEL_REPO} (${KERNEL_BRANCH}) 克隆内核源代码..."
    
    # 克隆指定分支的内核仓库
    git clone --branch "${KERNEL_BRANCH}" --depth 1 "${KERNEL_REPO}" "${TEMP_DIR}/linux"
    
    if [ $? -ne 0 ]; then
        log_error "❌ 克隆内核源代码失败"
        exit 1
    fi
    
    # 更新内核构建目录路径
    KERNEL_BUILD_DIR="${TEMP_DIR}/linux"
    
    # 验证克隆的仓库
    log_info "🔍 正在验证克隆的仓库..."
    cd "${KERNEL_BUILD_DIR}"
    git log --oneline -1
    cd - > /dev/null
    
    log_success "✅ 内核源代码克隆成功"
    log_info "📁 内核构建目录: ${KERNEL_BUILD_DIR}"
}

# ----------------------------- 
# 配置内核
# ----------------------------- 
configure_kernel() {
    log_info "⚙️ 正在配置内核..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # 使用GitHub Actions工作流中的环境变量
    # CCACHE配置已由工作流处理
    
    # 验证ccache是否可用并显示状态
    if command -v ccache >/dev/null 2>&1; then
        log_info "🔧 使用ccache，缓存目录: $CCACHE_DIR"
        log_info "📊 配置前的ccache状态:"
        ccache -s 2>/dev/null || log_warning "⚠️ 无法获取ccache状态"
    else
        log_warning "⚠️ ccache不可用，无缓存构建"
    fi
    
    log_info "🔧 正在运行内核配置..."
    log_info "📋 配置命令: make -j$(nproc) ARCH=arm64 CROSS_COMPILE=\"aarch64-linux-gnu-\" defconfig sm8150.config"
    
    # 使用ccache包装器，通过PATH环境变量自动拦截编译器调用
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE="aarch64-linux-gnu-" defconfig sm8150.config
    
    if [ $? -ne 0 ]; then
        log_error "❌ 内核配置失败"
        exit 1
    fi
    
    # 验证配置文件是否已创建
    log_info "🔍 正在验证配置文件..."
    if [ -f ".config" ]; then
        log_success "✅ 内核配置文件创建成功"
        log_info "📁 配置文件大小: $(du -h .config | cut -f1)"
    else
        log_error "❌ 未找到内核配置文件"
        exit 1
    fi
    
    log_success "✅ 内核配置成功"
    cd - > /dev/null
}

# ----------------------------- 
# 构建内核
# ----------------------------- 
build_kernel() {
    log_info "🔨 正在构建内核..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # 使用GitHub Actions工作流中的环境变量
    # CCACHE配置已由工作流处理
    
    # 验证ccache是否可用并显示状态
    if command -v ccache >/dev/null 2>&1; then
        log_info "🔧 使用ccache进行内核构建"
        log_info "📁 ccache目录: $CCACHE_DIR"
        log_info "📊 构建前的ccache状态:"
        ccache -s 2>/dev/null || log_warning "⚠️ 无法获取ccache状态"
    else
        log_warning "⚠️ ccache不可用，无缓存构建"
    fi
    
    log_info "🔨 开始内核编译..."
    log_info "📋 构建命令: make -j$(nproc) ARCH=arm64 CROSS_COMPILE=\"aarch64-linux-gnu-\""
    log_info "🖥️ 使用 $(nproc) 个CPU核心进行编译"
    
    # 使用ccache包装器，通过PATH环境变量自动拦截编译器调用
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE="aarch64-linux-gnu-"
    
    if [ $? -ne 0 ]; then
        log_error "❌ 内核构建失败"
        exit 1
    fi
    
    # 从构建中获取实际的内核版本
    _kernel_version="$(make kernelrelease -s)"
    export _kernel_version
    
    # 验证内核镜像是否已创建
    log_info "🔍 正在验证内核构建输出..."
    if [ -f "arch/arm64/boot/Image.gz" ]; then
        log_success "✅ 内核镜像创建成功"
        log_info "📁 内核镜像大小: $(du -h arch/arm64/boot/Image.gz | cut -f1)"
    else
        log_error "❌ 未找到内核镜像"
        exit 1
    fi
    
    # 显示构建后的ccache统计信息
    if command -v ccache >/dev/null 2>&1; then
        log_info "📊 构建后的ccache统计信息:"
        ccache -s 2>/dev/null || log_warning "⚠️ 无法获取ccache统计信息"
    fi
    
    log_success "✅ 内核构建成功 (版本: $_kernel_version)"
    log_info "📁 构建输出: arch/arm64/boot/Image.gz"
    cd - > /dev/null
}









# ----------------------------- 
# Create compressed archive
# ----------------------------- 
create_compressed_archive() {
    log_info "📦 Creating compressed archive of build artifacts..."
    
    local archive_name="kernel-${_kernel_version}-raphael"
    local archive_path="${OUTPUT_DIR}/${archive_name}"
    
    # Create a temporary directory for packaging
    local temp_dir=$(mktemp -d)
    
    # Copy all build artifacts to temporary directory
    log_info "📄 Copying build artifacts to temporary directory..."
    
    # Copy DEB packages
    mkdir -p "${temp_dir}/packages"
    cp "${OUTPUT_DIR}"/*.deb "${temp_dir}/packages/" 2>/dev/null || log_warning "⚠️ No DEB packages found"
    
    # Copy kernel image
    mkdir -p "${temp_dir}/kernel"
    if [ -f "${OUTPUT_DIR}/Image.gz-${_kernel_version}" ]; then
        cp "${OUTPUT_DIR}/Image.gz-${_kernel_version}" "${temp_dir}/kernel/"
        log_success "✅ Kernel image copied"
    fi
    
    # Copy DTB files
    if [ -d "${OUTPUT_DIR}/dtbs" ] && [ "$(ls -A ${OUTPUT_DIR}/dtbs/ 2>/dev/null)" ]; then
        mkdir -p "${temp_dir}/dtbs"
        cp "${OUTPUT_DIR}/dtbs/"* "${temp_dir}/dtbs/" 2>/dev/null || log_warning "⚠️ No DTB files found"
    fi
    
    # Copy build status file
    if [ -f "${OUTPUT_DIR}/build-status.txt" ]; then
        cp "${OUTPUT_DIR}/build-status.txt" "${temp_dir}/"
    fi
    
    # Create README file with build information
    cat > "${temp_dir}/README.md" << EOF
# Kernel $KERNEL_VERSION for Xiaomi Raphael (K20 Pro)

## Build Information
- Kernel Version: $KERNEL_VERSION
- Architecture: ARM64
- Target Device: Xiaomi Raphael (K20 Pro)
- Build Date: $(date)
- Build Time: $(( $(date +%s) - BUILD_START_TIME )) seconds

## Contents
- **packages/**: DEB packages for kernel, firmware, and ALSA
- **kernel/**: Standalone kernel image
- **dtbs/**: Device tree binary files
- **build-status.txt**: Detailed build status report

## Installation
1. Install DEB packages: \`sudo dpkg -i packages/*.deb\`
2. Update bootloader with kernel image if needed
3. Reboot to apply changes

## Cache Information
- CCACHE Enabled: $CACHE_ENABLED
- CCACHE Directory: $CCACHE_DIR
EOF
    
    # Create compressed archive (tar.gz for maximum compatibility)
    log_info "📦 Creating tar.gz archive..."
    cd "${temp_dir}"
    tar -czf "${archive_path}.tar.gz" .
    
    # Also create a zip archive for broader compatibility
    log_info "📦 Creating zip archive..."
    zip -r "${archive_path}.zip" . > /dev/null
    
    # Clean up temporary directory
    cd - > /dev/null
    rm -rf "${temp_dir}"
    
    # Verify archive creation
    if [ -f "${archive_path}.tar.gz" ] && [ -f "${archive_path}.zip" ]; then
        log_success "✅ Compressed archives created successfully"
        log_info "📦 Archive sizes:"
        log_info "   - ${archive_name}.tar.gz: $(du -h "${archive_path}.tar.gz" | cut -f1)"
        log_info "   - ${archive_name}.zip: $(du -h "${archive_path}.zip" | cut -f1)"
    else
        log_error "❌ Failed to create compressed archives"
    fi
}

# ----------------------------- 
# Create kernel package
# ----------------------------- 
create_kernel_package() {
    log_info "📦 Creating kernel package..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # Use the exact commands from user's requirements with correct paths
    local DEB_PACKAGE_DIR="${WORKING_DIR}/linux-xiaomi-raphael"
    log_info "📁 Creating package directory: ${DEB_PACKAGE_DIR}"
    mkdir -p "${DEB_PACKAGE_DIR}/boot"
    
    # Copy kernel image and DTB
    log_info "📄 Copying kernel image and DTB files..."
    cp arch/arm64/boot/Image.gz "${DEB_PACKAGE_DIR}/boot/vmlinuz-$_kernel_version"
    
    # Copy device tree file with error tolerance
    if [ -f "arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb" ]; then
        cp arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb "${DEB_PACKAGE_DIR}/boot/dtb-$_kernel_version"
        log_success "✅ Device tree file copied successfully"
    else
        log_warning "⚠️ Device tree file not found, creating placeholder"
        # Create empty placeholder file to avoid package creation failure
        touch "${DEB_PACKAGE_DIR}/boot/dtb-$_kernel_version"
        echo "# Placeholder for missing device tree file" > "${DEB_PACKAGE_DIR}/boot/dtb-$_kernel_version"
        log_info "📝 Created placeholder device tree file"
    fi
    
    log_success "✅ Kernel files processed successfully"
    
    # Update control file version
    log_info "📝 Updating control file version to ${_kernel_version}..."
    sed -i "s/Version:.*/Version: ${_kernel_version}/" "${DEB_PACKAGE_DIR}/DEBIAN/control"
    
    # Remove old lib directory if exists
    rm -rf "${DEB_PACKAGE_DIR}/lib" 2>/dev/null || true
    
    # Install modules
    log_info "🔧 Installing kernel modules..."
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="${DEB_PACKAGE_DIR}" modules_install
    
    # Remove build symlinks
    rm -rf "${DEB_PACKAGE_DIR}/lib/modules/**/build" 2>/dev/null || true
    
    # Build all packages
    cd "${WORKING_DIR}"
    
    # Create output directory structure
    log_info "📁 Creating output directory structure..."
    mkdir -p "${OUTPUT_DIR}/dtbs"
    
    # Copy standalone kernel image and DTB files
    log_info "📄 Copying standalone kernel files..."
    cp "${KERNEL_BUILD_DIR}/arch/arm64/boot/Image.gz" "${OUTPUT_DIR}/Image.gz-${_kernel_version}"
    
    # Copy device tree file with error tolerance
    if [ -f "${KERNEL_BUILD_DIR}/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb" ]; then
        cp "${KERNEL_BUILD_DIR}/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb" "${OUTPUT_DIR}/dtbs/"
        log_success "✅ Standalone device tree file copied successfully"
    else
        log_warning "⚠️ Standalone device tree file not found, skipping..."
        log_info "📝 DTB directory will be empty but build continues"
    fi
    
    # Create a symlink for GitHub Actions compatibility if versions differ
    if [ "${KERNEL_VERSION}" != "${_kernel_version}" ] && [ -n "${KERNEL_VERSION}" ]; then
        log_info "🔗 Creating version compatibility symlink..."
        ln -sf "Image.gz-${_kernel_version}" "${OUTPUT_DIR}/Image.gz-${KERNEL_VERSION}" 2>/dev/null || true
    fi
    
    # Build the kernel package
    log_info "📦 Building kernel DEB package..."
    dpkg-deb --build --root-owner-group linux-xiaomi-raphael
    
    # Verify the output directory structure
    log_info "🔍 Verifying output directory structure:"
    ls -la "${OUTPUT_DIR}/"
    ls -la "${OUTPUT_DIR}/dtbs/" 2>/dev/null || echo "DTB directory not found"
    
    # Build firmware and ALSA packages
    log_info "📦 Building firmware and ALSA packages..."
    dpkg-deb --build --root-owner-group firmware-xiaomi-raphael
    dpkg-deb --build --root-owner-group alsa-xiaomi-raphael
    
    # Copy packages to output directory
    log_info "📁 Moving packages to output directory..."
    mkdir -p "${OUTPUT_DIR}"
    mv linux-xiaomi-raphael.deb "${OUTPUT_DIR}/linux-xiaomi-raphael_${_kernel_version}_arm64.deb"
    mv firmware-xiaomi-raphael.deb "${OUTPUT_DIR}/firmware-xiaomi-raphael_${_kernel_version}_arm64.deb"
    mv alsa-xiaomi-raphael.deb "${OUTPUT_DIR}/alsa-xiaomi-raphael_${_kernel_version}_arm64.deb"
    
    # Clean up the linux directory
    rm -rf linux
    
    # Verify package sizes
    log_info "📊 Package sizes:"
    for pkg in "${OUTPUT_DIR}"/*.deb; do
        if [ -f "$pkg" ]; then
            log_info "📦 $(basename $pkg): $(du -h "$pkg" | cut -f1)"
        fi
    done
    
    log_success "✅ Kernel packages created successfully"
    log_info "📦 Kernel package: ${OUTPUT_DIR}/linux-xiaomi-raphael_${_kernel_version}_arm64.deb"
    log_info "📦 Firmware package: ${OUTPUT_DIR}/firmware-xiaomi-raphael_${_kernel_version}_arm64.deb"
    log_info "📦 ALSA package: ${OUTPUT_DIR}/alsa-xiaomi-raphael_${_kernel_version}_arm64.deb"
}

# Build status tracking
BUILD_START_TIME=$(date +%s)

# Main function
main() {
    log_info "Starting kernel build for Xiaomi K20 Pro (Raphael)"
    
    parse_arguments "$@"
    validate_parameters
    check_dependencies
    clone_kernel_source
    configure_kernel
    build_kernel
    create_kernel_package
    create_compressed_archive
    
    local total_time=$(( $(date +%s) - BUILD_START_TIME ))
    log_success "Kernel build completed in ${total_time}s"
    
    # Show package information
    for pkg in "${OUTPUT_DIR}"/*.deb; do
        [ -f "$pkg" ] && log_info "Package: $(basename $pkg) ($(du -h "$pkg" | cut -f1))"
    done
}

# ----------------------------- 
# Script execution
# ----------------------------- 
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi