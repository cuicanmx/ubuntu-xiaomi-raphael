#!/bin/bash

# Build configuration file for Raphael Multi-Distro Linux
# Centralized configuration management

# Version and URL configurations
UBUNTU_VERSION="24.04.3"
KERNEL_VERSION_DEFAULT="6.17.0"

# Base URLs
UBUNTU_BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases"
ARMBIAN_BASE_URL="https://github.com/ophub/amlogic-s9xxx-armbian/releases"

# QEMU configuration
QEMU_VERSION="v7.2.0-1"
QEMU_DOWNLOAD_URL="https://github.com/multiarch/qemu-user-static/releases/download"

# System configuration
ROOTFS_SIZE="6G"
HOSTNAME="xiaomi-raphael"
DNS_SERVER="1.1.1.1"
DEFAULT_USER="ubuntu"
DEFAULT_PASSWORD="1234"

# Package names
KERNEL_PACKAGE="linux-xiaomi-raphael"
FIRMWARE_PACKAGE="firmware-xiaomi-raphael"
ALSA_PACKAGE="alsa-xiaomi-raphael"

# Directory names
KERNEL_DEBS_DIR="kernel-debs"
DEVICE_DEBS_DIR_PREFIX="xiaomi-raphael-debs"

# Supported distributions and versions
SUPPORTED_DISTROS=("ubuntu" "armbian")
UBUNTU_VERSIONS=("noble" "jammy" "focal")
ARMBIAN_VERSIONS=("noble")

# Desktop environments for Ubuntu
UBUNTU_DESKTOP_ENVS=(
    "ubuntu-desktop"
    "kubuntu-desktop" 
    "xubuntu-desktop"
    "lubuntu-desktop"
    "ubuntu-mate"
    "ubuntu-server"
)

# Function to get Ubuntu download URL
get_ubuntu_url() {
    local version=$1
    echo "${UBUNTU_BASE_URL}/${version}/release/ubuntu-base-${UBUNTU_VERSION}-base-arm64.tar.gz"
}

# Function to get Armbian download URL
get_armbian_url() {
    local version=$1
    case "$version" in
        "noble")
            echo "${ARMBIAN_BASE_URL}/download/Armbian_noble_arm64_server_2025.12/Armbian_25.11.0-noble_arm64_6.12.59_rootfs.tar.gz"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Function to validate distribution and version
validate_distribution() {
    local distro=$1
    local version=$2
    
    case "$distro" in
        "ubuntu")
            if [[ ! " ${UBUNTU_VERSIONS[@]} " =~ " ${version} " ]]; then
                echo "❌ Unsupported Ubuntu version: $version"
                echo "✅ Supported versions: ${UBUNTU_VERSIONS[*]}"
                return 1
            fi
            ;;
        "armbian")
            if [[ ! " ${ARMBIAN_VERSIONS[@]} " =~ " ${version} " ]]; then
                echo "❌ Unsupported Armbian version: $version"
                echo "✅ Supported versions: ${ARMBIAN_VERSIONS[*]}"
                return 1
            fi
            ;;
        *)
            echo "❌ Unsupported distribution: $distro"
            echo "✅ Supported distributions: ${SUPPORTED_DISTROS[*]}"
            return 1
            ;;
    esac
    return 0
}

# Function to get device packages directory name
get_device_debs_dir() {
    local kernel_version=$1
    echo "${DEVICE_DEBS_DIR_PREFIX}_${kernel_version}"
}

# Function to check if running on ARM64 architecture
is_arm64_architecture() {
    uname -m | grep -q aarch64
}

# Function to setup QEMU for cross-architecture builds
setup_qemu_emulation() {
    if ! is_arm64_architecture; then
        echo "🔧 Setting up QEMU for cross-architecture emulation..."
        wget "$QEMU_DOWNLOAD_URL/$QEMU_VERSION/qemu-aarch64-static" || return 1
        install -m755 qemu-aarch64-static "$1/"
        
        # Register binfmt handlers
        echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
        echo ':aarch64ld:M::\x7fELF\x02\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
    fi
}

# Function to cleanup QEMU after build
cleanup_qemu_emulation() {
    if ! is_arm64_architecture; then
        echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64 2>/dev/null || true
        echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64ld 2>/dev/null || true
        rm -f qemu-aarch64-static 2>/dev/null || true
    fi
}

# Function to validate package installation
validate_package_installation() {
    local package=$1
    local rootdir=$2
    
    if chroot "$rootdir" dpkg -l | grep -q "^ii.*$package"; then
        return 0
    else
        return 1
    fi
}

# Export functions for use in other scripts
export -f get_ubuntu_url get_armbian_url validate_distribution get_device_debs_dir is_arm64_architecture setup_qemu_emulation cleanup_qemu_emulation validate_package_installation