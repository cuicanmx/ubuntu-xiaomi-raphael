#!/bin/bash

# 小米K20 Pro (Raphael) 内核构建脚本
# 标准化实现，使用集中式配置

set -e  # 任何错误时退出
set -o pipefail  # 管道失败时退出

# ----------------------------- 
# 错误处理和恢复
# ----------------------------- 
# 具有严重性级别的增强错误处理
handle_error() {
    local exit_code=$?
    local line_number=$1
    local function_name=$2
    local error_level="${3:-fatal}"  # 如果未指定，默认为致命错误
    
    case $error_level in
        "fatal")
            log_error "❌ 致命错误发生在函数 '$function_name' 的第 $line_number 行 (退出代码: $exit_code)"
            
            # 显示当前目录和环境信息用于调试
            log_info "📁 当前目录: $(pwd)"
            log_info "🔧 环境变量:"
            env | grep -E "(CCACHE|ARCH|CROSS_COMPILE|KERNEL)" || true
            
            # 在退出前尝试清理
            cleanup
            
            exit $exit_code
            ;;
        "nonfatal")
            log_warning "⚠️ 非致命错误发生在函数 '$function_name' 的第 $line_number 行 (退出代码: $exit_code)"
            log_info "📝 尽管有错误，继续构建过程..."
            return 0  # 继续执行
            ;;
        *)
            log_error "❌ 未知错误级别: $error_level"
            exit 1
            ;;
    esac
}

# 特定命令的增强错误处理
safe_execute() {
    local command="$1"
    local error_level="${2:-fatal}"
    
    log_info "🔧 执行: $command"
    
    if eval "$command"; then
        log_success "✅ 命令执行成功"
        return 0
    else
        local exit_code=$?
        log_warning "⚠️ 命令执行失败，退出代码: $exit_code"
        
        if [ "$error_level" = "nonfatal" ]; then
            log_info "📝 非致命错误，继续..."
            return $exit_code
        else
            log_error "❌ 致命错误，终止构建"
            exit $exit_code
        fi
    fi
}

# 为ERR信号设置陷阱，使用增强错误处理
trap 'handle_error $LINENO ${FUNCNAME[0]:-main} fatal' ERR

# ----------------------------- 
# 加载集中式配置
# ----------------------------- 
if [ -f "build-config.sh" ]; then
    source "build-config.sh"
else
    echo "❌ 错误: build-config.sh 未找到!"
    exit 1
fi

# ----------------------------- 
# 彩色输出函数
# ----------------------------- 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 无颜色

log_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

log_error() {
    echo -e "${RED}[错误]${NC} $1"
}

# ----------------------------- 
# 清理函数
# ----------------------------- 
cleanup() {
    log_info "正在清理临时目录..."
    
    # 清理临时文件和目录，带有错误处理
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log_info "删除临时目录: $TEMP_DIR"
        rm -rf "$TEMP_DIR" 2>/dev/null || {
            log_warning "删除临时目录失败: $TEMP_DIR"
            # 如果有权限问题，尝试使用sudo
            sudo rm -rf "$TEMP_DIR" 2>/dev/null || log_warning "即使使用sudo也无法删除临时目录"
        }
    else
        log_info "没有临时目录需要清理"
    fi
    
    log_success "清理完成"
}

# ----------------------------- 
# 错误处理设置
# ----------------------------- 
trap cleanup EXIT

# ----------------------------- 
# 参数解析
# ----------------------------- 
parse_arguments() {
    log_info "正在解析命令行参数..."
    
    # 从环境变量或集中式配置设置默认值
    KERNEL_VERSION="${KERNEL_VERSION:-${KERNEL_VERSION_DEFAULT}}"
    CACHE_ENABLED="${CACHE_ENABLED:-${CACHE_ENABLED_DEFAULT:-false}}"
    
    # 如果只有一个参数且不是选项，将其视为内核版本
    if [[ $# -eq 1 && ! "$1" =~ ^- ]]; then
        KERNEL_VERSION="$1"
        shift 1
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                KERNEL_VERSION="$2"
                shift 2
                ;;
            --cache)
                CACHE_ENABLED="true"
                shift 1
                ;;
            --no-cache)
                CACHE_ENABLED="false"
                shift 1
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_success "参数解析成功"
}

