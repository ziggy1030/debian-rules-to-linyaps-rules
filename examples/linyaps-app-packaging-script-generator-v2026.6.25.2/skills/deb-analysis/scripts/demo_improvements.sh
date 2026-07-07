#!/bin/bash
# 演示 deb_to_linglong.py 的后备机制和缓存功能

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEB_FILE="${1:-/tmp/test.deb}"

echo "========================================"
echo "deb_to_linglong.py 功能演示"
echo "========================================"
echo ""

# 检查 deb 文件是否存在
if [ ! -f "$DEB_FILE" ]; then
	echo "⚠ 警告: 测试文件不存在: $DEB_FILE"
	echo "请提供一个 deb 文件作为参数:"
	echo "  $0 <deb文件路径>"
	echo ""
	echo "示例:"
	echo "  $0 /path/to/package.deb"
	exit 1
fi

echo "测试文件: $DEB_FILE"
echo ""

# 1. 测试基本功能
echo "1. 测试基本功能（首次运行）"
echo "----------------------------------------"
python3 "$SCRIPT_DIR/deb_to_linglong.py" "$DEB_FILE" \
	--base org.deepin.base/25.2.2 \
	--output-dir /tmp/linglong_output

echo ""
echo "按回车继续..."
read

# 2. 测试缓存功能
echo ""
echo "2. 测试缓存功能（第二次运行）"
echo "----------------------------------------"
echo "注意观察输出中的 '✓ 从缓存读取' 消息"
python3 "$SCRIPT_DIR/deb_to_linglong.py" "$DEB_FILE" \
	--base org.deepin.base/25.2.2 \
	--output-dir /tmp/linglong_output

echo ""
echo "按回车继续..."
read

# 3. 测试解压功能
echo ""
echo "3. 测试解压功能"
echo "----------------------------------------"
EXTRACT_DIR="/tmp/deb_extracted_$(basename "$DEB_FILE" .deb)"
python3 "$SCRIPT_DIR/deb_to_linglong.py" "$DEB_FILE" \
	--base org.deepin.base/25.2.2 \
	--extract-dir "$EXTRACT_DIR"

echo ""
echo "解压目录内容:"
echo "control 文件:"
ls -lh "$EXTRACT_DIR/control/" 2>/dev/null || echo "  (无 control 目录)"
echo ""
echo "data 目录:"
du -sh "$EXTRACT_DIR/data/" 2>/dev/null || echo "  (无 data 目录)"

echo ""
echo "按回车继续..."
read

# 4. 显示缓存信息
echo ""
echo "4. 缓存信息"
echo "----------------------------------------"
CACHE_DIR="/tmp/deb_to_linglong_cache"
if [ -d "$CACHE_DIR" ]; then
	echo "缓存目录: $CACHE_DIR"
	echo "缓存文件数: $(find "$CACHE_DIR" -type f | wc -l)"
	echo ""
	echo "缓存文件列表:"
	ls -lh "$CACHE_DIR" | head -10

	echo ""
	echo "缓存内容示例:"
	CACHE_FILE=$(find "$CACHE_DIR" -name "extract_deb_info_*.json" | head -1)
	if [ -n "$CACHE_FILE" ]; then
		echo "文件: $CACHE_FILE"
		cat "$CACHE_FILE" | python3 -m json.tool | head -20
	fi
else
	echo "缓存目录不存在"
fi

echo ""
echo "========================================"
echo "演示完成"
echo "========================================"
echo ""
echo "清理测试文件? (y/n)"
read -r answer
if [ "$answer" = "y" ]; then
	rm -rf "$EXTRACT_DIR" /tmp/linglong_output
	echo "✓ 已清理测试文件"
fi
