#!/bin/bash

# Enhanced rootfs build script with Armbian support, skip kernel build option, and better error handling

if [ "$(id -u)" -ne 0 ]
then
  echo "? RootFS can only be built as root"
  exit 1
fi

# Parse command line arguments
if [ $# -lt 3 ]; then
  echo "Usage: $0 <distribution> <version> <kernel_version> [desktop_environment] [--skip-kernel-build]"
  echo "  distribution: ubuntu|armbian"
  echo "  version: for ubuntu: version name, for armbian: noble"
  echo "  kernel_version: e.g., 6.17"
  echo "  desktop_environment: (optional) for ubuntu only"
  echo "  --skip-kernel-build: (optional) use existing device packages instead of building kernel"
  exit 1
fi

DISTRO=$1
VERSION=$2
KERNEL_VERSION=$3

# Check for skip kernel build flag
SKIP_KERNEL_BUILD=false
if [ $# -ge 4 ] && [ "$4" = "--skip-kernel-build" ]; then
  SKIP_KERNEL_BUILD=true
fi
if [ $# -ge 5 ] && [ "$5" = "--skip-kernel-build" ]; then
  SKIP_KERNEL_BUILD=true
fi

# Set distribution-specific variables
case "$DISTRO" in
  "ubuntu")
    UBUNTU_VERSION="24.04.3"
    BASE_URL="https://cdimage.ubuntu.com/ubuntu-base/releases/$VERSION/release/ubuntu-base-$UBUNTU_VERSION-base-arm64.tar.gz"
    ;;
  "armbian")
    case "$VERSION" in
      "noble")
        BASE_URL="https://github.com/ophub/amlogic-s9xxx-armbian/releases/download/Armbian_noble_arm64_server_2025.12/Armbian_25.11.0-noble_arm64_6.12.59_rootfs.tar.gz"
        ;;
      *)
        echo "? Unsupported Armbian version: $VERSION"
        echo "? Supported versions: noble"
        exit 1
        ;;
    esac
    ;;
  *)
    echo "? Unsupported distribution: $DISTRO"
    exit 1
    ;;
esac

echo "? Starting RootFS build for $DISTRO $VERSION"
echo "? Kernel version: $KERNEL_VERSION"

# Create rootfs image with error handling
echo "? Creating rootfs image..."
truncate -s 6G rootfs.img || { echo "? Failed to create rootfs image"; exit 1; }
mkfs.ext4 rootfs.img || { echo "? Failed to format rootfs image"; exit 1; }
mkdir -p rootdir || { echo "? Failed to create rootdir"; exit 1; }
mount -o loop rootfs.img rootdir || { echo "? Failed to mount rootfs image"; exit 1; }

# Download base system
echo "? Downloading base system for $DISTRO $VERSION..."
wget -q --show-progress "$BASE_URL" || { echo "? Failed to download $DISTRO base"; exit 1; }

# Extract based on file type
if [[ "$BASE_URL" == *.tar.gz ]]; then
  tar xzvf "$(basename "$BASE_URL")" -C rootdir || { echo "? Failed to extract $DISTRO base"; exit 1; }
elif [[ "$BASE_URL" == *.tar.xz ]]; then
  tar xJvf "$(basename "$BASE_URL")" -C rootdir || { echo "? Failed to extract $DISTRO base"; exit 1; }
else
  echo "? Unsupported archive format: $BASE_URL"
  exit 1
fi

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount --bind /proc rootdir/proc
mount --bind /sys rootdir/sys

echo "nameserver 1.1.1.1" | tee rootdir/etc/resolv.conf
echo "xiaomi-raphael" | tee rootdir/etc/hostname
echo "127.0.0.1 localhost
127.0.1.1 xiaomi-raphael" | tee rootdir/etc/hosts

if uname -m | grep -q aarch64
then
  echo "cancel qemu install for arm64"
else
  wget https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static
  install -m755 qemu-aarch64-static rootdir/

  echo ':aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
  #ldconfig.real abi=linux type=dynamic
  echo ':aarch64ld:M::\x7fELF\x02\x01\x01\x03\x00\x00\x00\x00\x00\x00\x00\x00\x03\x00\xb7:\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/qemu-aarch64-static:' | tee /proc/sys/fs/binfmt_misc/register
fi


# Setup chroot environment
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH
export DEBIAN_FRONTEND=noninteractive

# Distribution-specific setup
if [ "$DISTRO" = "ubuntu" ]; then
  # Ubuntu-specific setup
  echo "? Setting up Ubuntu system..."
  chroot rootdir apt update
  chroot rootdir apt upgrade -y
  
  # Install basic packages for Ubuntu
  chroot rootdir apt install -y bash-completion sudo ssh nano initramfs-tools u-boot-tools- $1
  
  # Device specific packages for Ubuntu
  chroot rootdir apt install -y rmtfs protection-domain-mapper tqftpserv
  
  # Remove check for "*-laptop"
  sed -i '/ConditionKernelVersion/d' rootdir/lib/systemd/system/pd-mapper.service
  
