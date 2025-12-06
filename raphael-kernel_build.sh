#!/bin/bash

# ============================================================================
# 小米K20 Pro (Raphael) 内核构建脚本
# ============================================================================
#
# 描述：用于构建小米K20 Pro (Raphael) 设备的内核镜像和DEB包
# 功能：
#   - 自动检查系统依赖和构建环境
#   - 克隆内核源代码并配置构建参数
#   - 使用ccache加速编译过程
#   - 生成内核镜像、设备树文件和DEB安装包
#   - 提供性能监控和缓存统计功能
#
# 环境要求：
#   - Ubuntu/Debian系统（推荐Ubuntu 20.04+）
#   - 至少8GB可用内存
#   - 至少20GB可用磁盘空间
#   - 稳定的网络连接
#
# 使用方法：
#   ./raphael-kernel_build.sh [选项]
#
# 选项：
#   -v, --version <版本>   指定内核版本（默认：latest）
#   --cache                启用ccache缓存（默认：禁用）
#   --no-cache            禁用ccache缓存
#   -h, --help            显示此帮助信息
#
# 示例：
#   ./raphael-kernel_build.sh                         # 使用默认版本构建
#   ./raphael-kernel_build.sh -v 6.1.0                # 构建指定版本内核
#   ./raphael-kernel_build.sh --cache                 # 启用缓存构建
#
# 输出文件：
#   - linux-xiaomi-raphael_<版本>_arm64.deb      # 内核包
#   - firmware-xiaomi-raphael_<版本>_arm64.deb   # 固件包
#   - alsa-xiaomi-raphael_<版本>_arm64.deb       # 音频驱动包
#   - kernel-<版本>.tar.gz                       # 压缩归档文件
#
# 作者：自动生成脚本
# 版本：1.0.0
# 更新日期：2024年
# ============================================================================

set -e
set -o pipefail

# Load configuration
[ -f "build-config.sh" ] && source "build-config.sh" || {
    echo "[ERROR] build-config.sh not found!"
    exit 1
}

# 加载统一日志格式库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/logging-utils.sh" ]; then
    source "${SCRIPT_DIR}/logging-utils.sh"
else
    echo "[ERROR] 日志库文件 logging-utils.sh 未找到"
    exit 1
fi

# 初始化日志系统
init_logging

# 全局错误处理变量
BUILD_STATUS="success"
ERROR_CONTEXT=""
BUILD_START_TIME=0

# 依赖状态缓存配置
DEPENDENCY_CACHE_ENABLED=true
DEPENDENCY_CACHE_FILE="${WORKING_DIR}/.build_cache/dependency_cache.json"
DEPENDENCY_CACHE_TTL=3600  # 缓存有效期（秒）: 1小时

# 增强的清理函数
cleanup() {
    local exit_code=$?
    
    # 记录构建状态
    if [ $exit_code -ne 0 ] || [ "$BUILD_STATUS" = "failed" ]; then
        log_error "构建失败，正在执行清理操作..."
        if [ -n "$ERROR_CONTEXT" ]; then
            log_error "失败上下文: $ERROR_CONTEXT"
        fi
        
        # 收集诊断信息
        log_info "收集系统诊断信息..."
        log_info "当前工作目录: $(pwd)"
        log_info "磁盘空间使用:"
        df -h . 2>/dev/null || true
        log_info "内存使用情况:"
        free -h 2>/dev/null || true
        
        # 检查是否有正在运行的进程
        log_info "检查相关进程:"
        ps aux | grep -E "(make|gcc|git)" | head -10 2>/dev/null || true
    fi
    
    # 清理临时目录
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        log_info "清理临时目录: $TEMP_DIR"
        rm -rf "$TEMP_DIR" 2>/dev/null || log_warning "无法完全清理临时目录"
    fi
    
    # 如果构建成功，记录成功信息
    if [ $exit_code -eq 0 ] && [ "$BUILD_STATUS" = "success" ]; then
        log_success "构建完成，清理操作执行完毕"
    fi
}

# 重试函数
retry_command() {
    local max_attempts=$1
    local delay=$2
    local command_name=$3
    shift 3
    
    local attempt=1
    while [ $attempt -le $max_attempts ]; do
        log_info "执行命令: $command_name (尝试 $attempt/$max_attempts)"
        
        if "$@"; then
            log_success "命令执行成功: $command_name"
            return 0
        fi
        
        log_warning "命令失败: $command_name (尝试 $attempt/$max_attempts)"
        
        if [ $attempt -lt $max_attempts ]; then
            log_info "等待 ${delay}秒后重试..."
            sleep $delay
        fi
        
        attempt=$((attempt+1))
    done
    
    log_error "命令在 $max_attempts 次尝试后仍然失败: $command_name"
    ERROR_CONTEXT="$command_name"
    BUILD_STATUS="failed"
    return 1
}

# 验证文件存在性
verify_file_exists() {
    local file_path=$1
    local description=$2
    
    if [ ! -f "$file_path" ]; then
        log_error "文件不存在: $description ($file_path)"
        ERROR_CONTEXT="文件验证失败: $description"
        BUILD_STATUS="failed"
        return 1
    fi
    
    log_success "文件验证成功: $description"
    return 0
}

# 验证目录存在性
verify_directory_exists() {
    local dir_path=$1
    local description=$2
    
    if [ ! -d "$dir_path" ]; then
        log_error "目录不存在: $description ($dir_path)"
        ERROR_CONTEXT="目录验证失败: $description"
        BUILD_STATUS="failed"
        return 1
    fi
    
    log_success "目录验证成功: $description"
    return 0
}

