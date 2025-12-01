#!/bin/bash

# Enhanced rootfs build script with multi-desktop and Debian support

if [ "$(id -u)" -ne 0 ]
then
  echo "❌ rootfs can only be built as root"
  exit 1
fi

# Parse command line arguments
if [ $# -lt 3 ]; then
  echo "Usage: $0 <distro> <desktop> <kernel_version>"
  echo "  distro: ubuntu|debian"
  echo "  desktop: ubuntu-desktop|ubuntu-server|kubuntu-desktop|xubuntu-desktop|lubuntu-desktop|ubuntu-mate|gnome|kde|xfce|lxde|mate|server"
  echo "  kernel_version: e.g., 6.17"
  exit 1
fi

DISTRO=$1
DESKTOP=$2
KERNEL_VERSION=$3

# Set distribution-specific variables
case "$DISTRO" in
  "ubuntu")
    VERSION="noble"
    UBUNTU_VERSION="24.04.3"
    BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/$VERSION/release"
    BASE_FILE="ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz"
    ;;
  "debian")
    VERSION="bookworm"
    DEBIAN_VERSION="12"
    BASE_URL="https://cdimage.debian.org/debian-cd/current/arm64/iso-cd"
    BASE_FILE="debian-$DEBIAN_VERSION.0-arm64-netinst.iso"
    # For Debian we'll use debootstrap instead
    ;;
  *)
    echo "❌ Unsupported distribution: $DISTRO"
    exit 1
    ;;
esac

echo "📦 Building $DISTRO rootfs with $DESKTOP environment"
echo "📋 Kernel version: $KERNEL_VERSION"

# Create rootfs image
truncate -s 6G rootfs.img
mkfs.ext4 rootfs.img
mkdir rootdir
mount -o loop rootfs.img rootdir

# Download and extract base system
if [ "$DISTRO" = "ubuntu" ]; then
  echo "📥 Downloading Ubuntu base system..."
  wget "$BASE_URL/$BASE_FILE"
  tar xzvf "$BASE_FILE" -C rootdir
  # Keep base file for debugging
else
  echo "📥 Using debootstrap for Debian..."
  # Install debootstrap if not available
  if ! command -v debootstrap >/dev/null 2>&1; then
    echo "📦 Installing debootstrap..."
    apt update && apt install -y debootstrap
  fi
  
  # Use debootstrap to create Debian system
  debootstrap --arch=arm64 "$VERSION" rootdir http://deb.debian.org/debian/
fi

# Mount required filesystems
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount --bind /proc rootdir/proc
mount --bind /sys rootdir/sys

# Configure basic system settings
echo "⚙️ Configuring system settings..."
echo "nameserver 223.5.5.5" | tee rootdir/etc/resolv.conf
echo "xiaomi-raphael" | tee rootdir/etc/hostname
echo "127.0.0.1 localhost
127.0.1.1 xiaomi-raphael" | tee rootdir/etc/hosts

# Setup QEMU for cross-architecture builds
if ! uname -m | grep -q aarch64; then
  echo "🔧 Setting up QEMU for cross-architecture build..."
  wget -q https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static
  install -m755 qemu-aarch64-static rootdir/

  echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
  echo ':aarch64ld:M::\x7fELF\x02\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
fi

# Chroot environment setup
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
export DEBIAN_FRONTEND=noninteractive

# Update package lists
echo "🔄 Updating package lists..."
chroot rootdir apt update
chroot rootdir apt upgrade -y

# Install base packages
echo "📦 Installing base packages..."
chroot rootdir apt install -y bash-completion sudo ssh nano u-boot-tools locales

# Configure locale
chroot rootdir locale-gen en_US.UTF-8
chroot rootdir update-locale LANG=en_US.UTF-8

# Install desktop environment or server packages
case "$DESKTOP" in
  "ubuntu-desktop"|"gnome")
    echo "🖥️ Installing GNOME desktop environment..."
    chroot rootdir apt install -y ubuntu-desktop
    ;;
  "ubuntu-server"|"server")
    echo "🖥️ Installing server packages..."
    chroot rootdir apt install -y openssh-server net-tools htop
    ;;
  "kubuntu-desktop"|"kde")
    echo "🖥️ Installing KDE Plasma desktop environment..."
    chroot rootdir apt install -y kubuntu-desktop
    ;;
  "xubuntu-desktop"|"xfce")
    echo "🖥️ Installing XFCE desktop environment..."
    chroot rootdir apt install -y xubuntu-desktop
    ;;
  "lubuntu-desktop"|"lxde")
    echo "🖥️ Installing LXDE desktop environment..."
    chroot rootdir apt install -y lubuntu-desktop
    ;;
  "ubuntu-mate"|"mate")
    echo "🖥️ Installing MATE desktop environment..."
    chroot rootdir apt install -y ubuntu-mate-desktop
    ;;
  *)
    echo "⚠️ Using minimal desktop environment..."
    chroot rootdir apt install -y xorg xserver-xorg-core
    ;;
esac

# Device-specific packages
echo "📱 Installing device-specific packages..."
chroot rootdir apt install -y rmtfs protection-domain-mapper tqftpserv

# Remove laptop-specific service checks
sed -i '/ConditionKernelVersion/d' rootdir/lib/systemd/system/pd-mapper.service

# Install kernel and drivers
echo "🔧 Installing kernel and drivers..."
cp /home/runner/work/ubuntu-xiaomi-raphael/ubuntu-xiaomi-raphael/xiaomi-raphael-debs_$KERNEL_VERSION/*-xiaomi-raphael.deb rootdir/tmp/
chroot rootdir dpkg -i /tmp/linux-xiaomi-raphael.deb
chroot rootdir dpkg -i /tmp/firmware-xiaomi-raphael.deb
chroot rootdir dpkg -i /tmp/alsa-xiaomi-raphael.deb
rm rootdir/tmp/*-xiaomi-raphael.deb

# EFI and boot configuration
echo "🔧 Configuring boot system..."
chroot rootdir apt install -y grub-efi-arm64

# Configure GRUB
sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' rootdir/etc/default/grub
sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT=""/' rootdir/etc/default/grub

# Create fstab
echo "PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee rootdir/etc/fstab

# Setup default user (ubuntu:1234)
echo "👤 Creating default user..."
chroot rootdir useradd -m -s /bin/bash -G sudo ubuntu
echo 'ubuntu:1234' | chroot rootdir chpasswd

# Setup GDM for graphical login
if [[ "$DESKTOP" != "server" && "$DESKTOP" != "ubuntu-server" ]]; then
  echo "🖥️ Setting up graphical login..."
  mkdir -p rootdir/var/lib/gdm
  touch rootdir/var/lib/gdm/run-initial-setup
  
  # Enable automatic login for default user
  mkdir -p rootdir/etc/gdm3
  echo "[daemon]
AutomaticLoginEnable=true
AutomaticLogin=ubuntu" > rootdir/etc/gdm3/custom.conf
fi

# Clean up package cache
chroot rootdir apt clean

# Cleanup QEMU setup
if ! uname -m | grep -q aarch64; then
  echo "🧹 Cleaning up QEMU setup..."
  echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64
  echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64ld
  rm -f rootdir/qemu-aarch64-static qemu-aarch64-static
fi

# Unmount filesystems
echo "🔧 Unmounting filesystems..."
umount rootdir/sys
umount rootdir/proc
umount rootdir/dev/pts
umount rootdir/dev
umount rootdir

rm -d rootdir

echo '✅ RootFS build completed successfully!'
echo '📋 Boot command: "root=PARTLABEL=linux"'
echo '👤 Default login: ubuntu / 1234'

# Compress rootfs
7z a rootfs.7z rootfs.img

echo "🎉 $DISTRO $DESKTOP rootfs build completed!"
