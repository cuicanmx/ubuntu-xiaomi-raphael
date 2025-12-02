#!/bin/bash

# Kernel build script for Xiaomi K20 Pro (Raphael)
# Standardized implementation with centralized configuration

set -e  # Exit on any error

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
    log_info "Cleaning up..."
    
    # Clean up temporary files and directories
    rm -rf "$TEMP_DIR"
    
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
    
    # Set up directory paths
    TEMP_DIR="$(mktemp -d)"
    KERNEL_BUILD_DIR="${TEMP_DIR}/linux-${KERNEL_VERSION}"
    OUTPUT_DIR="${WORKING_DIR}/output/kernel"
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    
    log_success "Parameters validated successfully"
    log_info "Kernel version: $KERNEL_VERSION"
    log_info "Kernel branch: $KERNEL_BRANCH"
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
    log_info "Checking build dependencies..."
    
    # Use the centralized dependency check function
    if dependency_check_kernel_build; then
        log_success "All dependencies are already installed"
        return 0
    else
        log_warning "Missing dependencies, installing them..."
        install_dependencies
        return $?
    fi
}

# ----------------------------- 
# Clone kernel source
# ----------------------------- 
clone_kernel_source() {
    log_info "Cloning kernel source from ${KERNEL_REPO} (${KERNEL_BRANCH})..."
    
    # Clone the kernel repository with specific branch
    git clone --branch "${KERNEL_BRANCH}" --depth 1 "${KERNEL_REPO}" "${TEMP_DIR}/linux"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to clone kernel source"
        exit 1
    fi
    
    # Update kernel build directory path
    KERNEL_BUILD_DIR="${TEMP_DIR}/linux"
    
    log_success "Kernel source cloned successfully"
}

# ----------------------------- 
# Configure kernel
# ----------------------------- 
configure_kernel() {
    log_info "Configuring kernel..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # Set up ccache environment
    export CCACHE_DIR="${CCACHE_DIR}"
    export PATH="${CCACHE_DIR}/bin:${PATH}" 2>/dev/null || true
    
    # Use the exact command from user's requirements with ccache
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-" defconfig sm8150.config
    
    if [ $? -ne 0 ]; then
        log_error "Kernel configuration failed"
        exit 1
    fi
    
    log_success "Kernel configured successfully"
    cd - > /dev/null
}

# ----------------------------- 
# Build kernel
# ----------------------------- 
build_kernel() {
    log_info "Building kernel..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # Set up ccache environment
    export CCACHE_DIR="${CCACHE_DIR}"
    export PATH="${CCACHE_DIR}/bin:${PATH}" 2>/dev/null || true
    
    # Use the exact command from user's requirements with ccache
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE="ccache aarch64-linux-gnu-"
    
    if [ $? -ne 0 ]; then
        log_error "Kernel build failed"
        exit 1
    fi
    
    # Get the actual kernel version from the build
    _kernel_version="$(make kernelrelease -s)"
    export _kernel_version
    
    # Show ccache statistics
    if command -v ccache >/dev/null 2>&1; then
        log_info "ccache statistics:"
        ccache -s
    fi
    
    log_success "Kernel built successfully (version: $_kernel_version)"
    cd - > /dev/null
}









# ----------------------------- 
# Create kernel package
# ----------------------------- 
create_kernel_package() {
    log_info "Creating kernel package..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # Use the exact commands from user's requirements with correct paths
    local DEB_PACKAGE_DIR="${WORKING_DIR}/linux-xiaomi-raphael"
    mkdir -p "${DEB_PACKAGE_DIR}/boot"
    
    # Copy kernel image and DTB
    cp arch/arm64/boot/Image.gz "${DEB_PACKAGE_DIR}/boot/vmlinuz-$_kernel_version"
    cp arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb "${DEB_PACKAGE_DIR}/boot/dtb-$_kernel_version"
    
    # Update control file version
    sed -i "s/Version:.*/Version: ${_kernel_version}/" "${DEB_PACKAGE_DIR}/DEBIAN/control"
    
    # Remove old lib directory if exists
    rm -rf "${DEB_PACKAGE_DIR}/lib" 2>/dev/null || true
    
    # Install modules
    make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="${DEB_PACKAGE_DIR}" modules_install
    
    # Remove build symlinks
    rm -rf "${DEB_PACKAGE_DIR}/lib/modules/**/build" 2>/dev/null || true
    
    # Build all packages
    cd "${WORKING_DIR}"
    
    # Build the kernel package
    dpkg-deb --build --root-owner-group linux-xiaomi-raphael
    
    # Build firmware and ALSA packages
    dpkg-deb --build --root-owner-group firmware-xiaomi-raphael
    dpkg-deb --build --root-owner-group alsa-xiaomi-raphael
    
    # Copy packages to output directory
    mkdir -p "${OUTPUT_DIR}"
    mv linux-xiaomi-raphael.deb "${OUTPUT_DIR}/linux-xiaomi-raphael_${_kernel_version}.deb"
    mv firmware-xiaomi-raphael.deb "${OUTPUT_DIR}/firmware-xiaomi-raphael_${_kernel_version}.deb"
    mv alsa-xiaomi-raphael.deb "${OUTPUT_DIR}/alsa-xiaomi-raphael_${_kernel_version}.deb"
    
    # Clean up the linux directory
    rm -rf linux
    
    log_success "Kernel packages created successfully"
    log_info "Kernel package: ${OUTPUT_DIR}/linux-xiaomi-raphael_${_kernel_version}.deb"
    log_info "Firmware package: ${OUTPUT_DIR}/firmware-xiaomi-raphael_${_kernel_version}.deb"
    log_info "ALSA package: ${OUTPUT_DIR}/alsa-xiaomi-raphael_${_kernel_version}.deb"
}

# ----------------------------- 
# Main function
# ----------------------------- 
main() {
    # Set up ccache if enabled
    if [ "$CACHE_ENABLED" = "true" ]; then
        log_info "Configuring ccache..."
        
        # Create ccache directory if it doesn't exist
        mkdir -p "${CCACHE_DIR}"
        
        # Set ccache maximum size
        echo "max_size = ${CCACHE_MAXSIZE}" > "${CCACHE_DIR}/ccache.conf" 2>/dev/null || true
        
        # Set up ccache symlinks for cross-compilers
        mkdir -p "${CCACHE_DIR}/bin"
        for c in aarch64-linux-gnu-gcc aarch64-linux-gnu-g++; do
            ln -sf "$(which ccache)" "${CCACHE_DIR}/bin/$c" 2>/dev/null || true
        done
        
        # Make ccache directory writable
        sudo chmod -R 777 "${CCACHE_DIR}" 2>/dev/null || true
        
        log_success "ccache configured successfully"
    else
        log_info "Cache disabled, skipping ccache configuration"
    fi
    
    log_info "Starting kernel build for Xiaomi K20 Pro (Raphael)"
    
    # Step 1: Parse command-line arguments
    parse_arguments "$@"
    
    # Step 2: Validate parameters
    validate_parameters
    
    # Step 3: Check and install dependencies
    check_dependencies
    
    # Step 4: Clone kernel source code
    clone_kernel_source
    
    # Step 5: Configure kernel
    configure_kernel
    
    # Step 6: Build kernel (includes kernel release version detection)
    build_kernel
    
    # Step 7: Create kernel package
    create_kernel_package
    
    log_success "Kernel build completed successfully!"
    log_info "Build output is located in: $OUTPUT_DIR"
}

# ----------------------------- 
# Script execution
# ----------------------------- 
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi