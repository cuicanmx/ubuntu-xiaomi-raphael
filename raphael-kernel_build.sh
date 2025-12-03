#!/bin/bash

# Kernel build script for Xiaomi K20 Pro (Raphael)
# Standardized implementation with centralized configuration

set -e  # Exit on any error
set -o pipefail  # Exit on pipe failures

# ----------------------------- 
# Error handling and recovery
# ----------------------------- 
handle_error() {
    local exit_code=$?
    local line_number=$1
    local function_name=$2
    
    log_error "❌ Error occurred in function '$function_name' at line $line_number (exit code: $exit_code)"
    
    # Show current directory and environment info for debugging
    log_info "📁 Current directory: $(pwd)"
    log_info "🔧 Environment variables:"
    env | grep -E "(CCACHE|ARCH|CROSS_COMPILE|KERNEL)" || true
    
    # Attempt to cleanup before exiting
    cleanup
    
    exit $exit_code
}

trap 'handle_error $LINENO ${FUNCNAME[0]:-main}' ERR

# ----------------------------- 
# Load centralized configuration
# ----------------------------- 
if [ -f "build-config.sh" ]; then
    source "build-config.sh"
else
    echo "❌ Error: build-config.sh not found!"
    exit 1
fi

# ----------------------------- 
# Color output functions
# ----------------------------- 
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# ----------------------------- 
# Cleanup function
# ----------------------------- 
cleanup() {
    log_info "Cleaning up temporary directories..."
    
    # Clean up temporary files and directories with error handling
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log_info "Removing temporary directory: $TEMP_DIR"
        rm -rf "$TEMP_DIR" 2>/dev/null || {
            log_warning "Failed to remove temporary directory: $TEMP_DIR"
            # Try with sudo if permission issues
            sudo rm -rf "$TEMP_DIR" 2>/dev/null || log_warning "Could not remove temporary directory even with sudo"
        }
    else
        log_info "No temporary directory to clean up"
    fi
    
    log_success "Cleanup completed"
}

# ----------------------------- 
# Error handling setup
# ----------------------------- 
trap cleanup EXIT

# ----------------------------- 
# Parameter parsing
# ----------------------------- 
parse_arguments() {
    log_info "Parsing command-line arguments..."
    
    # Set default values from environment variables or centralized configuration
    KERNEL_VERSION="${KERNEL_VERSION:-${KERNEL_VERSION_DEFAULT}}"
    CACHE_ENABLED="${CACHE_ENABLED:-${CACHE_ENABLED_DEFAULT:-false}}"
    
    # If only one argument and it's not an option, treat it as kernel version
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
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    log_success "Arguments parsed successfully"
}

# ----------------------------- 
# Show help information
# ----------------------------- 
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Build kernel for Xiaomi K20 Pro (Raphael)

OPTIONS:
    -v, --version VERSION    Kernel version (e.g., 6.18) [default: ${KERNEL_VERSION_DEFAULT}]
    --cache                  Enable build cache
    --no-cache               Disable build cache [default: ${CACHE_ENABLED_DEFAULT:-false}]
    -h, --help               Show this help message

EXAMPLE:
    $0 --version 6.18 --cache
EOF
}

# ----------------------------- 
# Validate parameters
# ----------------------------- 
validate_parameters() {
    log_info "Validating parameters..."
    
    # Validate kernel version format
    validate_kernel_version "$KERNEL_VERSION" || {
        log_error "Invalid kernel version format"
        exit 1
    }
    
    # Set kernel branch name based on version
    KERNEL_BRANCH="${KERNEL_BRANCH_PREFIX}${KERNEL_VERSION}"
    
    # Set up directory paths with consistent naming
    TEMP_DIR="$(mktemp -d)"
    KERNEL_BUILD_DIR="${TEMP_DIR}/linux"
    OUTPUT_DIR="${WORKING_DIR}/output/kernel"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    log_success "Parameters validated successfully"
    log_info "Kernel version: $KERNEL_VERSION"
    log_info "Kernel branch: $KERNEL_BRANCH"
    log_info "Temporary directory: $TEMP_DIR"
    log_info "Build directory: $KERNEL_BUILD_DIR"
    log_info "Output directory: $OUTPUT_DIR"
}

# ----------------------------- 
# Install dependencies
# ----------------------------- 
install_dependencies() {
    log_info "Installing cross-compilation dependencies..."
    
    # Update package list
    sudo apt update
    
    # Install required packages including ccache
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
    
    log_success "Dependencies installed successfully"
}

# ----------------------------- 
# Check dependencies
# ----------------------------- 
check_dependencies() {
    log_info "🔍 Checking build dependencies..."
    
    # Check for essential cross-compilation tools
    local required_tools=("aarch64-linux-gnu-gcc" "aarch64-linux-gnu-g++" "make" "git" "ccache")
    local missing_tools=()
    
    for tool in "${required_tools[@]}"; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "All essential dependencies are available"
        return 0
    else
        log_warning "Missing dependencies: ${missing_tools[*]}"
        log_warning "Dependencies should be installed in the GitHub Actions workflow"
        log_warning "Attempting to install missing dependencies..."
        
        # Fallback: try to install missing dependencies
        install_dependencies
        return $?
    fi
}

# ----------------------------- 
# Clone kernel source
# ----------------------------- 
clone_kernel_source() {
    log_info "📥 Cloning kernel source from ${KERNEL_REPO} (${KERNEL_BRANCH})..."
    
    # Clone the kernel repository with specific branch
    git clone --branch "${KERNEL_BRANCH}" --depth 1 "${KERNEL_REPO}" "${TEMP_DIR}/linux"
    
    if [ $? -ne 0 ]; then
        log_error "❌ Failed to clone kernel source"
        exit 1
    fi
    
    # Update kernel build directory path
    KERNEL_BUILD_DIR="${TEMP_DIR}/linux"
    
    # Verify the cloned repository
    log_info "🔍 Verifying cloned repository..."
    cd "${KERNEL_BUILD_DIR}"
    git log --oneline -1
    cd - > /dev/null
    
    log_success "✅ Kernel source cloned successfully"
    log_info "📁 Kernel build directory: ${KERNEL_BUILD_DIR}"
}

# ----------------------------- 
# Configure kernel
# ----------------------------- 
configure_kernel() {
    log_info "⚙️ Configuring kernel..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # Use environment variables from GitHub Actions workflow
    # CCACHE configuration is already handled by the workflow
    
    # Verify ccache is available and show status
    if command -v ccache >/dev/null 2>&1; then
        log_info "🔧 Using ccache with cache directory: $CCACHE_DIR"
        log_info "📊 ccache status before configuration:"
        ccache -s 2>/dev/null || log_warning "⚠️ Could not get ccache status"
    else
        log_warning "⚠️ ccache not available, building without cache"
    fi
    
    log_info "🔧 Running kernel configuration..."
    log_info "📋 Configuration commands: make -j$(nproc) ARCH=arm64 CROSS_COMPILE=\"ccache aarch64-linux-gnu-\" defconfig sm8150.config"
    
    # Use the exact command from user's requirements with ccache
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" defconfig sm8150.config
    
    if [ $? -ne 0 ]; then
        log_error "❌ Kernel configuration failed"
        exit 1
    fi
    
    # Verify configuration files were created
    log_info "🔍 Verifying configuration files..."
    if [ -f ".config" ]; then
        log_success "✅ Kernel configuration file created successfully"
        log_info "📁 Configuration file size: $(du -h .config | cut -f1)"
    else
        log_error "❌ Kernel configuration file not found"
        exit 1
    fi
    
    log_success "✅ Kernel configured successfully"
    cd - > /dev/null
}