elif [ "$DISTRO" = "armbian" ]; then
  # Armbian-specific setup
  echo "? Setting up Armbian system..."
  
  # Armbian already has a functional system, just update package lists
  chroot rootdir apt update
  
  # Install additional packages needed for Xiaomi K20 Pro
  chroot rootdir apt install -y sudo ssh nano initramfs-tools
  
  # Armbian may have different package names, install device-specific packages
  chroot rootdir apt install -y rmtfs-mgr protection-domain-mapper tqftpserv || {
    echo "?? Some device packages not available in Armbian, continuing..."
  }
  
  # Remove check for "*-laptop" if the service exists
  if [ -f "rootdir/lib/systemd/system/pd-mapper.service" ]; then
    sed -i '/ConditionKernelVersion/d' rootdir/lib/systemd/system/pd-mapper.service
  fi
fi

# Install device packages (common for both distributions)
echo "? Installing device packages..."

if [ "$SKIP_KERNEL_BUILD" = "true" ]; then
  echo "? Skipping kernel build, using existing device packages..."
  # Check if device packages directory exists
  if [ -d "xiaomi-raphael-debs_$KERNEL_VERSION" ]; then
    cp xiaomi-raphael-debs_$KERNEL_VERSION/*-xiaomi-raphael.deb rootdir/tmp/ || { echo "?? Failed to copy existing device packages"; exit 1; }
  else
    echo "?? Device packages directory not found: xiaomi-raphael-debs_$KERNEL_VERSION"
    echo "?? Please ensure device packages are available or remove --skip-kernel-build flag"
    exit 1
  fi
else
  echo "? Using freshly built device packages..."
  # Ensure kernel build directory exists
  if [ ! -d "kernel-debs" ]; then
    echo "?? Kernel packages directory not found: kernel-debs"
    echo "?? Please build kernel first or use --skip-kernel-build flag"
    exit 1
  fi
  cp kernel-debs/*-xiaomi-raphael.deb rootdir/tmp/ || { echo "?? Failed to copy kernel packages"; exit 1; }
fi

chroot rootdir dpkg -i /tmp/linux-xiaomi-raphael.deb || { echo "?? Kernel package installation had issues"; }
chroot rootdir dpkg -i /tmp/firmware-xiaomi-raphael.deb || { echo "?? Firmware package installation had issues"; }
chroot rootdir dpkg -i /tmp/alsa-xiaomi-raphael.deb || { echo "?? ALSA package installation had issues"; }
rm rootdir/tmp/*-xiaomi-raphael.deb

# Update initramfs
chroot rootdir update-initramfs -c -k all || { echo "?? Initramfs update had issues"; }

# EFI and boot setup
if [ "$DISTRO" = "ubuntu" ]; then
  # Install GRUB for EFI
  chroot rootdir apt install -y grub-efi-arm64
  
  # Configure GRUB
  sed --in-place 's/^#GRUB_DISABLE_OS_PROBER=false/GRUB_DISABLE_OS_PROBER=false/' rootdir/etc/default/grub
  sed --in-place 's/GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"/GRUB_CMDLINE_LINUX_DEFAULT=""/' rootdir/etc/default/grub
  
  # Create fstab for Ubuntu
  echo "PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee rootdir/etc/fstab
  
  # Setup GDM for Ubuntu desktop
  mkdir -p rootdir/var/lib/gdm
  touch rootdir/var/lib/gdm/run-initial-setup
  
elif [ "$DISTRO" = "armbian" ]; then
  # Armbian already has boot setup, just ensure fstab is correct
  echo "PARTLABEL=linux / ext4 errors=remount-ro,x-systemd.growfs 0 1
PARTLABEL=esp /boot/efi vfat umask=0077 0 1" | tee rootdir/etc/fstab
  
  # Ensure Armbian has necessary boot tools
  chroot rootdir apt install -y u-boot-tools || echo "?? U-Boot tools installation had issues"
fi

# Clean up packages
chroot rootdir apt clean

if uname -m | grep -q aarch64
then
  echo "cancel qemu install for arm64"
else
  #Remove qemu emu
  echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64
  echo -1 | tee /proc/sys/fs/binfmt_misc/aarch64ld
  rm rootdir/qemu-aarch64-static
  rm qemu-aarch64-static
fi

umount rootdir/sys
umount rootdir/proc
umount rootdir/dev/pts
umount rootdir/dev
umount rootdir

rm -d rootdir

echo 'cmdline for legacy boot: "root=PARTLABEL=linux"'

7z a rootfs.7z rootfs.img