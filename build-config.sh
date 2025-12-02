#!/bin/bash

# ----------------------------- 
# Build Configuration for Xiaomi K20 Pro (Raphael) Ubuntu Project
# ----------------------------- 
# This file contains all centralized configuration parameters for the build system.
# All build scripts should source this file before execution.

# ----------------------------- 
# System Configuration
# ----------------------------- 
SYSTEM_ARCH="arm64"            # Target architecture
ROOTFS_SIZE="6G"              # Root filesystem size
SWAP_SIZE="2G"                # Swap partition size
BOOT_IMAGE_SIZE="64M"         # Boot image size
BUILD_THREADS=$(nproc)         # Number of build threads (auto-detected)

# ----------------------------- 
# Kernel Configuration
# ----------------------------- 
KERNEL_REPO="https://github.com/GengWei1997/linux.git"       # Kernel source repository
KERNEL_BRANCH_PREFIX="raphael-"                             # Branch prefix in kernel repo
KERNEL_VERSION_DEFAULT="6.18"                               # Default kernel version
RELEASE_TAG_DEFAULT="v6.18"                                 # Default release tag
CROSS_COMPILE="aarch64-linux-gnu-"                          # Cross-compiler prefix
KERNEL_CONFIG="sm8150.config"                                # Kernel configuration file

# ----------------------------- 
# Boot Image Configuration
# ----------------------------- 
BOOT_SOURCE_DEFAULT="https://example.com/xiaomi-k20pro-boot.img"  # Default boot image source
BOOT_OUTPUT_DEFAULT="xiaomi-k20pro-boot-%s-%s.img"                # Output boot image format

# ----------------------------- 
# Version Manager Configuration
# ----------------------------- 
GITHUB_REPO="GengWei1997/ubuntu-xiaomi-raphael"    # GitHub repository
KERNEL_WORKFLOW="kernel-build.yml"                 # Kernel build workflow
ROOTFS_WORKFLOW="main.yml"                          # Rootfs build workflow

# ----------------------------- 
# Ubuntu Configuration
# ----------------------------- 
UBUNTU_VERSION="24.04.3"                  # Ubuntu version
UBUNTU_CODENAME="noble"                   # Ubuntu codename
UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"  # Ubuntu mirror
UBUNTU_DOWNLOAD_BASE="https://cdimage.ubuntu.com/ubuntu-base/releases"  # Ubuntu base download URL
UBUNTU_IMAGE_TYPE="ubuntu-base"           # Ubuntu image type
UBUNTU_ARCH="arm64"                       # Ubuntu architecture

# ----------------------------- 
# QEMU Configuration
# ----------------------------- 
QEMU_SYSTEM="qemu-system-aarch64"        # QEMU system emulator
QEMU_MACHINE="virt"                      # QEMU machine type
QEMU_CPU="cortex-a72"                    # QEMU CPU type
QEMU_MEMORY="4G"                         # QEMU memory allocation
QEMU_DISK="ubuntu-arm64.img"             # QEMU disk image
QEMU_NET="user,hostfwd=tcp::2222-:22"    # QEMU network configuration

# ----------------------------- 
# Package Configuration
# ----------------------------- 
KERNEL_PACKAGE_NAME="linux-image-raphael"
KERNEL_PACKAGE_VERSION="${KERNEL_VERSION_DEFAULT}-1"
KERNEL_PACKAGE_ARCH="arm64"

# ----------------------------- 
# Directory Configuration
# ----------------------------- 
WORKING_DIR="$(pwd)"                 # Current working directory
TEMP_DIR="${WORKING_DIR}/temp"      # Temporary directory
OUTPUT_DIR="${WORKING_DIR}/output"   # Output directory

# ----------------------------- 
# Cache Configuration
# ----------------------------- 
CACHE_ENABLED_DEFAULT=true           # Default enable build cache
CACHE_DIR="${HOME}/.cache/raphael-build"  # Cache directory
CACHE_LIMIT="10G"                    # Cache size limit

# ----------------------------- 
# Supported Distributions
# ----------------------------- 
SUPPORTED_DISTRIBUTIONS=("ubuntu" "armbian")
SUPPORTED_UBUNTU_VERSIONS=("22.04" "24.04")

# ----------------------------- 
# Dependency Check Functions
# ----------------------------- 

# Check if a command is available
is_command_available() {
    local command="$1"
    local description="$2"
    
    if command -v "$command" &>/dev/null; then
        return 0
    else
        echo "❌ Error: $description ($command) is not installed!"
        return 1
    fi
}

# Check if all required dependencies are installed for kernel build
dependency_check_kernel_build() {
    local errors=0
    
    echo "🔍 Checking dependencies for kernel build..."
    
    # Check essential build tools
    is_command_available "git" "Git version control" || ((errors++))
    is_command_available "make" "GNU Make" || ((errors++))
    is_command_available "gcc" "GCC compiler" || ((errors++))
    is_command_available "bc" "Basic calculator" || ((errors++))
    is_command_available "bison" "Bison parser generator" || ((errors++))
    is_command_available "flex" "Flex lexical analyzer" || ((errors++))
    is_command_available "dtc" "Device Tree Compiler" || ((errors++))
    is_command_available "mkimage" "U-Boot image creator" || ((errors++))
    is_command_available "dpkg-deb" "Debian package builder" || ((errors++))
    
    # Check cross-compiler
    is_command_available "${CROSS_COMPILE}gcc" "AArch64 cross-compiler" || ((errors++))
    
    if ((errors == 0)); then
        echo "✅ All kernel build dependencies are installed"
        return 0
    else
        echo "❌ Missing $errors required dependencies"
        return 1
    fi
}

# Check if all required dependencies are installed for boot image build
dependency_check_boot_build() {
    local errors=0
    
    echo "🔍 Checking dependencies for boot image build..."
    
    # Check essential tools
    is_command_available "wget" "Wget download tool" || ((errors++))
    is_command_available "parted" "Parted disk partitioning tool" || ((errors++))
    is_command_available "mkfs.fat" "FAT filesystem creator" || ((errors++))
    is_command_available "mount" "Mount command" || ((errors++))
    is_command_available "umount" "Unmount command" || ((errors++))
    is_command_available "losetup" "Loop device setup" || ((errors++))
    is_command_available "blkid" "Block device identification" || ((errors++))
    is_command_available "find" "Find command" || ((errors++))
    is_command_available "cp" "Copy command" || ((errors++))
    is_command_available "mkdir" "Make directory" || ((errors++))
    is_command_available "rm" "Remove command" || ((errors++))
    is_command_available "cat" "Cat command" || ((errors++))
    is_command_available "dd" "DD disk copy tool" || ((errors++))
    
    if ((errors == 0)); then
        echo "✅ All boot image build dependencies are installed"
        return 0
    else
        echo "❌ Missing $errors required dependencies"
        return 1
    fi
}

# Check if all required dependencies are installed for version manager
dependency_check_version_manager() {
    local errors=0
    
    echo "🔍 Checking dependencies for version manager..."
    
    # Check essential tools
    is_command_available "gh" "GitHub CLI" || ((errors++))
    is_command_available "curl" "CURL tool" || ((errors++))
    is_command_available "git" "Git version control" || ((errors++))
    is_command_available "sed" "Stream editor" || ((errors++))
    is_command_available "grep" "Grep pattern matcher" || ((errors++))
    is_command_available "date" "Date command" || ((errors++))
    
    if ((errors == 0)); then
        echo "✅ All version manager dependencies are installed"
        return 0
    else
        echo "❌ Missing $errors required dependencies"
        return 1
    fi
}

# ----------------------------- 
# Validation Functions
# ----------------------------- 

# Validate distribution
validate_distribution() {
    local distribution="$1"
    local version="$2"
    local supported=false
    
    # Check if distribution is supported
    for supported_distro in "${SUPPORTED_DISTRIBUTIONS[@]}"; do
        if [[ "$distribution" == "$supported_distro" ]]; then
            supported=true
            break
        fi
    done
    
    if [[ "$supported" == false ]]; then
        echo "❌ Unsupported distribution: $distribution"
        echo "✅ Supported distributions: ${SUPPORTED_DISTRIBUTIONS[*]}"
        return 1
    fi
    
    # Check Ubuntu version if applicable
    if [[ "$distribution" == "ubuntu" && -n "$version" ]]; then
        local version_supported=false
        for supported_ubuntu_version in "${SUPPORTED_UBUNTU_VERSIONS[@]}"; do
            if [[ "$version" == "$supported_ubuntu_version"* ]]; then
                version_supported=true
                break
            fi
        done
        
        if [[ "$version_supported" == false ]]; then
            echo "❌ Unsupported Ubuntu version: $version"
            echo "✅ Supported Ubuntu versions: ${SUPPORTED_UBUNTU_VERSIONS[*]}"
            return 1
        fi
    fi
    
    return 0
}

# Validate kernel version format
validate_kernel_version() {
    local version="$1"
    
    # Basic kernel version validation (x.y or x.y.z format)
    if [[ "$version" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
        return 0
    else
        echo "❌ Invalid kernel version format: $version"
        echo "✅ Expected format: x.y or x.y.z (e.g., 6.18 or 6.18.1)"
        return 1
    fi
}

# Validate GitHub repository format
validate_github_repo() {
    local repo="$1"
    
    # Basic GitHub repository format validation (owner/repo)
    if [[ "$repo" =~ ^[a-zA-Z0-9_-]+\/[a-zA-Z0-9_-]+$ ]]; then
        return 0
    else
        echo "❌ Invalid GitHub repository format: $repo"
        echo "✅ Expected format: owner/repo (e.g., GengWei1997/ubuntu-xiaomi-raphael)"
        return 1
    fi
}

# ----------------------------- 
# Utility Functions
# ----------------------------- 

# Get Ubuntu download URL
get_ubuntu_url() {
    local version="$1"
    local arch="$2"
    
    # Generate Ubuntu base download URL
    local url="${UBUNTU_DOWNLOAD_BASE}/${version}/release/${UBUNTU_IMAGE_TYPE}-${version}-base-${arch}.tar.gz"
    echo "$url"
}

# Set up QEMU for emulation
setup_qemu() {
    local image="$1"
    
    echo "� Setting up QEMU for emulation..."
    echo "Command: qemu-system-aarch64 -machine ${QEMU_MACHINE} -cpu ${QEMU_CPU} -m ${QEMU_MEMORY} -drive format=raw,file=${image} -net ${QEMU_NET} -nographic -append 'console=ttyAMA0 root=/dev/vda2'"
    
    # Check if QEMU is installed
    is_command_available "${QEMU_SYSTEM}" "QEMU system emulator" || return 1
    
    return 0
}

# Generate a timestamp
generate_timestamp() {
    date +"%Y%m%d-%H%M%S"
}

# Create necessary directories
create_directories() {
    echo "📁 Creating necessary directories..."
    mkdir -p "${TEMP_DIR}" "${OUTPUT_DIR}" "${OUTPUT_DIR}/kernel" "${OUTPUT_DIR}/rootfs" "${OUTPUT_DIR}/boot"
}

# ----------------------------- 
# Parameter Validation Functions
# ----------------------------- 

# Validate root filesystem size
validate_rootfs_size() {
    local size="$1"
    
    # Check if size has valid format (e.g., 4G, 10G)
    if [[ "$size" =~ ^[0-9]+[GM]$ ]]; then
        local numeric_size=${size::-1}
        
        # Ensure minimum size is 2G
        if ((numeric_size >= 2)); then
            return 0
        else
            echo "❌ Root filesystem size too small. Minimum size is 2G"
            return 1
        fi
    else
        echo "❌ Invalid root filesystem size format: $size"
        echo "✅ Expected format: [number][G|M] (e.g., 6G, 4096M)"
        return 1
    fi
}

# Validate build threads count
validate_build_threads() {
    local threads="$1"
    
    # Check if threads is a positive integer
    if [[ "$threads" =~ ^[0-9]+$ ]] && ((threads > 0)); then
        return 0
    else
        echo "❌ Invalid build threads count: $threads"
        echo "✅ Expected a positive integer (e.g., 4, 8)"
        return 1
    fi
}

# ----------------------------- 
# Error Handling Functions
# ----------------------------- 

# Print error message and exit
fatal_error() {
    local message="$1"
    echo -e "\033[0;31m❌ FATAL ERROR: $message\033[0m"
    exit 1
}

# Check command execution status
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
# Initialization
# ----------------------------- 

# Source this file to load all configurations and functions
# Example usage: source build-config.sh

# Validate critical configurations on load
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    # This file is being sourced, perform basic validation
    validate_github_repo "${GITHUB_REPO}" || true
    validate_kernel_version "${KERNEL_VERSION_DEFAULT}" || true
fi