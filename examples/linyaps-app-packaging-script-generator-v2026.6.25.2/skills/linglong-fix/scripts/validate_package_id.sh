#!/bin/bash
# validate_package_id.sh - 验证玲珑包ID格式
#
# 功能：
#   1. 验证 package_id 是否符合玲珑规范
#   2. 检查工程目录命名是否正确
#   3. 验证 deb 文件存储路径是否正确
#
# 用法：
#   ./validate_package_id.sh <project_dir> [--deb-path <deb_path>]
#
# 参数：
#   project_dir  - 工程目录路径（如 CI_ll_com.visualstudio.code）
#   --deb-path   - 可选，deb 文件路径用于验证存储路径
#
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#
# 输出：
#   JSON 格式的验证报告

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 默认值
PROJECT_DIR=""
DEB_PATH=""
VERBOSE=false

# 解析参数
while [[ $# -gt 0 ]]; do
	case $1 in
	--deb-path)
		DEB_PATH="$2"
		shift 2
		;;
	--verbose | -v)
		VERBOSE=true
		shift
		;;
	--help | -h)
		echo "用法: $0 <project_dir> [--deb-path <deb_path>] [--verbose]"
		echo ""
		echo "参数:"
		echo "  project_dir    工程目录路径（如 CI_ll_com.visualstudio.code）"
		echo "  --deb-path     可选，deb 文件路径用于验证存储路径"
		echo "  --verbose, -v  显示详细输出"
		echo "  --help, -h     显示帮助信息"
		exit 0
		;;
	*)
		if [[ -z "$PROJECT_DIR" ]]; then
			PROJECT_DIR="$1"
		fi
		shift
		;;
	esac
done

# 检查必需参数
if [[ -z "$PROJECT_DIR" ]]; then
	echo -e "${RED}错误: 未指定工程目录${NC}" >&2
	exit 1
fi

# 验证结果收集
declare -a ERRORS
declare -a WARNINGS

# 函数：记录错误
add_error() {
	ERRORS+=("$1")
	if $VERBOSE; then
		echo -e "${RED}[错误] $1${NC}" >&2
	fi
}

# 函数：记录警告
add_warning() {
	WARNINGS+=("$1")
	if $VERBOSE; then
		echo -e "${YELLOW}[警告] $1${NC}" >&2
	fi
}

# 函数：验证 package_id 格式
# 玲珑包ID规范：反向域名格式，如 com.visualstudio.code
validate_package_id_format() {
	local package_id="$1"

	# 检查是否为空
	if [[ -z "$package_id" ]]; then
		add_error "package_id 为空"
		return 1
	fi

	# 检查格式：应为反向域名格式（至少包含两个点分隔的部分）
	if [[ ! "$package_id" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
		add_error "package_id 格式不正确: '$package_id'，应为反向域名格式（如 com.example.app）"
		return 1
	fi

	# 检查长度限制（玲珑包ID最大长度为255字符）
	if [[ ${#package_id} -gt 255 ]]; then
		add_error "package_id 长度超过限制（最大255字符）: ${#package_id}"
		return 1
	fi

	# 检查是否包含连续的点
	if [[ "$package_id" =~ \.\. ]]; then
		add_error "package_id 包含连续的点: '$package_id'"
		return 1
	fi

	# 检查是否以点开头或结尾
	if [[ "$package_id" =~ ^\.|\.$ ]]; then
		add_error "package_id 不能以点开头或结尾: '$package_id'"
		return 1
	fi

	return 0
}

# 函数：从工程目录名提取 package_id
extract_package_id_from_dir() {
	local dir_name
	dir_name=$(basename "$PROJECT_DIR")

	# 检查目录名格式：CI_ll_<package_id>
	if [[ ! "$dir_name" =~ ^CI_ll_(.+)$ ]]; then
		add_error "工程目录命名不符合规范: '$dir_name'，应为 'CI_ll_<package_id>' 格式"
		return 1
	fi

	local package_id="${BASH_REMATCH[1]}"
	echo "$package_id"
	return 0
}

# 函数：验证工程目录命名
validate_project_dir_naming() {
	local dir_name
	dir_name=$(basename "$PROJECT_DIR")

	# 检查目录是否存在
	if [[ ! -d "$PROJECT_DIR" ]]; then
		add_error "工程目录不存在: $PROJECT_DIR"
		return 1
	fi

	# 检查目录名格式
	if [[ ! "$dir_name" =~ ^CI_ll_(.+)$ ]]; then
		add_error "工程目录命名不符合规范: '$dir_name'，应为 'CI_ll_<package_id>' 格式"
		return 1
	fi

	local package_id="${BASH_REMATCH[1]}"

	# 验证提取的 package_id 格式
	if ! validate_package_id_format "$package_id"; then
		return 1
	fi

	return 0
}

# 函数：验证 linglong.yaml 中的 package_id
validate_yaml_package_id() {
	local yaml_path="$PROJECT_DIR/templates/linglong.yaml"

	if [[ ! -f "$yaml_path" ]]; then
		add_warning "linglong.yaml 不存在: $yaml_path"
		return 0
	fi

	# 提取 package.id
	local yaml_package_id
	yaml_package_id=$(grep -E '^\s+id:\s*' "$yaml_path" | head -n1 | sed 's/^\s*id:\s*//' | tr -d '"' | tr -d "'")

	if [[ -z "$yaml_package_id" ]]; then
		add_error "linglong.yaml 中未找到 package.id 字段"
		return 1
	fi

	# 从目录名提取期望的 package_id
	local expected_id
	expected_id=$(extract_package_id_from_dir)

	if [[ $? -ne 0 ]]; then
		return 1
	fi

	# 比较
	if [[ "$yaml_package_id" != "$expected_id" ]]; then
		add_error "linglong.yaml 中的 package.id ('$yaml_package_id') 与工程目录不匹配（期望: '$expected_id'）"
		return 1
	fi

	# 验证格式
	if ! validate_package_id_format "$yaml_package_id"; then
		return 1
	fi

	return 0
}

# 函数：验证 deb 文件存储路径
validate_deb_path() {
	local deb_path="$1"

	if [[ -z "$deb_path" ]]; then
		return 0
	fi

	if [[ ! -f "$deb_path" ]]; then
		add_error "deb 文件不存在: $deb_path"
		return 1
	fi

	# 获取 deb 文件所在目录
	local deb_dir
	deb_dir=$(dirname "$deb_path")
	deb_dir=$(basename "$deb_dir")

	# 从工程目录提取 package_id
	local expected_id
	expected_id=$(extract_package_id_from_dir)

	if [[ $? -ne 0 ]]; then
		return 1
	fi

	# 检查 deb 文件是否在正确的目录下
	# 期望路径：<package_id>/xxx.deb
	if [[ "$deb_dir" != "$expected_id" ]]; then
		add_error "deb 文件存储路径不正确: '$deb_path'"
		add_error "期望路径格式: $expected_id/xxx.deb"
		return 1
	fi

	return 0
}

# 函数：生成 JSON 报告
generate_report() {
	local status="passed"

	if [[ ${#ERRORS[@]} -gt 0 ]]; then
		status="failed"
	elif [[ ${#WARNINGS[@]} -gt 0 ]]; then
		status="warning"
	fi

	# 开始 JSON 输出
	echo "{"
	echo "  \"status\": \"$status\","

	# package_id 信息
	local package_id
	package_id=$(extract_package_id_from_dir 2>/dev/null || echo "")
	echo "  \"package_id\": \"$package_id\","
	echo "  \"project_dir\": \"$(basename "$PROJECT_DIR")\","

	# 错误列表
	echo "  \"errors\": ["
	for i in "${!ERRORS[@]}"; do
		if [[ $i -gt 0 ]]; then echo ","; fi
		echo -n "    \"${ERRORS[$i]}\""
	done
	echo ""
	echo "  ],"

	# 警告列表
	echo "  \"warnings\": ["
	for i in "${!WARNINGS[@]}"; do
		if [[ $i -gt 0 ]]; then echo ","; fi
		echo -n "    \"${WARNINGS[$i]}\""
	done
	echo ""
	echo "  ]"

	echo "}"
}

# 主函数
main() {
	local exit_code=0

	# 1. 验证工程目录命名
	if ! validate_project_dir_naming; then
		exit_code=1
	fi

	# 2. 验证 linglong.yaml 中的 package_id
	if ! validate_yaml_package_id; then
		exit_code=1
	fi

	# 3. 验证 deb 文件路径（如果指定）
	if [[ -n "$DEB_PATH" ]]; then
		if ! validate_deb_path "$DEB_PATH"; then
			exit_code=1
		fi
	fi

	# 生成报告
	generate_report

	return $exit_code
}

# 执行主函数
main
exit $?
