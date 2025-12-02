
# Multi-Distro Linux for Xiaomi K20 Pro (Raphael)

## ? 项目概述

这是一个为小米K20 Pro (代号: Raphael) 设备定制的多发行版Linux系统构建项目，支持Ubuntu和Armbian系统。本项目提供完整的自动化构建流程，支持多种发行版（Ubuntu/Armbian）、多种桌面环境（GNOME/KDE/XFCE等）和服务器版选择，为用户提供流畅的Linux使用体验。

## ? 主要特性

- ? **多发行版支持** - 支持Ubuntu和Armbian系统构建
- ? **多桌面环境** - 支持GNOME、KDE、XFCE、LXDE、MATE等多种桌面环境（Ubuntu）
- ? **服务器版支持** - 提供轻量级服务器版系统（Ubuntu）
- ? **Armbian支持** - 基于Armbian官方rootfs，提供优化的ARM系统体验
- ? **自动化构建系统** - 基于GitHub Actions的完整CI/CD流水线
- ? **多版本支持** - 支持自定义内核版本（6.17+）
- ? **固件集成** - 设备专用固件和驱动
- ? **默认用户配置** - 预置ubuntu用户（密码：1234）
- ? **错误处理** - 完善的构建错误检测和恢复机制

## ? 系统要求

### 自动构建 (GitHub Actions)
- GitHub账户
- 足够的存储空间用于构建产物

### 手动构建
- 操作系统: Linux发行版 (推荐Ubuntu 20.04+)
- 硬件要求: 至少8GB RAM, 50GB可用磁盘空间
- 依赖工具: git, build-essential, fakeroot, dpkg-dev, debootstrap, 7z, ccache
- 权限要求: 构建根文件系统需要root权限

## ? 快速开始

### 自动构建 (推荐)

1. **访问GitHub Actions**: 进入项目仓库的Actions页面
2. **手动触发构建**: 点击 "Raphael Multi-Distro Kernel and RootFS Builder" 工作流
3. **配置构建参数**:
   - `kernel_version`: 内核版本 (默认: 6.17)
   - `distribution`: 发行版选择 (Ubuntu/Armbian，默认: Ubuntu)
   - `desktop_environment`: 桌面环境或服务器版 (支持: ubuntu-desktop、kubuntu-desktop、xubuntu-desktop、lubuntu-desktop、ubuntu-mate、gnome、kde、xfce、lxde、mate、server等，默认: ubuntu-desktop)
   - `release_tag`: 发布标签 (默认: v1.0.0)
4. **监控构建进度**: 查看Actions日志实时监控构建过程
5. **下载镜像**: 构建完成后，在Releases页面下载生成的镜像文件

### 手动构建

```bash
# 安装必要依赖
sudo apt update
sudo apt install -y git build-essential fakeroot dpkg-dev debootstrap p7zip-full ccache

# 克隆仓库
git clone https://github.com/your-username/ubuntu-xiaomi-raphael.git
cd ubuntu-xiaomi-raphael

# 构建内核 (不需要root权限)
bash ./raphael-kernel_build.sh 6.17 ubuntu

# 构建根文件系统 (需要root权限)
# Ubuntu构建
sudo bash ./raphael-rootfs_build.sh ubuntu ubuntu-desktop 6.17

# Armbian构建
sudo bash ./raphael-rootfs_build.sh armbian noble 6.17.0
```

## ?? 构建指南

### 本地构建

1. **克隆项目**:
   ```bash
   git clone https://github.com/your-username/ubuntu-xiaomi-raphael.git
   cd ubuntu-xiaomi-raphael
   ```

2. **构建内核**:
   ```bash
   sudo bash ./raphael-kernel_build.sh
   # 或者指定内核版本
   sudo bash ./raphael-kernel_build.sh 6.17.0
   ```

3. **构建根文件系统**:
   ```bash
   # Ubuntu构建
   sudo bash ./raphael-rootfs_build.sh ubuntu noble 6.17.0 ubuntu-desktop
   
   # Armbian构建
   sudo bash ./raphael-rootfs_build.sh armbian noble 6.17.0
   ```

### GitHub Actions构建

1. **访问项目页面**: 打开GitHub仓库页面
2. **手动触发构建**: 点击"Actions"标签页，选择"Raphael Multi-Distro Kernel and RootFS Builder"工作流
3. **配置构建参数**:
   - **Distribution**: 选择发行版 (ubuntu/armbian)
   - **Version**: 选择版本 (noble/jammy/focal)
   - **Desktop environment**: 选择桌面环境 (仅Ubuntu需要)
   - **Kernel version**: 输入内核版本 (默认: 6.17.0)
4. **开始构建**: 点击"Run workflow"按钮

