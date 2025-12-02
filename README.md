# ? Xiaomi K20 Pro (Raphael) 多发行版 Linux 系统

## ? 项目简介

这是一个专为小米 K20 Pro (代号: Raphael) 定制的多发行版 Linux 系统构建项目，支持 Ubuntu 和 Armbian 系统。通过自动化构建流程，为用户提供完整的 Linux 使用体验。

## ? 核心特性

### ? 多发行版支持
- **Ubuntu**: 完整的桌面和服务器版本支持
- **Armbian**: 针对 ARM 架构优化的轻量级系统

### ? 构建功能
- **自动化构建**: 基于 GitHub Actions 的完整 CI/CD 流水线
- **跳过内核编译**: 可选功能，直接使用现有设备包
- **多版本支持**: 自定义内核版本 (6.17+) 和发行版版本
- **错误处理**: 完善的构建错误检测和恢复机制

### ? 设备优化
- **专用驱动**: 集成 Xiaomi K20 Pro 专用内核和固件
- **音频支持**: ALSA 音频驱动集成
- **网络优化**: 预配置 DNS 和网络设置

## ? 快速开始

### ? 自动构建 (推荐)

1. **访问 GitHub Actions**
   - 进入项目仓库的 Actions 页面
   - 选择 "Raphael Multi-Distro Kernel and RootFS Builder" 工作流

2. **配置构建参数**
   ```
   kernel_version: 6.17.0          # 内核版本 (默认: 6.17.0)
   distribution: ubuntu            # 发行版 (ubuntu/armbian)
   version: noble                  # 版本 (noble/jammy/focal)
   desktop_environment: ubuntu-desktop  # 桌面环境 (仅Ubuntu需要)
   skip_kernel_build: false        # 跳过内核编译 (默认: false)
   release_tag: v1.0.0             # 发布标签
   ```

3. **开始构建**
   - 点击 "Run workflow" 按钮
   - 监控构建进度和日志

### ? 手动构建

#### 环境要求
- 操作系统: Linux (推荐 Ubuntu 20.04+)
- 硬件: 8GB RAM, 50GB 磁盘空间
- 依赖: git, build-essential, fakeroot, dpkg-dev, debootstrap, 7z

#### 构建步骤
```bash
# 克隆项目
git clone https://github.com/your-username/ubuntu-xiaomi-raphael.git
cd ubuntu-xiaomi-raphael

# 构建内核 (可选，可跳过)
bash ./raphael-kernel_build.sh 6.17.0

# 构建根文件系统
# Ubuntu 完整构建
sudo bash ./raphael-rootfs_build.sh ubuntu noble 6.17.0 ubuntu-desktop

# Ubuntu 跳过内核编译
sudo bash ./raphael-rootfs_build.sh ubuntu noble 6.17.0 ubuntu-desktop --skip-kernel-build

# Armbian 完整构建
sudo bash ./raphael-rootfs_build.sh armbian noble 6.17.0

# Armbian 跳过内核编译
sudo bash ./raphael-rootfs_build.sh armbian noble 6.17.0 --skip-kernel-build
```

## ? 发行版详情

### Ubuntu 支持
- **版本**: noble (24.04), jammy (22.04), focal (20.04)
- **桌面环境**:
  - GNOME (ubuntu-desktop)
  - KDE Plasma (kubuntu-desktop)
  - XFCE (xubuntu-desktop)
  - LXDE (lubuntu-desktop)
  - MATE (ubuntu-mate)
  - 服务器版 (ubuntu-server)

### Armbian 支持
- **版本**: noble (基于 Ubuntu 24.04)
- **特性**:
  - 针对 ARM 架构优化
  - 轻量级系统设计
  - 预装设备驱动和固件

## ? 系统配置

### 默认用户
- **用户名**: ubuntu
- **密码**: 1234
- **自动登录**: 桌面环境启用

### 网络配置
- **DNS 服务器**: 223.5.5.5 (阿里云)
- **主机名**: xiaomi-raphael
- **自动配置**: 构建过程中自动设置

## ? 项目结构

```
ubuntu-xiaomi-raphael/
├── .github/workflows/main.yml          # GitHub Actions 配置
├── raphael-kernel_build.sh             # 内核构建脚本
├── raphael-rootfs_build.sh             # 根文件系统构建脚本 (模块化)
├── build-config.sh                     # 构建配置文件
├── linux-xiaomi-raphael/               # 内核包配置
│   └── DEBIAN/control
├── firmware-xiaomi-raphael/            # 固件包配置
│   └── DEBIAN/control
├── alsa-xiaomi-raphael/                # 音频驱动配置
│   └── DEBIAN/control
└── README.md                           # 项目文档
```

## ? 故障排除

### 常见问题

#### 构建失败
- **检查网络连接**: 确保能访问所需的下载源
- **磁盘空间**: 确保有足够的可用空间 (至少 10GB)
- **依赖安装**: 确认所有构建依赖已正确安装

#### 设备包问题
- **跳过内核编译**: 确保 `xiaomi-raphael-debs_*` 目录存在且包含必需包
- **内核版本匹配**: 确认内核版本与设备包版本一致

#### 系统启动问题
- **Bootloader**: 确保设备已解锁 Bootloader
- **TWRP 恢复**: 使用正确的 TWRP 版本刷入系统
- **分区格式**: 确认分区格式和设备兼容性

### 调试信息
- 查看详细的构建日志获取错误信息
- 检查系统日志文件定位问题
- 验证设备驱动是否正确加载

## ? 技术实现

### 构建流程
1. **内核构建**: 编译定制内核和设备驱动
2. **根文件系统**: 下载基础系统并集成设备包
3. **系统配置**: 设置网络、用户和启动配置
4. **镜像打包**: 创建可刷写的系统镜像

### 模块化设计
- **配置管理**: 集中管理构建参数和版本信息
- **错误处理**: 统一的错误检测和恢复机制
- **功能模块**: 分离的参数解析、系统设置和设备安装逻辑

## ? 贡献指南

欢迎提交 Issue 和 Pull Request 来改进项目：
- 报告构建问题或设备兼容性问题
- 添加新的发行版或桌面环境支持
- 优化构建脚本和文档

## ? 许可证

本项目基于开源许可证发布，具体信息请查看 LICENSE 文件。

---

**? 注意**: 刷机有风险，请确保备份重要数据并遵循正确的刷机流程。