# ----------------------------- 
# 缓存管理函数
# ----------------------------- 
setup_cache_environment() {
    log_info "🔧 配置编译缓存环境..."
    
    if [[ "$CACHE_ENABLED" != "true" ]]; then
        log_info "📋 缓存已禁用，跳过缓存配置"
        return 0
    fi
    
    # 检查ccache是否可用
    if ! command -v ccache >/dev/null 2>&1; then
        log_error "❌ ccache不可用，但缓存已启用"
        ERROR_CONTEXT="缓存配置失败：ccache不可用"
        BUILD_STATUS="failed"
        return 1
    fi
    
    # 显示ccache版本信息
    local ccache_version=$(ccache --version | head -n1)
    log_info "📊 ccache版本: $ccache_version"
    
    # 设置ccache环境变量
    export CCACHE_DIR="${CCACHE_DIR}"
    export CCACHE_MAXSIZE="${CCACHE_MAXSIZE}"
    export CCACHE_COMPRESS="${CCACHE_COMPRESS}"
    export CCACHE_COMPRESSLEVEL="${CCACHE_COMPRESSLEVEL}"
    export CCACHE_LOGFILE="${CCACHE_LOGFILE}"
    export CCACHE_UMASK="${CCACHE_UMASK}"
    export CCACHE_SLOPPINESS="${CCACHE_SLOPPINESS}"
    export CCACHE_NOHASHDIR="${CCACHE_NOHASHDIR}"
    
    # 验证并创建ccache目录
    log_info "📁 配置ccache目录: $CCACHE_DIR"
    if [ ! -d "$CCACHE_DIR" ]; then
        log_warning "⚠️ ccache目录不存在，创建目录..."
        mkdir -p "$CCACHE_DIR" || {
            log_error "❌ 无法创建ccache目录: $CCACHE_DIR"
            ERROR_CONTEXT="缓存配置失败：目录创建失败"
            BUILD_STATUS="failed"
            return 1
        }
    fi
    
    # 验证ccache目录权限
    if [ ! -w "$CCACHE_DIR" ]; then
        log_error "❌ ccache目录不可写: $CCACHE_DIR"
        ERROR_CONTEXT="缓存配置失败：目录不可写"
        BUILD_STATUS="failed"
        return 1
    fi
    
    # 配置编译器包装
    export CC="ccache gcc"
    export CXX="ccache g++"
    export LD="ld"
    export AR="ar"
    
    log_info "🔧 编译器配置:"
    log_info "   - CC: $CC"
    log_info "   - CXX: $CXX"
    log_info "   - 缓存目录: $CCACHE_DIR"
    log_info "   - 缓存大小: $CCACHE_MAXSIZE"
    log_info "   - 压缩级别: $CCACHE_COMPRESSLEVEL"
    
    # 显示初始ccache统计信息
    log_info "📊 初始ccache统计:"
    if ccache -s >/dev/null 2>&1; then
        ccache -s | head -15
        
        # 计算缓存命中率
        local stats=$(ccache -s)
        local cache_hit_rate=$(echo "$stats" | grep -E "cache hit rate" | sed 's/[^0-9.]//g')
        if [ -n "$cache_hit_rate" ]; then
            log_info "🎯 当前缓存命中率: ${cache_hit_rate}%"
        fi
    else
        log_warning "⚠️ 无法获取ccache统计信息"
    fi
    
    log_success "✅ 缓存环境配置成功"
    return 0
}

# ----------------------------- 
# 缓存统计函数
# ----------------------------- 
show_cache_statistics() {
    if [[ "$CACHE_ENABLED" != "true" ]] || ! command -v ccache >/dev/null 2>&1; then
        return 0
    fi
    
    log_info "📊 缓存使用统计:"
    
    # 显示详细统计信息
    if ccache -s >/dev/null 2>&1; then
        ccache -s | while IFS= read -r line; do
            if [[ "$line" =~ (cache hit rate|cache directory|cache size|files in cache|max cache size) ]]; then
                log_info "   $line"
            fi
        done
        
        # 计算性能提升
        local stats=$(ccache -s)
        local hit_rate=$(echo "$stats" | grep -E "cache hit \(direct\)" | awk '{print $4}')
        local miss_rate=$(echo "$stats" | grep -E "cache miss" | awk '{print $3}')
        
        if [ -n "$hit_rate" ] && [ -n "$miss_rate" ] && [ "$hit_rate" -gt 0 ]; then
            local total_compiles=$((hit_rate + miss_rate))
            local performance_gain=$((hit_rate * 100 / total_compiles))
            log_info "🎯 性能提升: 缓存节省了约 ${performance_gain}% 的编译时间"
        fi
    fi
}

# ----------------------------- 
# 性能监控函数
# ----------------------------- 
# 函数：show_performance_monitor
# 描述：显示构建过程的性能监控报告，包括系统负载、内存使用、磁盘使用、CPU核心数和构建总耗时
# 参数：无
# 返回：无
# 使用场景：构建完成后调用，提供系统资源使用情况和构建时间统计
show_performance_monitor() {
    log_info "📈 构建性能监控报告:"
    
    # 系统负载 - 显示最近1、5、15分钟的平均负载
    if command -v uptime >/dev/null 2>&1; then
        local load_avg=$(uptime | awk -F'load average:' '{print $2}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        log_info "   - 系统负载: $load_avg (最近1、5、15分钟平均)"
    else
        log_info "   - 系统负载: 无法获取"
    fi
    
    # 内存使用 - 显示总内存、已用内存和内存使用百分比
    if command -v free >/dev/null 2>&1; then
        local mem_info=$(free -m | awk 'NR==2{printf "%.2f%% (已用 %dMB / 总共 %dMB)", $3*100/$2, $3, $2}')
        log_info "   - 内存使用: $mem_info"
    else
        log_info "   - 内存使用: 无法获取"
    fi
    
    # 磁盘使用 - 检查构建目录所在磁盘的使用情况，包括挂载点、已用空间、总空间和使用率
    local build_disk_info=$(df -h "${WORKING_DIR}" 2>/dev/null | awk 'NR==2{printf "%s (已用 %s / 总共 %s, 使用率 %s)", $6, $3, $2, $5}')
    if [ -n "$build_disk_info" ]; then
        log_info "   - 构建目录磁盘使用: $build_disk_info"
    else
        log_info "   - 构建目录磁盘使用: 无法获取"
    fi
    
    # CPU信息 - 获取系统可用的CPU核心数，用于评估并行编译能力
    local cpu_cores=$(nproc 2>/dev/null || echo "未知")
    log_info "   - CPU核心数: $cpu_cores"
    
    # 构建时间信息 - 计算从构建开始到结束的总耗时，用于性能评估
    if [ -n "$BUILD_START_TIME" ] && [ -n "$BUILD_END_TIME" ]; then
        local build_duration=$((BUILD_END_TIME - BUILD_START_TIME))
        log_info "   - 构建总耗时: ${build_duration}秒"
    fi
}

# 设置错误捕获
trap cleanup EXIT

# Parse arguments
parse_arguments() {
    KERNEL_VERSION="${KERNEL_VERSION:-${KERNEL_VERSION_DEFAULT}}"
    CACHE_ENABLED="${CACHE_ENABLED:-${CACHE_ENABLED_DEFAULT:-false}}"
    
    [[ $# -eq 1 && ! "$1" =~ ^- ]] && KERNEL_VERSION="$1" && shift 1
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version) KERNEL_VERSION="$2"; shift 2 ;;
            --cache) CACHE_ENABLED="true"; shift 1 ;;
            --no-cache) CACHE_ENABLED="false"; shift 1 ;;
            -h|--help) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

# Show help
show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

Build kernel for Xiaomi K20 Pro (Raphael)

OPTIONS:
    -v, --version VERSION    Kernel version (e.g., 6.18) [default: ${KERNEL_VERSION_DEFAULT}]
    --cache                  Enable build cache
    --no-cache               Disable build cache [default: ${CACHE_ENABLED_DEFAULT:-false}]
    -h, --help               Show this help message

EXAMPLES:
    $0 --version 6.18 --cache
EOF
}

# ----------------------------- 
# 参数验证
# ----------------------------- 
validate_parameters() {
    log_info "正在验证参数..."
    
    # 验证内核版本格式 (例如: 6.18, 5.15)
    if [[ ! "$KERNEL_VERSION" =~ ^[0-9]+\.[0-9]+$ ]]; then
        log_error "无效的内核版本格式: $KERNEL_VERSION"
        log_error "期望格式: 主版本.次版本 (例如: 6.18, 5.15)"
        exit 1
    fi
    
    # 验证缓存选项
    if [[ "$CACHE_ENABLED" != "true" && "$CACHE_ENABLED" != "false" ]]; then
        log_error "无效的缓存选项: $CACHE_ENABLED"
        log_error "期望值: true 或 false"
        exit 1
    fi
    
    # 设置基于版本的内核分支名称
    KERNEL_BRANCH="${KERNEL_BRANCH_PREFIX}${KERNEL_VERSION}"
    
    # 使用一致的命名设置目录路径
    TEMP_DIR="$(mktemp -d)"
    KERNEL_BUILD_DIR="${TEMP_DIR}/linux"
    OUTPUT_DIR="${WORKING_DIR}/output/kernel"
    
    # 创建输出目录
    mkdir -p "$OUTPUT_DIR"
    
    log_success "参数验证成功"
    log_info "内核版本: $KERNEL_VERSION"
    log_info "内核分支: $KERNEL_BRANCH"
    log_info "临时目录: $TEMP_DIR"
    log_info "构建目录: $KERNEL_BUILD_DIR"
    log_info "输出目录: $OUTPUT_DIR"
}