## ? 支持的发行版和桌面环境

### 支持的发行版
- Ubuntu (noble, jammy, focal)
- Armbian (noble)

### 支持的桌面环境（Ubuntu）
- GNOME (ubuntu-desktop)
- KDE Plasma (kubuntu-desktop)
- XFCE (xubuntu-desktop)
- LXDE (lubuntu-desktop)
- MATE (ubuntu-mate)
- 服务器版 (ubuntu-server)

### Armbian特性
- 基于Armbian官方rootfs构建
- 针对ARM架构优化
- 包含必要的设备驱动和固件
- 轻量级系统体验

### 默认用户配置
所有构建版本均预置默认用户：
- **用户名**: ubuntu
- **密码**: 1234
- **自动登录**: 桌面环境启用自动登录

## ? 项目结构

```
├── .github/workflows/main.yml    # GitHub Actions工作流配置
├── raphael-kernel_build.sh       # 内核构建脚本
├── raphael-rootfs_build.sh       # 根文件系统构建脚本
├── linux-xiaomi-raphael/         # 内核DEB包配置文件
├── firmware-xiaomi-raphael/      # 设备固件DEB包配置
├── alsa-xiaomi-raphael/          # 音频驱动DEB包配置
└── workflow_tests/               # 工作流测试目录
```

## ? 网络配置

- **默认DNS服务器**: `223.5.5.5` (阿里云DNS)
- **自动配置**: 根文件系统构建过程中自动设置，提供稳定的国内网络连接
- **自定义配置**: 系统安装后可通过编辑 `/etc/resolv.conf` 修改DNS设置

## ? 安装指南

### 准备工作
1. **解锁Bootloader**: 确保小米K20 Pro已解锁Bootloader
2. **下载TWRP**: 下载适用于Raphael的TWRP恢复镜像
3. **准备存储**: 确保设备有足够的存储空间（建议16GB以上）

### Ubuntu安装步骤
1. **刷入TWRP**: 通过Fastboot刷入TWRP恢复
2. **进入恢复模式**: 重启设备进入TWRP
3. **刷入系统**: 在TWRP中刷入构建好的Ubuntu系统镜像
4. **安装内核**: 刷入对应的内核包
5. **重启系统**: 重启设备进入新系统

### Armbian安装步骤
1. **刷入TWRP**: 通过Fastboot刷入TWRP恢复
2. **进入恢复模式**: 重启设备进入TWRP
3. **刷入系统**: 在TWRP中刷入构建好的Armbian系统镜像
4. **安装内核**: 刷入对应的内核包
5. **重启系统**: 重启设备进入新系统

### 首次启动配置
- **用户名**: `raphael`
- **密码**: `raphael`
- **Root权限**: 默认启用，密码为`raphael`

## ?? 故障排除

### 常见问题

1. **构建失败**
   - 检查网络连接是否正常
   - 确保有足够的磁盘空间（至少10GB）
   - 查看详细的错误日志进行诊断
   - 对于Debian构建，确保已安装debootstrap

2. **内核模块加载失败**
   - 检查内核版本是否匹配
   - 验证模块依赖关系
   - 确保发行版与内核版本兼容

3. **音频问题**
   - 检查ALSA配置是否正确
   - 验证音频设备识别

4. **网络连接问题**
   - 检查网络接口配置
   - 验证DNS设置

5. **桌面环境问题**
   - 确保选择的桌面环境与发行版兼容
   - 检查桌面环境包是否正确安装
   - 验证自动登录配置

6. **用户登录问题**
   - 默认用户：ubuntu，密码：1234
   - 检查用户创建和权限设置
   - 验证自动登录配置

### 调试技巧
- 使用 `dmesg` 查看系统启动日志
- 通过 `journalctl` 检查系统服务状态
- 构建问题可查看详细的工作流日志

## ? 贡献指南

欢迎提交Issue和Pull Request来改进本项目。贡献前请确保：
- 代码风格与现有项目保持一致
- 添加必要的注释和文档
- 测试修改以确保稳定性

## ? 许可证

本项目基于开源项目构建，具体许可证信息请参考各组件源码。

## ? 致谢

- **内核来源**: @Pc1598 - https://github.com/Aospa-raphael-unofficial
- **技术支持**: 感谢所有为Linux on mobile设备做出贡献的开发者
- **社区反馈**: 感谢用户的建议和问题报告，帮助项目不断完善

## ? 问题反馈

如遇到问题，请在GitHub上提交Issue，提供详细的错误描述和复现步骤。

## ? 相关资源

- **Linux内核文档**: https://www.kernel.org/doc/html/
- **Ubuntu文档**: https://ubuntu.com/server/docs


由AI生成
