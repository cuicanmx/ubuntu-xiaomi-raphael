#!/bin/bash

# ================================================
# 小米K20 Pro Ubuntu项目 - 统一日志格式规范
# ================================================

# 日志级别颜色编码
LOG_COLOR_RESET="\033[0m"
LOG_COLOR_BLACK="\033[30m"
LOG_COLOR_RED="\033[31m"
LOG_COLOR_GREEN="\033[32m"
LOG_COLOR_YELLOW="\033[33m"
LOG_COLOR_BLUE="\033[34m"
LOG_COLOR_MAGENTA="\033[35m"
LOG_COLOR_CYAN="\033[36m"
LOG_COLOR_WHITE="\033[37m"

# 背景颜色
LOG_BG_RED="\033[41m"
LOG_BG_GREEN="\033[42m"
LOG_BG_YELLOW="\033[43m"
LOG_BG_BLUE="\033[44m"
LOG_BG_MAGENTA="\033[45m"
LOG_BG_CYAN="\033[46m"

# 样式定义
LOG_STYLE_BOLD="\033[1m"
LOG_STYLE_DIM="\033[2m"
LOG_STYLE_UNDERLINE="\033[4m"

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
# 时间戳格式
# ================================================

# 获取当前时间戳 (格式: YYYY-MM-DD HH:MM:SS)
log_timestamp() {
    echo -n "[$(date '+%Y-%m-%d %H:%M:%S')]"
}

# 获取相对时间戳 (从脚本开始时间计算)
LOG_START_TIME=$(date +%s)
log_relative_timestamp() {
    local current_time=$(date +%s)
    local elapsed=$((current_time - LOG_START_TIME))
    printf "[%02d:%02d:%02d]" $((elapsed/3600)) $(((elapsed%3600)/60)) $((elapsed%60))
}

# ================================================
# 核心日志函数
# ================================================

# 调试日志 - 蓝色，详细调试信息
log_debug() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_DEBUG" ]; then
        log_timestamp
        echo -e "${LOG_COLOR_CYAN}${LOG_STYLE_DIM}[DEBUG]${LOG_COLOR_RESET} ${LOG_STYLE_DIM}$1${LOG_COLOR_RESET}"
    fi
}

# 信息日志 - 蓝色，常规操作信息
log_info() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_INFO" ]; then
        log_timestamp
        echo -e "${LOG_COLOR_BLUE}[INFO]${LOG_COLOR_RESET} $1"
    fi
}

# 成功日志 - 绿色，操作成功完成
log_success() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_SUCCESS" ]; then
        log_timestamp
        echo -e "${LOG_COLOR_GREEN}${LOG_STYLE_BOLD}[SUCCESS]${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}$1${LOG_COLOR_RESET}"
    fi
}

# 警告日志 - 黄色，需要注意的问题
log_warning() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_WARNING" ]; then
        log_timestamp
        echo -e "${LOG_COLOR_YELLOW}${LOG_STYLE_BOLD}[WARNING]${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}$1${LOG_COLOR_RESET}"
    fi
}

# 错误日志 - 红色，严重问题
log_error() {
    if [ "$LOG_LEVEL" -le "$LOG_LEVEL_ERROR" ]; then
        log_timestamp
        echo -e "${LOG_COLOR_RED}${LOG_STYLE_BOLD}[ERROR]${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}$1${LOG_COLOR_RESET}" >&2
    fi
}

# ================================================
# 特殊日志格式
# ================================================

# 步骤开始日志 - 紫色，标识操作步骤开始
log_step_start() {
    local step_number=$1
    local step_description=$2
    log_timestamp
    echo -e "${LOG_COLOR_MAGENTA}${LOG_STYLE_BOLD}[STEP $step_number]${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}$step_description${LOG_COLOR_RESET}"
}

# 步骤完成日志 - 绿色，标识操作步骤完成
log_step_complete() {
    local step_number=$1
    log_timestamp
    echo -e "${LOG_COLOR_GREEN}${LOG_STYLE_BOLD}[STEP $step_number ✓]${LOG_COLOR_RESET} ${LOG_STYLE_BOLD}步骤完成${LOG_COLOR_RESET}"
}

# 进度日志 - 青色，显示操作进度
log_progress() {
    local current=$1
    local total=$2
    local description=$3
    local percentage=$((current * 100 / total))
    log_timestamp
    echo -e "${LOG_COLOR_CYAN}[PROGRESS]${LOG_COLOR_RESET} $description ($current/$total - ${percentage}%)"
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
    log_timestamp
    echo -e "${LOG_COLOR_BLUE}${LOG_STYLE_BOLD}${LOG_STYLE_UNDERLINE}$title${LOG_COLOR_RESET}"
    log_separator "="
}

# ================================================
# 命令执行日志
# ================================================

# 执行命令并记录详细日志
execute_command() {
    local cmd="$1"
    local description="$2"
    local show_output="${3:-true}"
    
    log_info "执行: $description"
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
    
    if [ $exit_code -eq 0 ]; then
        log_success "完成: $description"
        return 0
    else
        log_error "失败: $description (退出码: $exit_code)"
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
    LOG_START_TIME=$(date +%s)
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