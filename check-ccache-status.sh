#!/bin/bash

# 检查ccache配置和状态的脚本来验证设置是否正确

echo "=== ccache配置检查 ==="
echo ""

# 检查ccache是否安装
if command -v ccache >/dev/null 2>&1; then
    echo "✅ ccache已安装"
    echo "ccache版本: $(ccache --version | head -n 1)"
else
    echo "❌ ccache未安装"
    exit 1
fi

echo ""

# 检查环境变量
echo "=== 环境变量检查 ==="
echo "CCACHE_DIR: ${CCACHE_DIR:-$HOME/.ccache}"
echo "CCACHE_MAXSIZE: ${CCACHE_MAXSIZE:-未设置}"
echo "CCACHE_COMPILERCHECK: ${CCACHE_COMPILERCHECK:-未设置}"
echo "CCACHE_COMPRESS: ${CCACHE_COMPRESS:-未设置}"
echo "CCACHE_SLOPPINESS: ${CCACHE_SLOPPINESS:-未设置}"
echo ""

# 检查ccache配置文件
CCACHE_CONF_DIR="${CCACHE_DIR:-$HOME/.ccache}"
if [ -f "$CCACHE_CONF_DIR/ccache.conf" ]; then
    echo "=== ccache配置文件内容 ==="
    cat "$CCACHE_CONF_DIR/ccache.conf"
    echo ""
else
    echo "⚠️ ccache配置文件不存在"
fi

echo "=== ccache统计信息 ==="
ccache -s

echo ""
echo "=== ccache缓存目录 ==="
ls -la "$CCACHE_CONF_DIR"