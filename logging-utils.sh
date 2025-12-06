#!/bin/bash

# ================================================
# 小米K20 Pro Ubuntu项目 - GitHub Actions优化日志格式
# ================================================

# GitHub Actions环境检测和颜色配置
if [ -n "$GITHUB_ACTIONS" ]; then
    GITHUB_ACTIONS_MODE=true
    # GitHub Actions中启用彩色输出（支持ANSI颜色）
    LOG_COLOR_RESET="\033[0m"
    LOG_COLOR_RED="\033[31m"
    LOG_COLOR_GREEN="\033[32m"
    LOG_COLOR_YELLOW="\033[33m"
    LOG_COLOR_BLUE="\033[34m"
    LOG_COLOR_MAGENTA="\033[35m"
    LOG_COLOR_CYAN="\033[36m"
    LOG_STYLE_BOLD="\033[1m"
    LOG_STYLE_DIM="\033[2m"
    LOG_STYLE_UNDERLINE="\033[4m"
else
    GITHUB_ACTIONS_MODE=false
    # 本地环境保留颜色
    LOG_COLOR_RESET="\033[0m"
    LOG_COLOR_RED="\033[31m"
    LOG_COLOR_GREEN="\033[32m"
    LOG_COLOR_YELLOW="\033[33m"
    LOG_COLOR_BLUE="\033[34m"
    LOG_COLOR_MAGENTA="\033[35m"
    LOG_COLOR_CYAN="\033[36m"
    LOG_STYLE_BOLD="\033[1m"
    LOG_STYLE_DIM="\033[2m"
    LOG_STYLE_UNDERLINE="\033[4m"
fi

# ================================================
# 日志级别定义
# ================================================

# 调试日志 (DEBUG) - 详细调试信息
LOG_LEVEL_DEBUG=0
# 信息日志 (INFO) - 常规操作信息
LOG_LEVEL_INFO=1
# 成功日志 (SUCCESS) - 操作成功完成
LOG_LEVEL_SUCCESS=2
# 警告日志 (WARNING) - 需要注意的问题
LOG_LEVEL_WARNING=3
# 错误日志 (ERROR) - 严重问题
LOG_LEVEL_ERROR=4

# 当前日志级别 (默认为INFO)
LOG_LEVEL="${LOG_LEVEL:-$LOG_LEVEL_INFO}"

# ================================================
# 命令计时功能
# ================================================

# 命令计时器数组
declare -A COMMAND_TIMERS

# 开始命令计时
start_command_timer() {
    local command_id="$1"
    COMMAND_TIMERS["$command_id"]=$(date +%s.%N)
}

# 结束命令计时并返回耗时（秒）
end_command_timer() {
    local command_id="$1"
    local end_time=$(date +%s.%N)
    local start_time=${COMMAND_TIMERS["$command_id"]}
    
    if [ -n "$start_time" ]; then
        local duration=$(echo "$end_time - $start_time" | bc)
        printf "%.2f" "$duration"
    else
        echo "0.00"
    fi
}

# ================================================
# 核心日志函数（GitHub Actions优化版）
# ================================================

# 调试日志 - 🔍 调试信息
log_debug() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]; then
        echo -e "🔍 ${LOG_COLOR_CYAN}${LOG_STYLE_DIM}DEBUG${LOG_COLOR_RESET} ${LOG_STYLE_DIM}$1${LOG_COLOR_RESET}"
    fi
}

# 信息日志 - ℹ️ 常规信息
log_info() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_INFO" ]; then
        echo -e "ℹ️ ${LOG_COLOR_BLUE}INFO${LOG_COLOR_RESET} $1"
    fi
}

# 成功日志 - ✅ 操作成功
log_success() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_SUCCESS" ]; then
        echo -e "✅ ${LOG_COLOR_GREEN}${LOG_STYLE_BOLD}SUCCESS${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}$1${LOG_COLOR_RESET}"
    fi
}

# 警告日志 - ⚠️ 需要注意的问题
log_warning() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_WARNING" ]; then
        echo -e "⚠️ ${LOG_COLOR_YELLOW}${LOG_STYLE_BOLD}WARNING${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}$1${LOG_COLOR_RESET}"
    fi
}

# 错误日志 - ❌ 严重问题
log_error() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_ERROR" ]; then
        echo -e "❌ ${LOG_COLOR_RED}${LOG_STYLE_BOLD}ERROR${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}$1${LOG_COLOR_RESET}" >&2
    fi
}

# ================================================
# 特殊日志格式（GitHub Actions优化版）
# ================================================

# 步骤开始日志 - 🚀 开始操作步骤
log_step_start() {
    local step_number=$1
    local step_description=$2
    echo -e "🚀 ${LOG_COLOR_MAGENTA}${LOG_STYLE_BOLD}STEP $step_number${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}$step_description${LOG_COLOR_RESET}"
}

# 步骤完成日志 - ✅ 步骤完成
log_step_complete() {
    local step_number=$1
    echo -e "✅ ${LOG_COLOR_GREEN}${LOG_STYLE_BOLD}STEP $step_number COMPLETE${LOG_COLOR_RESET}"
}

# 进度日志 - 📊 显示操作进度
log_progress() {
    local current=$1
    local total=$2
    local description=$3
    local percentage=$((current * 100 / total))
    echo -e "📊 ${LOG_COLOR_CYAN}PROGRESS${LOG_COLOR_RESET} $description ($current/$total - ${percentage}%)"
}

# 分隔线日志 - 用于视觉分隔
log_separator() {
    local char=${1:-"="}
    local length=${2:-60}
    echo -e "${LOG_COLOR_WHITE}${LOG_STYLE_DIM}$(printf "%${length}s" | tr ' ' "$char")${LOG_COLOR_RESET}"
}

# 标题日志 - 用于章节标题
log_title() {
    local title=$1
    log_separator "="
    echo -e "📋 ${LOG_COLOR_BLUE}${LOG_STYLE_BOLD}${LOG_STYLE_UNDERLINE}$title${LOG_COLOR_RESET}"
    log_separator "="
}

# ================================================
# 命令执行日志（GitHub Actions优化版）
# ================================================

# 执行命令并记录详细日志（带计时功能）
execute_command() {
    local cmd="$1"
    local description="$2"
    local show_output="${3:-true}"
    
    # 生成唯一命令ID用于计时
    local command_id="cmd_$(date +%s%N)"
    
    # 开始计时
    start_command_timer "$command_id"
    
    log_info "⏱️ 执行: $description"
    log_debug "命令: $cmd"
    
    # 执行命令并捕获输出
    local output
    local exit_code
    
    if [ "$show_output" = "true" ]; then
        # 显示实时输出
        eval "$cmd"
        exit_code=$?
    else
        # 静默执行，仅在失败时显示输出
        output=$(eval "$cmd" 2>&1)
        exit_code=$?
    fi
    
    # 结束计时
    local duration=$(end_command_timer "$command_id")
    
    if [ $exit_code -eq 0 ]; then
        log_success "✅ 完成: $description (耗时: ${duration}s)"
        return 0
    else
        log_error "❌ 失败: $description (耗时: ${duration}s, 退出码: $exit_code)"
        if [ "$show_output" = "false" ]; then
            log_error "错误信息:"
            echo "$output"
        fi
        
        # 根据错误类型提供特定建议
        if [[ "$description" == *chroot* ]] && [[ "$output" == *"No such file or directory"* ]]; then
            log_warning "chroot失败，检查目录是否存在且已正确挂载"
        elif [[ "$description" == *mount* ]]; then
            log_warning "挂载失败，检查设备或镜像文件是否存在"
        elif [[ "$description" == *download* ]]; then
            log_warning "下载失败，检查网络连接和URL有效性"
        fi
        
        return $exit_code
    fi
}

# ================================================
# 错误处理系统
# ================================================

# 全局错误处理函数
handle_error() {
    local error_code=$?
    local line_number=$1
    local command_name=$2
    
    log_error "命令失败: $command_name (行号: $line_number, 退出码: $error_code)"
    log_warning "可能的解决方案:"
    log_warning "1. 检查磁盘空间是否充足"
    log_warning "2. 验证网络连接是否正常"
    log_warning "3. 检查依赖包是否完整安装"
    log_warning "4. 查看详细错误信息以确定具体问题"
    
    exit $error_code
}

# 设置错误处理trap
setup_error_trap() {
    trap 'handle_error $LINENO "${BASH_COMMAND}"' ERR
}

# ================================================
# 日志配置和工具函数
# ================================================

# 设置日志级别
set_log_level() {
    case "$1" in
        "debug") LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        "info") LOG_LEVEL=$LOG_LEVEL_INFO ;;
        "success") LOG_LEVEL=$LOG_LEVEL_SUCCESS ;;
        "warning") LOG_LEVEL=$LOG_LEVEL_WARNING ;;
        "error") LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        *) log_warning "未知的日志级别: $1，使用默认级别(info)" ;;
    esac
    log_info "日志级别设置为: $1"
}

# 显示日志级别信息
show_log_levels() {
    log_title "日志级别说明"
    echo "DEBUG   - 详细调试信息 (蓝色)"
    echo "INFO    - 常规操作信息 (蓝色)"
    echo "SUCCESS - 操作成功完成 (绿色粗体)"
    echo "WARNING - 需要注意的问题 (黄色粗体)"
    echo "ERROR   - 严重问题 (红色粗体)"
    echo ""
    echo "当前日志级别: $(get_current_log_level)"
}

# 获取当前日志级别名称
get_current_log_level() {
    case "$LOG_LEVEL" in
        "$LOG_LEVEL_DEBUG") echo "debug" ;;
        "$LOG_LEVEL_INFO") echo "info" ;;
        "$LOG_LEVEL_SUCCESS") echo "success" ;;
        "$LOG_LEVEL_WARNING") echo "warning" ;;
        "$LOG_LEVEL_ERROR") echo "error" ;;
        *) echo "unknown" ;;
    esac
}

# 初始化日志系统
init_logging() {
    setup_error_trap
    log_info "日志系统初始化完成 (级别: $(get_current_log_level))"
}

# ================================================
# 使用示例和说明
# ================================================

# 显示使用示例
show_logging_examples() {
    log_title "日志格式使用示例"
    
    log_debug "这是调试信息，用于详细调试"
    log_info "这是常规信息，用于操作记录"
    log_success "这是成功信息，表示操作完成"
    log_warning "这是警告信息，需要注意的问题"
    log_error "这是错误信息，表示严重问题"
    
    log_step_start "1" "开始构建内核"
    log_progress "3" "5" "正在安装依赖包"
    log_step_complete "1"
    
    log_separator "-"
    log_title "构建完成"
}

# 如果直接执行此脚本，显示示例
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    show_log_levels
    show_logging_examples
fi