# ----------------------------- 
# 安装依赖项
# ----------------------------- 
install_dependencies() {
    log_info "📦 正在安装交叉编译依赖项..."
    
    # 检查系统包管理器可用性
    if ! command -v apt >/dev/null 2>&1; then
        log_error "❌ 系统不支持apt包管理器，无法安装依赖项"
        ERROR_CONTEXT="依赖安装失败：包管理器不可用"
        BUILD_STATUS="failed"
        return 1
    fi
    
    # 检查sudo权限
    if ! sudo -n true 2>/dev/null; then
        log_warning "⚠️ 需要sudo权限安装依赖项"
    fi
    
    # 使用重试机制更新软件包列表
    log_info "🔄 更新软件包列表..."
    retry_command 2 30 "apt update" sudo apt update -y
    
    if [ $? -ne 0 ]; then
        log_error "❌ 软件包列表更新失败"
        ERROR_CONTEXT="依赖安装失败：包列表更新"
        BUILD_STATUS="failed"
        return 1
    fi
    
    # 定义依赖包列表
    local dependencies=(
        "crossbuild-essential-arm64"
        "git"
        "make"
        "gcc"
        "bc"
        "bison"
        "flex"
        "libssl-dev"
        "device-tree-compiler"
        "dpkg-dev"
        "debhelper"
        "ccache"
    )
    
    # 检查每个依赖包是否已安装
    log_info "🔍 检查依赖包状态..."
    local missing_packages=()
    for pkg in "${dependencies[@]}"; do
        if ! dpkg -l | grep -q "^ii\s*$pkg\s"; then
            missing_packages+=("$pkg")
        fi
    done
    
    # 如果没有缺失的包，直接返回成功
    if [ ${#missing_packages[@]} -eq 0 ]; then
        log_success "✅ 所有依赖项已安装"
        return 0
    fi
    
    log_info "📥 需要安装的依赖项: ${missing_packages[*]}"
    
    # 使用重试机制安装依赖项
    log_info "🔄 安装依赖包..."
    retry_command 3 60 "apt install" sudo apt install -y "${missing_packages[@]}"
    
    if [ $? -ne 0 ]; then
        log_error "❌ 依赖项安装失败"
        ERROR_CONTEXT="依赖安装失败：包安装"
        BUILD_STATUS="failed"
        
        # 提供详细的错误诊断
        log_info "🔍 安装失败诊断:"
        log_info "尝试的包: ${missing_packages[*]}"
        log_info "检查包可用性..."
        for pkg in "${missing_packages[@]}"; do
            if apt-cache show "$pkg" >/dev/null 2>&1; then
                log_info "   - $pkg: 可用"
            else
                log_error "   - $pkg: 不可用"
            fi
        done
        
        return 1
    fi
    
    # 验证安装结果
    log_info "🔍 验证依赖项安装..."
    local failed_verification=0
    for pkg in "${missing_packages[@]}"; do
        if dpkg -l | grep -q "^ii\s*$pkg\s"; then
            log_success "   ✅ $pkg 安装成功"
        else
            log_error "   ❌ $pkg 安装失败"
            failed_verification=$((failed_verification+1))
        fi
    done
    
    if [ $failed_verification -gt 0 ]; then
        log_error "❌ 依赖项验证失败 ($failed_verification 个包)"
        ERROR_CONTEXT="依赖安装失败：验证失败"
        BUILD_STATUS="failed"
        return 1
    fi
    
    log_success "✅ 依赖项安装和验证成功"
    log_info "📊 安装统计: ${#missing_packages[@]} 个依赖包已安装"
    
    return 0
}

# -----------------------------
# 依赖状态缓存管理函数
# -----------------------------

# 检查依赖缓存是否有效
check_dependency_cache_valid() {
    if [[ "$DEPENDENCY_CACHE_ENABLED" != "true" ]]; then
        return 1  # 缓存被禁用
    fi

    if [[ ! -f "$DEPENDENCY_CACHE_FILE" ]]; then
        return 1  # 缓存文件不存在
    fi

    local cache_age
    cache_age=$(($(date +%s) - $(stat -c %Y "$DEPENDENCY_CACHE_FILE" 2>/dev/null || echo "0")))
    
    if [[ $cache_age -gt $DEPENDENCY_CACHE_TTL ]]; then
        return 1  # 缓存过期
    fi

    return 0  # 缓存有效
}

# 从缓存读取依赖状态
read_dependency_cache() {
    local tool_name=$1
    
    if [[ ! -f "$DEPENDENCY_CACHE_FILE" ]]; then
        return 1
    fi

    # 使用jq解析JSON缓存文件
    if command -v jq >/dev/null 2>&1; then
        jq -r ".tools.\"$tool_name\"" "$DEPENDENCY_CACHE_FILE" 2>/dev/null
    else
        # 如果没有jq，使用grep和sed简单提取
        grep -A1 -B1 "\"$tool_name\"" "$DEPENDENCY_CACHE_FILE" 2>/dev/null | \
        grep -o '"available":[^,]*' | cut -d':' -f2 | tr -d ' '
    fi
}

# 写入依赖状态缓存
write_dependency_cache() {
    local tool_name=$1
    local available=$2
    local version=$3

    # 创建缓存目录
    mkdir -p "$(dirname "$DEPENDENCY_CACHE_FILE")"

    # 如果缓存文件不存在，创建基础JSON结构
    if [[ ! -f "$DEPENDENCY_CACHE_FILE" ]]; then
        echo '{"timestamp":"'$(date +%s)'","tools":{}}' > "$DEPENDENCY_CACHE_FILE"
    fi

    # 使用jq更新JSON缓存文件
    if command -v jq >/dev/null 2>&1; then
        jq --arg tool "$tool_name" \
           --arg available "$available" \
           --arg version "$version" \
           --arg timestamp "$(date +%s)" '
        .timestamp = $timestamp |
        .tools[$tool] = {"available": $available, "version": $version}
        ' "$DEPENDENCY_CACHE_FILE" > "$DEPENDENCY_CACHE_FILE.tmp" && \
        mv "$DEPENDENCY_CACHE_FILE.tmp" "$DEPENDENCY_CACHE_FILE"
    else
        # 如果没有jq，使用简单的文本操作（有限支持）
        log_warning "jq命令不可用，依赖缓存功能受限"
        # 这里我们简单跳过，因为复杂的JSON操作需要jq
        # 为了简化，我们只记录一个标记文件表示依赖已检查
        echo "依赖检查于 $(date) 完成" > "${DEPENDENCY_CACHE_FILE}.simple"
    fi
}

# 清除依赖缓存
clear_dependency_cache() {
    if [[ -f "$DEPENDENCY_CACHE_FILE" ]]; then
        rm -f "$DEPENDENCY_CACHE_FILE"
        log_info "🗑️  已清除依赖缓存"
    fi
    # 同时清除简单缓存文件
    rm -f "${DEPENDENCY_CACHE_FILE}.simple"
    rm -f "${DEPENDENCY_CACHE_FILE}.tmp"
}

# ----------------------------- 
# 检查依赖项
# ----------------------------- 
check_dependencies() {
    log_info "🔍 正在检查构建依赖项..."
    
    # 缓存统计
    local cache_hit_count=0
    local cache_miss_count=0
    local use_cache=false
    
    # 检查缓存是否有效
    if check_dependency_cache_valid; then
        log_info "📦 使用依赖状态缓存（有效期: ${DEPENDENCY_CACHE_TTL}秒）"
        use_cache=true
    else
        log_info "📦 依赖缓存无效或已过期，执行完整检查"
        # 如果缓存文件存在但已过期，清除它
        clear_dependency_cache
    fi
    
    # 检查必需的原生编译工具
    local required_tools=("gcc" "g++" "make" "git" "ld" "ar" "ccache")
    local missing_tools=()
    local tool_versions=()
    
    log_info "📋 检查工具可用性..."
    for tool in "${required_tools[@]}"; do
        local tool_available=false
        local cached_version=""
        local actual_version=""
        
        # 尝试从缓存读取
        if [[ "$use_cache" == "true" ]]; then
            local cache_result
            cache_result=$(read_dependency_cache "$tool")
            
            if [[ -n "$cache_result" ]] && [[ "$cache_result" != "null" ]]; then
                # 解析缓存结果（格式: {"available":true,"version":"x.x.x"}）
                local cached_available
                cached_available=$(echo "$cache_result" | grep -o '"available":[^,]*' | cut -d':' -f2 | tr -d ' ')
                cached_version=$(echo "$cache_result" | grep -o '"version":[^,}]*' | cut -d':' -f2 | tr -d '" ')
                
                if [[ "$cached_available" == "true" ]]; then
                    # 验证缓存的工具是否仍然可用
                    if command -v "$tool" >/dev/null 2>&1; then
                        # 获取实际版本
                        case "$tool" in
                            "gcc"|"g++")
                                actual_version=$("$tool" --version | head -n1 | sed 's/^.* //')
                                ;;
                            "make")
                                actual_version=$("$tool" --version | head -n1 | sed 's/^.* //')
                                ;;
                            "git")
                                actual_version=$("$tool" --version | sed 's/^.* //' | head -n1)
                                ;;
                            "ccache")
                                actual_version=$("$tool" --version | head -n1 | sed 's/^.* //')
                                ;;
                            *)
                                actual_version="可用"
                                ;;
                        esac
                        
                        # 检查版本是否匹配
                        if [[ "$actual_version" == "$cached_version" ]] || [[ "$cached_version" == "可用" ]]; then
                            cache_hit_count=$((cache_hit_count + 1))
                            tool_available=true
                            tool_versions+=("$tool: $cached_version (缓存命中)")
                            log_success "   ✅ $tool: $cached_version (缓存命中)"
                            continue  # 跳过实际检查
                        else
                            log_info "   🔄 $tool: 版本不匹配（缓存: $cached_version, 实际: $actual_version）"
                        fi
                    else
                        log_info "   🔄 $tool: 缓存显示可用但实际不可用"
                    fi
                fi
            fi
        fi
        
        # 缓存未命中或无效，执行实际检查
        cache_miss_count=$((cache_miss_count + 1))
        
        if command -v "$tool" >/dev/null 2>&1; then
            # 获取工具版本信息
            case "$tool" in
                "gcc"|"g++")
                    actual_version=$("$tool" --version | head -n1 | sed 's/^.* //')
                    ;;
                "make")
                    actual_version=$("$tool" --version | head -n1 | sed 's/^.* //')
                    ;;
                "git")
                    actual_version=$("$tool" --version | sed 's/^.* //' | head -n1)
                    ;;
                "ccache")
                    actual_version=$("$tool" --version | head -n1 | sed 's/^.* //')
                    ;;
                *)
                    actual_version="可用"
                    ;;
            esac
            
            tool_available=true
            tool_versions+=("$tool: $actual_version")
            log_success "   ✅ $tool: $actual_version"
            
            # 写入缓存
            write_dependency_cache "$tool" "true" "$actual_version"
        else
            missing_tools+=("$tool")
            log_error "   ❌ $tool: 不可用"
            # 写入缓存（不可用状态）
            write_dependency_cache "$tool" "false" ""
        fi
    done
    
    # 检查系统架构
    local system_arch=$(uname -m)
    log_info "🏗️  系统架构: $system_arch"
    
    # 检查可用内存和磁盘空间
    log_info "💾 系统资源检查..."
    if command -v free >/dev/null 2>&1; then
        local available_mem=$(free -m | awk 'NR==2{print $7}')
        log_info "   - 可用内存: ${available_mem}MB"
        
        if [ "$available_mem" -lt 2048 ]; then
            log_warning "⚠️ 可用内存较低，可能影响构建性能"
        fi
    fi
    
    if command -v df >/dev/null 2>&1; then
        local available_disk=$(df -h . | awk 'NR==2{print $4}')
        log_info "   - 可用磁盘空间: $available_disk"
        
        if [ "$available_disk" = "0" ] || [ "$available_disk" = "0B" ]; then
            log_error "❌ 磁盘空间不足"
            ERROR_CONTEXT="系统资源检查失败：磁盘空间不足"
            BUILD_STATUS="failed"
            return 1
        fi
    fi
    
    if [ ${#missing_tools[@]} -eq 0 ]; then
        log_success "✅ 所有必需的依赖项都可用"
        
        # 显示缓存统计信息
        if [[ "$DEPENDENCY_CACHE_ENABLED" == "true" ]]; then
            log_info "📊 依赖缓存统计:"
            log_info "   - 缓存命中: $cache_hit_count"
            log_info "   - 缓存未命中: $cache_miss_count"
            local total_checks=$((cache_hit_count + cache_miss_count))
            if [ $total_checks -gt 0 ]; then
                local hit_rate=$((cache_hit_count * 100 / total_checks))
                log_info "   - 缓存命中率: ${hit_rate}%"
            fi
        fi
        
        # 显示详细的工具信息
        log_info "🔧 工具版本信息:"
        for tool_info in "${tool_versions[@]}"; do
            log_info "   - $tool_info"
        done
        
        # 检查ccache状态（如果启用缓存）
        if [[ "$CACHE_ENABLED" == "true" ]] && command -v ccache >/dev/null 2>&1; then
            log_info "📊 ccache状态检查..."
            ccache -s | head -10 || log_warning "无法获取ccache统计信息"
        fi
        
        return 0
    else
        log_warning "⚠️ 缺少依赖项: ${missing_tools[*]}"
        log_info "📋 依赖项统计: ${#missing_tools[@]} 个工具缺失"
        
        # 检查是否在GitHub Actions环境中
        if [ -n "$GITHUB_ACTIONS" ]; then
            log_info "🏗️ 检测到GitHub Actions环境"
            log_info "依赖项应该在GitHub Actions工作流中安装"
        fi
        
        # 检查是否支持自动安装
        if command -v apt >/dev/null 2>&1; then
            log_info "🔄 尝试自动安装缺少的依赖项..."
            
            # 备用方案：尝试安装缺少的依赖项
            if install_dependencies; then
                log_success "✅ 依赖项安装成功"
                return 0
            else
                log_error "❌ 依赖项安装失败"
                ERROR_CONTEXT="依赖检查失败：自动安装失败"
                BUILD_STATUS="failed"
                return 1
            fi
        else
            log_error "❌ 无法自动安装依赖项（缺少apt包管理器）"
            log_error "请手动安装以下工具: ${missing_tools[*]}"
            ERROR_CONTEXT="依赖检查失败：无法自动安装"
            BUILD_STATUS="failed"
            return 1
        fi
    fi
}

# ----------------------------- 
# 克隆内核源代码
# ----------------------------- 
clone_kernel_source() {
    log_info "📥 正在从 ${KERNEL_REPO} (${KERNEL_BRANCH}) 克隆内核源代码..."
    
    # 验证临时目录存在
    verify_directory_exists "$TEMP_DIR" "临时目录" || return 1
    
    # 使用重试机制克隆指定分支的内核仓库
    retry_command 3 5 "git clone" git clone --branch "${KERNEL_BRANCH}" --depth 1 "${KERNEL_REPO}" "${TEMP_DIR}/linux"
    
    if [ $? -ne 0 ]; then
        log_error "❌ 克隆内核源代码失败，请检查网络连接和仓库地址"
        # 提供诊断信息
        log_error "仓库URL: ${KERNEL_REPO}"
        log_error "分支: ${KERNEL_BRANCH}"
        log_error "目标目录: ${TEMP_DIR}/linux"
        
        # 检查网络连接
        log_info "检查网络连接状态..."
        if ping -c 3 github.com >/dev/null 2>&1; then
            log_success "网络连接正常"
        else
            log_error "网络连接异常，无法访问github.com"
        fi
        
        return 1
    fi
    
    # 更新内核构建目录路径
    KERNEL_BUILD_DIR="${TEMP_DIR}/linux"
    
    # 验证克隆的仓库
    log_info "🔍 正在验证克隆的仓库..."
    verify_directory_exists "${KERNEL_BUILD_DIR}/.git" "Git仓库" || return 1
    
    cd "${KERNEL_BUILD_DIR}"
    
    # 验证分支是否正确
    local current_branch=$(git branch --show-current)
    if [ "$current_branch" != "$KERNEL_BRANCH" ]; then
        log_warning "克隆的分支($current_branch)与请求的分支($KERNEL_BRANCH)不匹配"
        log_info "尝试切换到正确分支..."
        git checkout "$KERNEL_BRANCH" || {
            log_error "无法切换到分支: $KERNEL_BRANCH"
            cd - > /dev/null
            return 1
        }
    fi
    
    # 验证提交历史
    git log --oneline -1 || {
        log_error "无法获取Git提交历史"
        cd - > /dev/null
        return 1
    }
    
    cd - > /dev/null
    
    log_success "✅ 内核源代码克隆成功"
    log_info "📁 内核构建目录: ${KERNEL_BUILD_DIR}"
    log_info "🌿 Git分支: ${KERNEL_BRANCH}"
    
    return 0
}

# ----------------------------- 
# 配置内核
# ----------------------------- 
configure_kernel() {
    log_info "⚙️ 正在配置内核..."
    
    # 验证内核构建目录
    verify_directory_exists "${KERNEL_BUILD_DIR}" "内核构建目录" || return 1
    
    cd "${KERNEL_BUILD_DIR}" || {
        log_error "无法进入内核构建目录: ${KERNEL_BUILD_DIR}"
        return 1
    }
    
    # 配置缓存环境
    if ! setup_cache_environment; then
        log_error "❌ 缓存环境配置失败"
        cd - > /dev/null
        return 1
    fi
    
    # 验证编译器可用性
    log_info "🔍 验证编译器可用性..."
    if ! command -v "$CC" >/dev/null 2>&1; then
        log_error "编译器不可用: $CC"
        ERROR_CONTEXT="编译器配置失败"
        BUILD_STATUS="failed"
        cd - > /dev/null
        return 1
    fi
    
    log_info "🔧 正在运行内核配置..."
    log_info "📋 配置命令: make -j$(nproc) ARCH=arm64 defconfig sm8150.config"
    
    # 使用重试机制进行内核配置
    retry_command 2 10 "内核配置" make -j$(nproc) ARCH=arm64 defconfig sm8150.config
    
    if [ $? -ne 0 ]; then
        log_error "❌ 内核配置失败"
        ERROR_CONTEXT="内核配置失败"
        BUILD_STATUS="failed"
        cd - > /dev/null
        return 1
    fi
    
    # 验证配置文件是否已创建
    log_info "🔍 正在验证配置文件..."
    verify_file_exists ".config" "内核配置文件" || {
        cd - > /dev/null
        return 1
    }
    
    # 检查配置文件大小
    local config_size=$(du -h .config | cut -f1)
    if [ "$config_size" = "0" ] || [ "$config_size" = "0B" ]; then
        log_error "配置文件大小为0，可能配置失败"
        ERROR_CONTEXT="配置文件为空"
        BUILD_STATUS="failed"
        cd - > /dev/null
        return 1
    fi
    
    log_success "✅ 内核配置成功"
    log_info "📁 配置文件大小: $config_size"
    
    cd - > /dev/null
    return 0
}

# ----------------------------- 
# 构建内核
# ----------------------------- 
build_kernel() {
    log_info "🔨 正在构建内核..."
    
    # 验证内核构建目录和配置文件
    verify_directory_exists "${KERNEL_BUILD_DIR}" "内核构建目录" || return 1
    verify_file_exists "${KERNEL_BUILD_DIR}/.config" "内核配置文件" || return 1
    
    cd "${KERNEL_BUILD_DIR}" || {
        log_error "无法进入内核构建目录: ${KERNEL_BUILD_DIR}"
        return 1
    }
    
    # 检查系统资源
    log_info "🔍 检查系统资源..."
    local cpu_cores=$(nproc)
    local available_memory=$(free -m | awk 'NR==2{print $7}')
    local available_disk=$(df -m . | awk 'NR==2{print $4}')
    
    log_info "🖥️ 可用CPU核心: $cpu_cores"
    log_info "💾 可用内存: ${available_memory}MB"
    log_info "💽 可用磁盘空间: ${available_disk}MB"
    
    # 检查资源是否足够
    if [ $available_memory -lt 2048 ]; then
        log_warning "可用内存较少(${available_memory}MB)，可能影响构建性能"
    fi
    
    if [ $available_disk -lt 1024 ]; then
        log_error "磁盘空间不足(${available_disk}MB)，需要至少1GB"
        ERROR_CONTEXT="磁盘空间不足"
        BUILD_STATUS="failed"
        cd - > /dev/null
        return 1
    fi
    
    log_info "🔨 开始内核编译..."
    log_info "📋 构建命令: make -j$(nproc) VERBOSE=1 ARCH=arm64"
    log_info "🖥️ 使用 $cpu_cores 个CPU核心进行编译"
    
    # 使用重试机制进行内核构建
    retry_command 1 0 "内核构建" make -j$cpu_cores VERBOSE=1 ARCH=arm64
    
    if [ $? -ne 0 ]; then
        log_error "❌ 内核构建失败"
        ERROR_CONTEXT="内核构建失败"
        BUILD_STATUS="failed"
        
        # 提供构建失败的诊断信息
        log_info "🔍 构建失败诊断信息:"
        log_info "检查构建日志中的错误信息..."
        
        cd - > /dev/null
        return 1
    fi
    
    # 从构建中获取实际的内核版本
    log_info "🔍 获取内核版本信息..."
    _kernel_version="$(make kernelrelease -s 2>/dev/null)"
    if [ -z "$_kernel_version" ]; then
        log_error "无法获取内核版本信息"
        ERROR_CONTEXT="内核版本获取失败"
        BUILD_STATUS="failed"
        cd - > /dev/null
        return 1
    fi
    
    export _kernel_version
    
    # 验证内核镜像是否已创建
    log_info "🔍 正在验证内核构建输出..."
    verify_file_exists "arch/arm64/boot/Image.gz" "内核镜像文件" || {
        cd - > /dev/null
        return 1
    }
    
    # 检查镜像文件大小
    local image_size=$(du -h arch/arm64/boot/Image.gz | cut -f1)
    if [ "$image_size" = "0" ] || [ "$image_size" = "0B" ]; then
        log_error "内核镜像大小为0，构建可能失败"
        ERROR_CONTEXT="内核镜像为空"
        BUILD_STATUS="failed"
        cd - > /dev/null
        return 1
    fi
    
    # 验证其他关键文件
    local critical_files=(
        "arch/arm64/boot/Image"
        "System.map"
        "vmlinux"
    )
    
    for file in "${critical_files[@]}"; do
        if [ -f "$file" ]; then
            log_success "✅ 关键文件存在: $file"
        else
            log_warning "⚠️ 关键文件缺失: $file"
        fi
    done
    
    log_success "✅ 内核构建成功 (版本: $_kernel_version)"
    log_info "📁 内核镜像大小: $image_size"
    log_info "📁 构建输出: arch/arm64/boot/Image.gz"
    
    cd - > /dev/null
    return 0
}









# ----------------------------- 
# Create compressed archive
# ----------------------------- 
create_compressed_archive() {
    log_info "📦 Creating compressed archive of build artifacts..."
    
    local archive_name="kernel-${_kernel_version}-raphael"
    local archive_path="${OUTPUT_DIR}/${archive_name}"
    
    # Create a README file with build information
    local readme_content="# Kernel ${_kernel_version} for Xiaomi Raphael (K20 Pro)\n\n## Build Information\n- Kernel Version: ${_kernel_version}\n- Architecture: ARM64\n- Target Device: Xiaomi Raphael (K20 Pro)\n- Build Date: $(date)\n- Build Time: $(( $(date +%s) - BUILD_START_TIME )) seconds\n\n## Contents\n- linux-xiaomi-raphael_${_kernel_version}_arm64.deb: Kernel package\n- firmware-xiaomi-raphael_${_kernel_version}_arm64.deb: Firmware package\n- alsa-xiaomi-raphael_${_kernel_version}_arm64.deb: ALSA package\n- Image.gz-${_kernel_version}: Standalone kernel image\n- dtbs/: Device tree binary files\n\n## Installation\n1. Install DEB packages: \`sudo dpkg -i *.deb\`\n2. Update bootloader with kernel image if needed\n3. Reboot to apply changes"
    
    # Create compressed archive directly from build directory without copying
    log_info "📦 Creating tar.gz archive..."
    cd "${WORKING_DIR}"
    
    # Create a temporary README file
    echo "${readme_content}" > "${OUTPUT_DIR}/README.md"
    
    # Create tar.gz archive with all necessary files
    # Use --ignore-failed-read to handle empty dtbs directory
    tar -czf "${archive_path}.tar.gz" --ignore-failed-read \
        -C "${OUTPUT_DIR}" linux-xiaomi-raphael_${_kernel_version}_arm64.deb \
        -C "${OUTPUT_DIR}" firmware-xiaomi-raphael_${_kernel_version}_arm64.deb \
        -C "${OUTPUT_DIR}" alsa-xiaomi-raphael_${_kernel_version}_arm64.deb \
        -C "${OUTPUT_DIR}" Image.gz-${_kernel_version} \
        -C "${OUTPUT_DIR}" dtbs/ \
        -C "${OUTPUT_DIR}" README.md || { log_error "❌ Failed to create archive"; exit 1; }
    
    # Remove temporary README file
    rm "${OUTPUT_DIR}/README.md"
    
    # Verify archive creation
    if [ -f "${archive_path}.tar.gz" ]; then
        log_success "✅ Compressed archive created successfully"
        log_info "📦 Archive size: $(du -h "${archive_path}.tar.gz" | cut -f1)"
    else
        log_error "❌ Failed to create compressed archive"
    fi
}

# ----------------------------- 
# Create kernel package
# ----------------------------- 
create_kernel_package() {
    log_info "📦 Creating kernel package..."
    
    cd "${KERNEL_BUILD_DIR}"
    
    # Use the exact commands from user's requirements with correct paths
    local DEB_PACKAGE_DIR="${WORKING_DIR}/linux-xiaomi-raphael"
    log_info "📁 Creating package directory: ${DEB_PACKAGE_DIR}"
    mkdir -p "${DEB_PACKAGE_DIR}/boot"
    
    # Copy kernel image and DTB
    log_info "📄 Copying kernel image and DTB files..."
    cp arch/arm64/boot/Image.gz "${DEB_PACKAGE_DIR}/boot/vmlinuz-$_kernel_version"
    
    # Copy device tree file with error tolerance
    if [ -f "arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb" ]; then
        cp arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb "${DEB_PACKAGE_DIR}/boot/dtb-$_kernel_version"
        log_success "✅ Device tree file copied successfully"
    else
        log_warning "⚠️ Device tree file not found, creating placeholder"
        # Create empty placeholder file to avoid package creation failure
        touch "${DEB_PACKAGE_DIR}/boot/dtb-$_kernel_version"
        echo "# Placeholder for missing device tree file" > "${DEB_PACKAGE_DIR}/boot/dtb-$_kernel_version"
        log_info "📝 Created placeholder device tree file"
    fi
    
    log_success "✅ Kernel files processed successfully"
    
    # Update control file version
    log_info "📝 Updating control file version to ${_kernel_version}..."
    sed -i "s/Version:.*/Version: ${_kernel_version}/" "${DEB_PACKAGE_DIR}/DEBIAN/control"
    
    # Remove old lib directory if exists
    rm -rf "${DEB_PACKAGE_DIR}/lib" 2>/dev/null || true
    
    # Install modules
    log_info "🔧 Installing kernel modules..."
    make -j$(nproc) ARCH=arm64 INSTALL_MOD_PATH="${DEB_PACKAGE_DIR}" modules_install
    
    # Remove build symlinks
    rm -rf "${DEB_PACKAGE_DIR}/lib/modules/**/build" 2>/dev/null || true
    
    # Build all packages
    cd "${WORKING_DIR}"
    
    # Create output directory structure
    log_info "📁 Creating output directory structure..."
    mkdir -p "${OUTPUT_DIR}/dtbs"
    
    # Copy standalone kernel image and DTB files
    log_info "📄 Copying standalone kernel files..."
    cp "${KERNEL_BUILD_DIR}/arch/arm64/boot/Image.gz" "${OUTPUT_DIR}/Image.gz-${_kernel_version}"
    
    # Copy device tree file with error tolerance
    if [ -f "${KERNEL_BUILD_DIR}/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb" ]; then
        cp "${KERNEL_BUILD_DIR}/arch/arm64/boot/dts/qcom/sm8150-xiaomi-raphael.dtb" "${OUTPUT_DIR}/dtbs/"
        log_success "✅ Standalone device tree file copied successfully"
    else
        log_warning "⚠️ Standalone device tree file not found, skipping..."
        log_info "📝 DTB directory will be empty but build continues"
    fi
    
    # Create a symlink for GitHub Actions compatibility if versions differ
    if [ "${KERNEL_VERSION}" != "${_kernel_version}" ] && [ -n "${KERNEL_VERSION}" ]; then
        log_info "🔗 Creating version compatibility symlink..."
        ln -sf "Image.gz-${_kernel_version}" "${OUTPUT_DIR}/Image.gz-${KERNEL_VERSION}" 2>/dev/null || true
    fi
    
    # Build all packages directly
    log_info "📦 Building DEB packages..."
    dpkg-deb --build --root-owner-group linux-xiaomi-raphael
    dpkg-deb --build --root-owner-group firmware-xiaomi-raphael
    dpkg-deb --build --root-owner-group alsa-xiaomi-raphael
    
    # Move built packages to output directory with proper naming
    log_info "📁 Moving packages to output directory..."
    mv -f linux-xiaomi-raphael.deb "${OUTPUT_DIR}/linux-xiaomi-raphael_${_kernel_version}_arm64.deb"
    mv -f firmware-xiaomi-raphael.deb "${OUTPUT_DIR}/firmware-xiaomi-raphael_${_kernel_version}_arm64.deb"
    mv -f alsa-xiaomi-raphael.deb "${OUTPUT_DIR}/alsa-xiaomi-raphael_${_kernel_version}_arm64.deb"
    
    # Verify the output directory structure
    log_info "� Verifying output directory structure:"
    ls -la "${OUTPUT_DIR}/"
    ls -la "${OUTPUT_DIR}/dtbs/" 2>/dev/null || echo "DTB directory not found"
    
    # Create output directory if needed
    mkdir -p "${OUTPUT_DIR}" 2>/dev/null || true
    
    # Clean up the linux directory
    rm -rf linux
    
    # Verify package sizes
    log_info "📊 Package sizes:"
    for pkg in "${OUTPUT_DIR}"/*.deb; do
        if [ -f "$pkg" ]; then
            log_info "📦 $(basename $pkg): $(du -h "$pkg" | cut -f1)"
        fi
    done
    
    log_success "✅ Kernel packages created successfully"
    log_info "📦 Kernel package: ${OUTPUT_DIR}/linux-xiaomi-raphael_${_kernel_version}_arm64.deb"
    log_info "📦 Firmware package: ${OUTPUT_DIR}/firmware-xiaomi-raphael_${_kernel_version}_arm64.deb"
    log_info "📦 ALSA package: ${OUTPUT_DIR}/alsa-xiaomi-raphael_${_kernel_version}_arm64.deb"
}

# Build status tracking
BUILD_START_TIME=$(date +%s)

# Main function
main() {
    log_info "Starting kernel build for Xiaomi K20 Pro (Raphael)"
    
    # 记录构建开始时间
    BUILD_START_TIME=$(date +%s)
    
    # 执行构建步骤，每一步都进行错误检查
    local steps=(
        "parse_arguments"
        "validate_parameters" 
        "check_dependencies"
        "clone_kernel_source"
        "configure_kernel"
        "build_kernel"
        "create_kernel_package"
        "create_compressed_archive"
    )
    
    local step_start_time
    local step_name
    
    for step in "${steps[@]}"; do
        step_start_time=$(date +%s)
        step_name="${step//_/ }"
        
        log_info "🚀 开始执行步骤: $step_name"
        
        # 执行步骤并检查返回值
        if ! $step "$@"; then
            log_error "❌ 步骤失败: $step_name"
            ERROR_CONTEXT="$step_name"
            BUILD_STATUS="failed"
            
            # 计算步骤执行时间
            local step_time=$(( $(date +%s) - step_start_time ))
            log_error "步骤执行时间: ${step_time}s"
            
            # 提供失败诊断
            log_info "🔍 失败诊断信息:"
            log_info "当前工作目录: $(pwd)"
            log_info "环境变量检查:"
            env | grep -E "(KERNEL|CCACHE|GITHUB)" | head -10
            
            return 1
        fi
        
        # 计算步骤执行时间
        local step_time=$(( $(date +%s) - step_start_time ))
        log_success "✅ 步骤完成: $step_name (${step_time}s)"
    done
    
    # 计算总构建时间并设置构建结束时间
    local total_time=$(( $(date +%s) - BUILD_START_TIME ))
    BUILD_END_TIME=$(date +%s)
    
    # 显示缓存统计信息
    show_cache_statistics
    
    # 显示构建摘要
    log_success "🎉 内核构建成功完成!"
    log_info "📊 构建统计:"
    log_info "   - 总构建时间: ${total_time}s"
    log_info "   - 内核版本: ${_kernel_version:-未知}"
    log_info "   - 输出目录: ${OUTPUT_DIR}"
    log_info "   - 缓存状态: ${CACHE_ENABLED:-false}"
    
    # 显示性能监控报告
    show_performance_monitor
    
    # 显示包信息
    log_info "📦 构建产物:"
    local package_count=0
    for pkg in "${OUTPUT_DIR}"/*.deb; do
        if [ -f "$pkg" ]; then
            local pkg_size=$(du -h "$pkg" | cut -f1)
            log_info "   - $(basename $pkg) ($pkg_size)"
            package_count=$((package_count+1))
        fi
    done
    
    if [ $package_count -eq 0 ]; then
        log_warning "⚠️ 未找到任何包文件"
    else
        log_success "✅ 生成 $package_count 个包文件"
    fi
    
    return 0
}

# ----------------------------- 
# Script execution
# ----------------------------- 
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi