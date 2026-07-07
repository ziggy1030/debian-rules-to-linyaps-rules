#!/bin/bash
# fix_package_id.sh - 修复玲珑包ID相关问题
#
# 功能：
#   1. 修复工程目录命名（重命名为正确的 CI_ll_<package_id> 格式）
#   2. 修复 linglong.yaml 中的 package.id 字段
#   3. 修复 desktop 文件中的相关引用
#   4. 生成修复报告
#
# 用法：
#   ./fix_package_id.sh <project_dir> [--new-id <package_id>] [--dry-run]
#
# 参数：
#   project_dir  - 工程目录路径
#   --new-id     - 可选，指定新的 package_id（如不指定则从 linglong.yaml 提取）
#   --dry-run    - 仅模拟执行，不实际修改文件
#   --rename-dir - 允许重命名工程目录
#
# 返回值：
#   0 - 修复成功
#   1 - 修复失败

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认值
PROJECT_DIR=""
NEW_PACKAGE_ID=""
DRY_RUN=false
RENAME_DIR=false
VERBOSE=false

# 解析参数
while [[ $# -gt 0 ]]; do
	case $1 in
	--new-id)
		NEW_PACKAGE_ID="$2"
		shift 2
		;;
	--dry-run)
		DRY_RUN=true
		shift
		;;
	--rename-dir)
		RENAME_DIR=true
		shift
		;;
	--verbose | -v)
		VERBOSE=true
		shift
		;;
	--help | -h)
		echo "用法: $0 <project_dir> [--new-id <package_id>] [--dry-run] [--rename-dir]"
		echo ""
		echo "参数:"
		echo "  project_dir    工程目录路径"
		echo "  --new-id       指定新的 package_id（如不指定则从 linglong.yaml 提取）"
		echo "  --dry-run      仅模拟执行，不实际修改文件"
		echo "  --rename-dir   允许重命名工程目录"
		echo "  --verbose,-v   显示详细输出"
		echo "  --help,-h      显示帮助信息"
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

# 转换为绝对路径
PROJECT_DIR=$(cd "$(dirname "$PROJECT_DIR")" 2>/dev/null && pwd)/$(basename "$PROJECT_DIR")

# 检查目录是否存在，不存在则尝试创建
if [[ ! -d "$PROJECT_DIR" ]]; then
	echo -e "${YELLOW}工程目录不存在，尝试创建: $PROJECT_DIR${NC}"
	if mkdir -p "$PROJECT_DIR"; then
		echo -e "${GREEN}成功创建工程目录: $PROJECT_DIR${NC}"
	else
		echo -e "${RED}错误: 无法创建工程目录: $PROJECT_DIR${NC}" >&2
		exit 1
	fi
fi

# 修复记录
declare -a FIXES_APPLIED
declare -a FIXES_FAILED

# 日志函数
log_info() {
	if $VERBOSE; then
		echo -e "${BLUE}[INFO] $1${NC}"
	fi
}

log_success() {
	echo -e "${GREEN}[成功] $1${NC}"
}

log_warning() {
	echo -e "${YELLOW}[警告] $1${NC}"
}

log_error() {
	echo -e "${RED}[错误] $1${NC}" >&2
}

log_dry_run() {
	echo -e "${YELLOW}[模拟] $1${NC}"
}

# 函数：验证 package_id 格式
validate_package_id_format() {
	local package_id="$1"

	if [[ -z "$package_id" ]]; then
		return 1
	fi

	# 反向域名格式
	if [[ ! "$package_id" =~ ^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$ ]]; then
		return 1
	fi

	return 0
}

# 函数：从 linglong.yaml 提取 package_id
extract_package_id_from_yaml() {
	local yaml_path="$PROJECT_DIR/templates/linglong.yaml"

	if [[ ! -f "$yaml_path" ]]; then
		return 1
	fi

	local package_id
	package_id=$(grep -E '^\s+id:\s*' "$yaml_path" | head -n1 | sed 's/^\s*id:\s*//' | tr -d '"' | tr -d "'")

	if [[ -z "$package_id" ]]; then
		return 1
	fi

	echo "$package_id"
	return 0
}

# 函数：从工程目录名提取 package_id
extract_package_id_from_dir() {
	local dir_name
	dir_name=$(basename "$PROJECT_DIR")

	if [[ ! "$dir_name" =~ ^CI_ll_(.+)$ ]]; then
		return 1
	fi

	echo "${BASH_REMATCH[1]}"
	return 0
}

# 函数：修复 linglong.yaml 中的 package.id
fix_yaml_package_id() {
	local new_id="$1"
	local yaml_path="$PROJECT_DIR/templates/linglong.yaml"

	if [[ ! -f "$yaml_path" ]]; then
		log_error "linglong.yaml 不存在: $yaml_path"
		FIXES_FAILED+=("yaml_package_id: 文件不存在")
		return 1
	fi

	if $DRY_RUN; then
		log_dry_run "将更新 linglong.yaml 中的 package.id 为: $new_id"
		FIXES_APPLIED+=("yaml_package_id: $new_id (模拟)")
		return 0
	fi

	# 备份原文件
	cp "$yaml_path" "${yaml_path}.bak"

	# 替换 package.id
	if sed -i "s/^\(\s*id:\s*\).*$/\1${new_id}/" "$yaml_path"; then
		log_success "已更新 linglong.yaml 中的 package.id 为: $new_id"
		FIXES_APPLIED+=("yaml_package_id: $new_id")
		return 0
	else
		log_error "更新 linglong.yaml 失败"
		# 恢复备份
		mv "${yaml_path}.bak" "$yaml_path"
		FIXES_FAILED+=("yaml_package_id: 更新失败")
		return 1
	fi
}

# 函数：修复 desktop 文件中的相关引用
fix_desktop_files() {
	local new_id="$1"
	local desktop_dir="$PROJECT_DIR/templates/files_res/share/applications"

	if [[ ! -d "$desktop_dir" ]]; then
		log_info "desktop 文件目录不存在，跳过"
		return 0
	fi

	local desktop_count=0

	for desktop_file in "$desktop_dir"/*.desktop; do
		if [[ ! -f "$desktop_file" ]]; then
			continue
		fi

		((desktop_count++))
		local desktop_name=$(basename "$desktop_file")

		if $DRY_RUN; then
			log_dry_run "将检查并修复 desktop 文件: $desktop_name"
			continue
		fi

		# 备份
		cp "$desktop_file" "${desktop_file}.bak"

		# 修复 DBusActivatable 相关的路径（如果存在）
		if grep -q "DBusActivatable=true" "$desktop_file"; then
			# 更新 DBus 服务路径
			sed -i "s|/opt/apps/[^/]*/|/opt/apps/${new_id}/|g" "$desktop_file"
		fi

		log_success "已检查 desktop 文件: $desktop_name"
		FIXES_APPLIED+=("desktop_file: $desktop_name")
	done

	if [[ $desktop_count -eq 0 ]]; then
		log_info "未找到 desktop 文件"
	fi

	return 0
}

# 函数：重命名工程目录
rename_project_dir() {
	local new_id="$1"
	local current_dir="$PROJECT_DIR"
	local parent_dir=$(dirname "$PROJECT_DIR")
	local new_dir_name="CI_ll_${new_id}"
	local new_dir_path="${parent_dir}/${new_dir_name}"

	# 检查目标目录是否已存在
	if [[ -d "$new_dir_path" ]] && [[ "$new_dir_path" != "$current_dir" ]]; then
		log_error "目标目录已存在: $new_dir_path"
		FIXES_FAILED+=("rename_dir: 目标目录已存在")
		return 1
	fi

	if $DRY_RUN; then
		log_dry_run "将重命名目录: $(basename "$current_dir") -> $new_dir_name"
		FIXES_APPLIED+=("rename_dir: $new_dir_name (模拟)")
		return 0
	fi

	# 执行重命名
	if mv "$current_dir" "$new_dir_path"; then
		log_success "已重命名目录: $(basename "$current_dir") -> $new_dir_name"
		PROJECT_DIR="$new_dir_path"
		FIXES_APPLIED+=("rename_dir: $new_dir_name")
		return 0
	else
		log_error "重命名目录失败"
		FIXES_FAILED+=("rename_dir: 重命名失败")
		return 1
	fi
}

# 函数：生成修复报告
generate_report() {
	local status="success"

	if [[ ${#FIXES_FAILED[@]} -gt 0 ]]; then
		status="partial"
	fi

	if [[ ${#FIXES_APPLIED[@]} -eq 0 ]] && [[ ${#FIXES_FAILED[@]} -eq 0 ]]; then
		status="no_changes"
	fi

	echo ""
	echo "========================================"
	echo "修复报告"
	echo "========================================"
	echo "状态: $status"
	echo "工程目录: $PROJECT_DIR"
	echo ""

	if [[ ${#FIXES_APPLIED[@]} -gt 0 ]]; then
		echo "已应用的修复:"
		for fix in "${FIXES_APPLIED[@]}"; do
			echo "  ✓ $fix"
		done
		echo ""
	fi

	if [[ ${#FIXES_FAILED[@]} -gt 0 ]]; then
		echo "失败的修复:"
		for fail in "${FIXES_FAILED[@]}"; do
			echo "  ✗ $fail"
		done
		echo ""
	fi

	if $DRY_RUN; then
		echo "注意: 以上为模拟执行结果，未实际修改文件"
	fi

	echo "========================================"
}

# 主函数
main() {
	local target_package_id=""

	echo "========================================"
	echo "玲珑包ID修复工具"
	echo "========================================"
	echo "工程目录: $PROJECT_DIR"
	if $DRY_RUN; then
		echo "模式: 模拟执行 (--dry-run)"
	fi
	echo ""

	# 1. 确定目标 package_id
	if [[ -n "$NEW_PACKAGE_ID" ]]; then
		# 用户指定了新的 package_id
		if ! validate_package_id_format "$NEW_PACKAGE_ID"; then
			log_error "指定的 package_id 格式不正确: $NEW_PACKAGE_ID"
			log_info "正确格式示例: com.example.app"
			exit 1
		fi
		target_package_id="$NEW_PACKAGE_ID"
		log_info "使用指定的 package_id: $target_package_id"
	else
		# 从 linglong.yaml 提取
		target_package_id=$(extract_package_id_from_yaml)
		if [[ $? -eq 0 ]] && [[ -n "$target_package_id" ]]; then
			log_info "从 linglong.yaml 提取 package_id: $target_package_id"
		else
			# 从目录名提取
			target_package_id=$(extract_package_id_from_dir)
			if [[ $? -eq 0 ]] && [[ -n "$target_package_id" ]]; then
				log_info "从目录名提取 package_id: $target_package_id"
			else
				log_error "无法确定 package_id，请使用 --new-id 参数指定"
				exit 1
			fi
		fi
	fi

	# 验证提取的 package_id
	if ! validate_package_id_format "$target_package_id"; then
		log_error "提取的 package_id 格式不正确: $target_package_id"
		log_info "请使用 --new-id 参数指定正确的 package_id"
		exit 1
	fi

	echo "目标 package_id: $target_package_id"
	echo ""

	# 2. 检查当前状态
	local current_dir_id
	current_dir_id=$(extract_package_id_from_dir 2>/dev/null || echo "")

	local current_yaml_id
	current_yaml_id=$(extract_package_id_from_yaml 2>/dev/null || echo "")

	local need_fix=false

	# 检查目录命名
	if [[ "$current_dir_id" != "$target_package_id" ]]; then
		log_warning "工程目录命名不匹配: 当前='$current_dir_id', 期望='$target_package_id'"
		need_fix=true
	fi

	# 检查 YAML 中的 ID
	if [[ -n "$current_yaml_id" ]] && [[ "$current_yaml_id" != "$target_package_id" ]]; then
		log_warning "linglong.yaml 中的 package.id 不匹配: 当前='$current_yaml_id', 期望='$target_package_id'"
		need_fix=true
	fi

	if ! $need_fix; then
		log_success "所有检查通过，无需修复"
		generate_report
		exit 0
	fi

	echo ""
	echo "开始修复..."
	echo ""

	# 3. 执行修复

	# 修复 linglong.yaml
	if [[ -z "$current_yaml_id" ]] || [[ "$current_yaml_id" != "$target_package_id" ]]; then
		fix_yaml_package_id "$target_package_id"
	fi

	# 修复 desktop 文件
	fix_desktop_files "$target_package_id"

	# 重命名目录（如果需要且用户允许）
	if [[ "$current_dir_id" != "$target_package_id" ]]; then
		if $RENAME_DIR; then
			rename_project_dir "$target_package_id"
		else
			log_warning "工程目录命名不正确，但未启用 --rename-dir 选项"
			log_info "正确的目录名应为: CI_ll_${target_package_id}"
			FIXES_FAILED+=("rename_dir: 未启用 --rename-dir 选项")
		fi
	fi

	# 4. 生成报告
	generate_report

	# 返回状态
	if [[ ${#FIXES_FAILED[@]} -gt 0 ]]; then
		exit 1
	fi

	exit 0
}

# 执行主函数
main
