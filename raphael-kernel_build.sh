#!/bin/bash
set -e  # Exit on any error

# 参数验证
if [ -z "$1" ]; then
    echo "Usage: $0 <kernel_version>"
    exit 1
fi

KERNEL_VERSION="$1"

# 安装交叉编译工具链（如果尚未安装）
if ! command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    echo "Installing aarch64 cross-compiler..."
    sudo apt-get update
    sudo apt-get install -y gcc-aarch64-linux-gnu g++-aarch64-linux-gnu
fi

# 克隆内核源码
echo "Cloning kernel source for version $KERNEL_VERSION..."
git clone https://github.com/GengWei1997/linux.git --branch raphael-$KERNEL_VERSION --depth 1 linux

cd linux

# 设置内核配置
 echo "Configuring kernel..."
 make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- sm8150.config

# 构建内核
echo "Building kernel..."
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-

# 获取内核版本
_kernel_version="$(make kernelrelease -s)"
echo "Kernel version: $_kernel_version"

# 准备打包目录
cd ..
rm -rf linux-xiaomi-raphael/boot 2>/dev/null || true
mkdir -p linux-xiaomi-raphael/boot

# 复制内核文件
cd linux
cp arch/arm64/boot/Image.gz ../linux-xiaomi-raphael/boot/vmlinuz-$_kernel_version
cp arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb ../linux-xiaomi-raphael/boot/dtb-$_kernel_version

# 更新控制文件版本号
cd ..
sed -i "s/Version:.*/Version: ${_kernel_version}/" linux-xiaomi-raphael/DEBIAN/control

# 安装内核模块
cd linux
rm -rf ../linux-xiaomi-raphael/lib 2>/dev/null || true
make -j$(nproc) ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=../linux-xiaomi-raphael modules_install

# 清理不必要的文件
cd ..
rm -rf linux-xiaomi-raphael/lib/modules/*/build 2>/dev/null || true
rm -rf linux-xiaomi-raphael/lib/modules/*/source 2>/dev/null || true

# 清理内核源码
rm -rf linux

# 构建Debian包
echo "Building Debian packages..."
dpkg-deb --build --root-owner-group linux-xiaomi-raphael linux-xiaomi-raphael_${_kernel_version}_arm64.deb
dpkg-deb --build --root-owner-group firmware-xiaomi-raphael firmware-xiaomi-raphael_${_kernel_version}_arm64.deb
dpkg-deb --build --root-owner-group alsa-xiaomi-raphael alsa-xiaomi-raphael_${_kernel_version}_arm64.deb

echo "Kernel build completed successfully!"
echo "Generated packages:"
ls -la *.deb