# ----------------------------- 
# Build kernel
# ----------------------------- 
build_kernel() {
    log_info "🔨 Building kernel..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # Use environment variables from GitHub Actions workflow
    # CCACHE configuration is already handled by the workflow
    
    # Verify ccache is available and show status
    if command -v ccache >/dev/null 2>&1; then
        log_info "🔧 Using ccache for kernel build"
        log_info "📁 ccache directory: $CCACHE_DIR"
        log_info "📊 ccache status before build:"
        ccache -s 2>/dev/null || log_warning "⚠️ Could not get ccache status"
    else
        log_warning "⚠️ ccache not available, building without cache"
    fi
    
    log_info "🔨 Starting kernel compilation..."
    log_info "📋 Build command: make -j$(nproc) ARCH=arm64 CROSS_COMPILE=\"ccache aarch64-linux-gnu-\""
    log_info "🖥️ Using $(nproc) CPU cores for compilation"
    
    # Use the exact command from user's requirements with ccache
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-"
    
    if [ $? -ne 0 ]; then
        log_error "❌ Kernel build failed"
        exit 1
    fi
    
    # Get the actual kernel version from the build
    _kernel_version="$(make kernelrelease -s)"
    export _kernel_version
    
    # Verify kernel image was created
    log_info "🔍 Verifying kernel build output..."
    if [ -f "arch/arm64/boot/Image.gz" ]; then
        log_success "✅ Kernel image created successfully"
        log_info "📁 Kernel image size: $(du -h arch/arm64/boot/Image.gz | cut -f1)"
    else
        log_error "❌ Kernel image not found"
        exit 1
    fi
    
    # Show ccache statistics after build
    if command -v ccache >/dev/null 2>&1; then
        log_info "📊 ccache statistics after build:"
        ccache -s 2>/dev/null || log_warning "⚠️ Could not get ccache statistics"
    fi
    
    log_success "✅ Kernel built successfully (version: $_kernel_version)"
    log_info "📁 Build output: arch/arm64/boot/Image.gz"
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
    cp arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb "${DEB_PACKAGE_DIR}/boot/dtb-$_kernel_version"
    log_success "✅ Kernel files copied to package directory"
    
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
    cp "${KERNEL_BUILD_DIR}/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb" "${OUTPUT_DIR}/dtbs/"
    
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
    mv linux-xiaomi-raphael.deb "${OUTPUT_DIR}/linux-xiaomi-raphael_${_kernel_version}.deb"
    mv firmware-xiaomi-raphael.deb "${OUTPUT_DIR}/firmware-xiaomi-raphael_${_kernel_version}.deb"
    mv alsa-xiaomi-raphael.deb "${OUTPUT_DIR}/alsa-xiaomi-raphael_${_kernel_version}.deb"
    
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
    log_info "📦 Kernel package: ${OUTPUT_DIR}/linux-xiaomi-raphael_${_kernel_version}.deb"
    log_info "📦 Firmware package: ${OUTPUT_DIR}/firmware-xiaomi-raphael_${_kernel_version}.deb"
    log_info "📦 ALSA package: ${OUTPUT_DIR}/alsa-xiaomi-raphael_${_kernel_version}.deb"
}

# ----------------------------- 
# Build status monitoring
# ----------------------------- 
BUILD_START_TIME=$(date +%s)
BUILD_STEPS=("参数解析" "参数验证" "依赖检查" "源码克隆" "内核配置" "内核编译" "包创建")
BUILD_STEP_COUNT=${#BUILD_STEPS[@]}
CURRENT_STEP=0

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
            ;;
        "error")
            log_error "❌ [$CURRENT_STEP/$BUILD_STEP_COUNT] ($progress%) 错误: $step_name - $message"
            ;;
    esac
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
    
    # Show initial ccache status if cache is enabled
    if [ "$CACHE_ENABLED" = "true" ] && command -v ccache >/dev/null 2>&1; then
        log_info "Cache enabled, checking ccache status..."
        log_info "ccache directory: $CCACHE_DIR"
        log_info "Initial ccache status:"
        ccache -s 2>/dev/null || log_warning "Could not get initial ccache status"
    elif [ "$CACHE_ENABLED" = "false" ]; then
        log_info "Cache disabled, building without ccache"
    else
        log_warning "ccache not available, building without cache"
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
    
    # Final build summary
    local total_time=$(( $(date +%s) - BUILD_START_TIME ))
    log_success "🎉 内核构建完成！"
    log_info "📊 构建统计:"
    log_info "   - 总耗时: ${total_time} 秒"
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
}

# ----------------------------- 
# Script execution
# ----------------------------- 
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi