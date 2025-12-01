#!/bin/bash

# Enhanced kernel build script with better error handling and Debian support

# Use GITHUB_WORKSPACE if available, otherwise default to current directory
BASE_DIR=${GITHUB_WORKSPACE:-.}

# Parse command line arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <kernel_version> [distro]"
  echo "  kernel_version: e.g., 6.17"
  echo "  distro: ubuntu|debian (optional, default: ubuntu)"
  exit 1
fi

KERNEL_VERSION=$1
DISTRO=${2:-ubuntu}

echo "📁 Using base directory: $BASE_DIR"
echo "🔧 Building kernel for $DISTRO, version: $KERNEL_VERSION"
cd "$BASE_DIR" || { echo "❌ Failed to change to base directory"; exit 1; }

# Auto-install cross-compilation tools if not available
if ! which aarch64-linux-gnu-gcc > /dev/null; then
  echo "⚠️ aarch64-linux-gnu-gcc not found. Installing cross-compilation tools..."
  sudo apt-get update && sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu || {
    echo "❌ Failed to install cross-compilation tools"
    exit 1
  }
fi

# Install additional build dependencies for Debian compatibility
if [ "$DISTRO" = "debian" ]; then
  echo "📦 Installing Debian-specific build dependencies..."
  sudo apt-get install -y libssl-dev libelf-dev bc kmod cpio flex bison dwarves || {
    echo "❌ Failed to install Debian build dependencies"
    exit 1
  }
fi

# Calculate optimal jobs for parallel build (use 75% of available cores)
JOBS=$(( ($(nproc) * 3) / 4 ))
if [ $JOBS -lt 1 ]; then
  JOBS=1
fi
echo "🔧 Using $JOBS parallel jobs for compilation"

# Clone kernel source with better error handling
echo "📥 Cloning kernel source..."
if [ -d "linux" ]; then
  echo "🧹 Removing existing kernel directory..."
  rm -rf linux
fi

git clone https://github.com/GengWei1997/linux.git --branch raphael-$KERNEL_VERSION --depth 1 linux || {
  echo "❌ Failed to clone kernel source"
  echo "💡 Try checking if the branch 'raphael-$KERNEL_VERSION' exists"
  exit 1
}

cd linux || { echo "❌ Failed to change to kernel directory"; exit 1; }

# Configure kernel with verbose output for debugging
echo "⚙️ Configuring kernel..."
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- defconfig || {
  echo "❌ Failed to create default config"
  exit 1
}

# Apply device-specific configuration
if [ -f "sm8150.config" ]; then
  echo "🔧 Applying sm8150 configuration..."
  make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- sm8150.config || {
    echo "⚠️ Failed to apply sm8150 config, continuing with default..."
  }
fi

# Build kernel with proper error handling
echo "🔨 Building kernel..."
make -j$JOBS ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- || {
  echo "❌ Kernel build failed"
  echo "💡 Check kernel configuration and dependencies"
  exit 1
}

_kernel_version="$(make kernelrelease -s)"
echo "📋 Kernel version: $_kernel_version"

# Create output directories
echo "📂 Creating output directories..."
mkdir -p "$BASE_DIR/linux-xiaomi-raphael/boot" || {
  echo "❌ Failed to create boot directory"
  exit 1
}

# Copy kernel artifacts with verification
echo "📦 Copying kernel artifacts..."
if [ ! -f "arch/arm64/boot/Image.gz" ]; then
  echo "❌ Kernel image not found at arch/arm64/boot/Image.gz"
  exit 1
fi

cp arch/arm64/boot/Image.gz "$BASE_DIR/linux-xiaomi-raphael/boot/vmlinuz-$_kernel_version" || {
  echo "❌ Failed to copy kernel image"
  exit 1
}

if [ ! -f "arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb" ]; then
  echo "❌ Device tree not found at arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb"
  exit 1
fi

cp arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb "$BASE_DIR/linux-xiaomi-raphael/boot/dtb-$_kernel_version" || {
  echo "❌ Failed to copy device tree"
  exit 1
}

# Update package control file with proper versioning
echo "📝 Updating package control file..."
if [ -f "$BASE_DIR/linux-xiaomi-raphael/DEBIAN/control" ]; then
  sed -i "s/Version:.*/Version: ${_kernel_version}/" "$BASE_DIR/linux-xiaomi-raphael/DEBIAN/control" || {
    echo "⚠️ Failed to update control file version"
  }
  
  # Update description for Debian compatibility
  if [ "$DISTRO" = "debian" ]; then
    sed -i "s/Section: kernel/Section: kernel/" "$BASE_DIR/linux-xiaomi-raphael/DEBIAN/control"
    echo "🔧 Updated package for Debian compatibility"
  fi
else
  echo "⚠️ Control file not found, creating basic one..."
  mkdir -p "$BASE_DIR/linux-xiaomi-raphael/DEBIAN"
  cat > "$BASE_DIR/linux-xiaomi-raphael/DEBIAN/control" << EOF
Package: linux-xiaomi-raphael
Version: $_kernel_version
Architecture: arm64
Maintainer: Raphael Build System <build@raphael.dev>
Section: kernel
Description: Custom Linux kernel for Xiaomi K20 Pro (Raphael)
 Built for $DISTRO with version $_kernel_version
EOF
fi

# Clean old modules
echo "🧹 Cleaning old modules..."
rm -rf "$BASE_DIR/linux-xiaomi-raphael/lib"

# Install kernel modules
echo "📦 Installing kernel modules..."
make -j$JOBS ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH="$BASE_DIR/linux-xiaomi-raphael" modules_install || {
  echo "❌ Failed to install kernel modules"
  exit 1
}

# Clean up build links
echo "🧹 Cleaning up build links..."
find "$BASE_DIR/linux-xiaomi-raphael/lib/modules" -name "build" -delete
find "$BASE_DIR/linux-xiaomi-raphael/lib/modules" -name "source" -delete

# Return to base directory
cd "$BASE_DIR" || { echo "❌ Failed to return to base directory"; exit 1; }

# Clean up source code to save space
echo "🧹 Cleaning up source code to save space..."
rm -rf linux

# Build Debian packages with enhanced error handling
echo "📦 Building Debian packages..."

# Build kernel package
if [ -d "linux-xiaomi-raphael" ]; then
  dpkg-deb --build --root-owner-group linux-xiaomi-raphael || {
    echo "❌ Failed to build linux-xiaomi-raphael package"
    exit 1
  }
  echo "✅ linux-xiaomi-raphael.deb built successfully"
else
  echo "❌ linux-xiaomi-raphael directory not found"
  exit 1
fi

# Build firmware package
if [ -d "firmware-xiaomi-raphael" ]; then
  dpkg-deb --build --root-owner-group firmware-xiaomi-raphael || {
    echo "❌ Failed to build firmware-xiaomi-raphael package"
    exit 1
  }
  echo "✅ firmware-xiaomi-raphael.deb built successfully"
else
  echo "❌ firmware-xiaomi-raphael directory not found"
  exit 1
fi

# Build ALSA package
if [ -d "alsa-xiaomi-raphael" ]; then
  dpkg-deb --build --root-owner-group alsa-xiaomi-raphael || {
    echo "❌ Failed to build alsa-xiaomi-raphael package"
    exit 1
  }
  echo "✅ alsa-xiaomi-raphael.deb built successfully"
else
  echo "❌ alsa-xiaomi-raphael directory not found"
  exit 1
fi

echo "🎉 All packages built successfully for $DISTRO!"
echo "📋 Kernel version: $_kernel_version"
echo "📦 Packages created:"
ls -la *.deb