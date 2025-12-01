
# Multi-Distro Linux for Xiaomi K20 Pro (Raphael)

## 📋 项目概述

这是一个为小米K20 Pro (代号: Raphael) 设备定制的多发行版Linux系统构建项目，支持Ubuntu和Debian系统。本项目提供完整的自动化构建流程，支持多种发行版（Ubuntu/Debian）、多种桌面环境（GNOME/KDE/XFCE等）和服务器版选择，为用户提供流畅的Linux使用体验。

## 🚀 主要特性

- ✅ **多发行版支持** - 支持Ubuntu和Debian系统构建
- ✅ **多桌面环境** - 支持GNOME、KDE、XFCE、LXDE、MATE等多种桌面环境
- ✅ **服务器版支持** - 提供轻量级服务器版系统
- ✅ **自动化构建系统** - 基于GitHub Actions的完整CI/CD流水线
- ✅ **多版本支持** - 支持自定义内核版本（6.17+）
- ✅ **固件集成** - 设备专用固件和驱动
- ✅ **默认用户配置** - 预置ubuntu用户（密码：1234）
- ✅ **错误处理** - 完善的构建错误检测和恢复机制

## 📋 系统要求

### 自动构建 (GitHub Actions)
- GitHub账户
- 足够的存储空间用于构建产物

### 手动构建
- 操作系统: Linux发行版 (推荐Ubuntu 20.04+)
- 硬件要求: 至少8GB RAM, 50GB可用磁盘空间
- 依赖工具: git, build-essential, fakeroot, dpkg-dev, debootstrap, 7z, ccache
- 权限要求: 构建根文件系统需要root权限

## 📥 快速开始

### 自动构建 (推荐)

1. **访问GitHub Actions**: 进入项目仓库的Actions页面
2. **手动触发构建**: 点击 "Raphael Multi-Distro Kernel and RootFS Builder" 工作流
3. **配置构建参数**:
   - `kernel_version`: 内核版本 (默认: 6.17)
   - `distribution`: 发行版选择 (Ubuntu/Debian，默认: Ubuntu)
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
sudo bash ./raphael-rootfs_build.sh ubuntu ubuntu-desktop 6.17
```

## 🌟 支持的发行版和桌面环境

### 发行版选项
- **Ubuntu** - 基于Ubuntu的稳定版本，提供完整的桌面体验
- **Debian** - 基于Debian的稳定版本，适合需要更稳定环境的用户

### 桌面环境选项

#### Ubuntu桌面环境
- **ubuntu-desktop** - 官方GNOME桌面环境
- **kubuntu-desktop** - KDE Plasma桌面环境
- **xubuntu-desktop** - XFCE轻量级桌面环境
- **lubuntu-desktop** - LXQt轻量级桌面环境
- **ubuntu-mate** - MATE传统桌面环境

#### 通用桌面环境（Ubuntu/Debian）
- **gnome** - GNOME桌面环境
- **kde** - KDE Plasma桌面环境
- **xfce** - XFCE轻量级桌面环境
- **lxde** - LXDE轻量级桌面环境
- **mate** - MATE传统桌面环境

#### 服务器版
- **server** - 无图形界面的服务器版本

### 默认用户配置
所有构建版本均预置默认用户：
- **用户名**: ubuntu
- **密码**: 1234
- **自动登录**: 桌面环境启用自动登录

## 🔧 项目结构

```
├── .github/workflows/main.yml    # GitHub Actions工作流配置
├── raphael-kernel_build.sh       # 内核构建脚本
├── raphael-rootfs_build.sh       # 根文件系统构建脚本
├── linux-xiaomi-raphael/         # 内核DEB包配置文件
├── firmware-xiaomi-raphael/      # 设备固件DEB包配置
├── alsa-xiaomi-raphael/          # 音频驱动DEB包配置
└── workflow_tests/               # 工作流测试目录
```

## 🌐 网络配置

- **默认DNS服务器**: `223.5.5.5` (阿里云DNS)
- **自动配置**: 根文件系统构建过程中自动设置，提供稳定的国内网络连接
- **自定义配置**: 系统安装后可通过编辑 `/etc/resolv.conf` 修改DNS设置

## 📚 安装指南

### 前期准备
- 解锁小米K20 Pro的引导加载程序
- 安装TWRP或其他自定义recovery
- 准备一张至少32GB的高速SD卡或USB存储设备

### 安装步骤
1. 下载最新的Release镜像文件
2. 参考小米Pad 5的Ubuntu安装指南：
   https://linux-on-nabu.gitbook.io/linux-for-mi-pad-5/installation-guide/ubuntu-installation-guide-new-method#assign-new-efi-partition
3. 按照教程进行分区和安装操作
4. 首次启动时完成初始系统配置

### 注意事项
- 安装过程中请确保设备电量充足
- 刷机有风险，请提前备份重要数据
- 首次启动可能需要较长时间，请耐心等待

## 🛠️ 故障排除

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

## 🤝 贡献指南

欢迎提交Issue和Pull Request来改进本项目。贡献前请确保：
- 代码风格与现有项目保持一致
- 添加必要的注释和文档
- 测试修改以确保稳定性

## 📄 许可证

本项目基于开源项目构建，具体许可证信息请参考各组件源码。

## 🤝 致谢

- **内核来源**: @Pc1598 - https://github.com/Aospa-raphael-unofficial
- **技术支持**: 感谢所有为Linux on mobile设备做出贡献的开发者
- **社区反馈**: 感谢用户的建议和问题报告，帮助项目不断完善

## 🐛 问题反馈

如遇到问题，请在GitHub上提交Issue，提供详细的错误描述和复现步骤。

## 🔗 相关资源

- **Linux内核文档**: https://www.kernel.org/doc/html/
- **Ubuntu文档**: https://ubuntu.com/server/docs


由AI生成
