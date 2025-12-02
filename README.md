# ? Xiaomi K20 Pro (Raphael) 多发行版 Linux 系统

## ? 项目简介

这是一个专为小米 K20 Pro (代号: Raphael) 定制的多发行版 Linux 系统构建项目，支持 Ubuntu 和 Armbian 系统。通过自动化构建流程，为用户提供完整的 Linux 使用体验。

## ? 构建工作流

项目包含以下自动化构建工作流：

### 1. 内核构建 (Kernel Build)
- **文件**: `.github/workflows/kernel-build.yml`
- **功能**: 构建定制的 Linux 内核包
- **触发**: 手动触发或内核版本更新
- **输出**: 内核 deb 包

### 2. 根文件系统构建 (RootFS Build)
- **文件**: `.github/workflows/main.yml`
- **功能**: 构建完整的根文件系统镜像
- **触发**: 手动触发
- **输出**: rootfs.img 镜像文件

### 3. Boot 镜像构建 (Boot Image Build) - **新增**
- **文件**: `.github/workflows/boot-image.yml`
- **功能**: 创建可启动的 boot 镜像，包含内核和引导配置
- **触发**: 手动触发
- **输出**: xiaomi-k20pro-boot-*.img

## ? Boot 镜像构建说明

### 功能特性
- 自动下载或创建基础 boot 镜像
- 从 rootfs 镜像中提取内核文件 (vmlinuz 和 initrd)
- 自动获取 rootfs 的 UUID 并更新引导配置
- 配置 systemd-boot 引导加载器
- 支持 Ubuntu 和 Armbian 两种发行版

### 目录结构
boot 镜像包含以下结构：
```
xiaomiboot/
├── linux.efi          # 内核文件 (从 rootfs 提取)
├── initramfs          # 初始内存盘 (从 rootfs 提取)
└── loader/
    └── entries/
        └── ubuntu.conf # 引导配置文件
```

### 引导配置示例
```conf
title  Ubuntu
sort-key ubuntu
linux   linux.efi
initrd  initramfs

options console=tty0 loglevel=3 splash root=UUID=ee8d3593-59b1-480e-a3b6-4fefb17ee7d8 rw
```

### 使用方法
1. 在 GitHub Actions 中手动触发 "Boot Image Creation" 工作流
2. 选择内核版本和发行版
3. 工作流会自动下载对应的 rootfs 镜像
4. 构建完成后，下载生成的 boot 镜像
5. 将 boot 镜像刷写到设备的 boot 分区

### 手动构建
```bash
# 使用脚本手动构建
./raphael-boot_build.sh \
  --kernel-version 6.18 \
  --distribution ubuntu \
  --rootfs-image root-ubuntu-6.18.img
```

## ? 构建脚本说明

### raphael-boot_build.sh
- **功能**: Boot 镜像构建主脚本
- **参数**:
  - `-k, --kernel-version`: 内核版本 (必需)
  - `-d, --distribution`: 发行版 (ubuntu/armbian, 默认: ubuntu)
  - `-b, --boot-source`: boot 镜像源 URL (可选)
  - `-r, --rootfs-image`: rootfs 镜像文件 (必需)
  - `-o, --output`: 输出文件 (可选)

### 构建流程
1. **参数验证**: 检查必需参数和权限
2. **下载基础镜像**: 下载原始 boot 镜像或创建空镜像
3. **挂载镜像**: 挂载 boot 镜像到临时目录
4. **提取 UUID**: 从 rootfs 镜像获取 UUID
5. **复制内核文件**: 从 rootfs 提取 vmlinuz 和 initrd
6. **更新配置**: 创建引导配置文件
7. **验证内容**: 检查关键文件是否存在
8. **保存镜像**: 卸载并保存最终的 boot 镜像

## ? 注意事项

1. **依赖关系**: Boot 镜像构建需要先有对应的 rootfs 镜像
2. **UUID 匹配**: 引导配置中的 UUID 必须与 rootfs 镜像的实际 UUID 一致
3. **镜像大小**: 默认创建 64MB 的 boot 镜像，可根据需要调整
4. **引导兼容性**: 使用 systemd-boot 引导加载器，确保设备支持