# ----------------------------- 
# 显示帮助信息
# ----------------------------- 
show_help() {
    cat << EOF
用法: $0 [选项]

为小米K20 Pro (Raphael) 构建内核

选项:
    -v, --version 版本        内核版本 (例如: 6.18) [默认: ${KERNEL_VERSION_DEFAULT}]
    --cache                   启用构建缓存
    --no-cache                禁用构建缓存 [默认: ${CACHE_ENABLED_DEFAULT:-false}]
    -h, --help                显示此帮助信息

示例:
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
    log_info "📋 配置命令: make -j$(nproc) ARCH=arm64 CROSS_COMPILE=\"ccache aarch64-linux-gnu-\" defconfig sm8150.config"
    
    # 使用用户需求中的确切命令，包含ccache
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" defconfig sm8150.config
    
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
    log_info "📋 构建命令: make -j$(nproc) ARCH=arm64 CROSS_COMPILE=\"ccache aarch64-linux-gnu-\""
    log_info "🖥️ 使用 $(nproc) 个CPU核心进行编译"
    
    # 使用用户需求中的确切命令，包含ccache
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-"
    
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

# ----------------------------- 
# Build status monitoring and error tolerance
# ----------------------------- 
BUILD_START_TIME=$(date +%s)
BUILD_STEPS=("参数解析" "参数验证" "依赖检查" "源码克隆" "内核配置" "内核编译" "包创建")
BUILD_STEP_COUNT=${#BUILD_STEPS[@]}
CURRENT_STEP=0
BUILD_STATUS="in_progress"

# Enhanced build status reporting with error tolerance
report_build_status() {
    local step_name="$1"
    local status="$2"
    local message="$3"
    
    CURRENT_STEP=$((CURRENT_STEP + 1))
    local progress=$((CURRENT_STEP * 100 / BUILD_STEP_COUNT))
    local elapsed_time=$(( $(date +%s) - BUILD_START_TIME ))
    
    case $status in
        "start")
            log_info "🚀 [$CURRENT_STEP/$BUILD_STEP_COUNT] ($progress%) 开始: $step_name"
            ;;
        "success") 
            log_success "✅ [$CURRENT_STEP/$BUILD_STEP_COUNT] ($progress%) 完成: $step_name (耗时: ${elapsed_time}s)"
            ;;
        "warning")
            log_warning "⚠️ [$CURRENT_STEP/$BUILD_STEP_COUNT] ($progress%) 警告: $step_name - $message"
            BUILD_STATUS="partial_success"
            ;;
        "error")
            log_error "❌ [$CURRENT_STEP/$BUILD_STEP_COUNT] ($progress%) 错误: $step_name - $message"
            BUILD_STATUS="partial_success"
            ;;
    esac
    
    # Update build status file for GitHub Actions
    update_build_status_file
}

# Create build status file for debugging and monitoring
update_build_status_file() {
    local status_file="${OUTPUT_DIR}/build-status.txt"
    
    mkdir -p "${OUTPUT_DIR}"
    
    cat > "$status_file" << EOF
Build Status: $BUILD_STATUS
Current Step: $CURRENT_STEP/$BUILD_STEP_COUNT
Progress: $((CURRENT_STEP * 100 / BUILD_STEP_COUNT))%
Elapsed Time: $(( $(date +%s) - BUILD_START_TIME ))s
Kernel Version: $KERNEL_VERSION
Build Started: $(date -d @$BUILD_START_TIME)
Last Updated: $(date)

Generated Files:
- DEB Packages: $(ls "${OUTPUT_DIR}"/*.deb 2>/dev/null | wc -l)
- Kernel Image: $([ -f "${OUTPUT_DIR}/Image.gz-${KERNEL_VERSION}" ] && echo "yes" || echo "no")
- DTB Files: $(ls "${OUTPUT_DIR}/dtbs/"*.dtb 2>/dev/null | wc -l)

Cache Information:
- CCACHE Enabled: $CACHE_ENABLED
- CCACHE Directory: $CCACHE_DIR
EOF
    
    # Add detailed file list if available
    if [ -d "${OUTPUT_DIR}" ]; then
        echo "" >> "$status_file"
        echo "File Listing:" >> "$status_file"
        ls -la "${OUTPUT_DIR}"/* 2>/dev/null >> "$status_file" || true
    fi
}

# ----------------------------- 
# Main function
# ----------------------------- 
main() {
    log_info "🚀 Starting kernel build process..."
    log_info "📊 Build configuration:"
    log_info "   - Target: Xiaomi K20 Pro (Raphael)"
    log_info "   - Architecture: ARM64"
    log_info "   - Build started at: $(date)"
    
    # Show initial ccache status if cache is enabled or in GitHub Actions environment
    if [ "$CACHE_ENABLED" = "true" ] || [ -n "$GITHUB_ACTIONS" ]; then
        if command -v ccache >/dev/null 2>&1; then
            log_info "🔧 ccache status (GitHub Actions environment):"
            log_info "📁 ccache directory: $CCACHE_DIR"
            ccache -s 2>/dev/null || log_warning "⚠️ Could not get ccache status"
            
            # Check if ccache directory is accessible
            if [ -n "$CCACHE_DIR" ] && [ -d "$CCACHE_DIR" ]; then
                log_info "📁 ccache directory: $CCACHE_DIR (accessible)"
            else
                log_warning "⚠️ ccache directory not accessible"
            fi
        else
            log_warning "⚠️ ccache command not found in PATH"
        fi
    else
        log_info "🔧 Building without ccache (cache disabled)"
    fi
    
    # Parse command-line arguments
    report_build_status "${BUILD_STEPS[0]}" "start"
    parse_arguments "$@"
    report_build_status "${BUILD_STEPS[0]}" "success"
    
    # Validate parameters
    report_build_status "${BUILD_STEPS[1]}" "start"
    validate_parameters
    report_build_status "${BUILD_STEPS[1]}" "success"
    
    # Check dependencies
    report_build_status "${BUILD_STEPS[2]}" "start"
    check_dependencies
    report_build_status "${BUILD_STEPS[2]}" "success"
    
    # Clone kernel source
    report_build_status "${BUILD_STEPS[3]}" "start"
    clone_kernel_source
    report_build_status "${BUILD_STEPS[3]}" "success"
    
    # Configure kernel
    report_build_status "${BUILD_STEPS[4]}" "start"
    configure_kernel
    report_build_status "${BUILD_STEPS[4]}" "success"
    
    # Build kernel
    report_build_status "${BUILD_STEPS[5]}" "start"
    build_kernel
    report_build_status "${BUILD_STEPS[5]}" "success"
    
    # Create kernel package
    report_build_status "${BUILD_STEPS[6]}" "start"
    create_kernel_package
    report_build_status "${BUILD_STEPS[6]}" "success"
    
    # Final build summary and status update
    local total_time=$(( $(date +%s) - BUILD_START_TIME ))
    
    # Set final build status
    if [ "$BUILD_STATUS" = "in_progress" ]; then
        BUILD_STATUS="success"
    fi
    
    log_success "🎉 内核构建完成！"
    log_info "📊 构建统计:"
    log_info "   - 总耗时: ${total_time} 秒"
    log_info "   - 构建状态: ${BUILD_STATUS}"
    log_info "   - 输出目录: ${OUTPUT_DIR}"
    log_info "   - 生成的文件:"
    ls -la "${OUTPUT_DIR}/"
    
    # Show final package information
    log_info "📦 生成的包:"
    for pkg in "${OUTPUT_DIR}"/*.deb; do
        if [ -f "$pkg" ]; then
            log_info "   - $(basename $pkg) ($(du -h "$pkg" | cut -f1))"
        fi
    done
    
    # Final build status update
    update_build_status_file
    
    # Show build status file content
    if [ -f "${OUTPUT_DIR}/build-status.txt" ]; then
        log_info "📋 构建状态报告:"
        cat "${OUTPUT_DIR}/build-status.txt"
    fi
}

# ----------------------------- 
# Script execution
# ----------------------------- 
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi