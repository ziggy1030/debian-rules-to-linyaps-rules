#!/bin/bash
# validate_project_structure.sh - 验证玲珑打包项目目录结构和必要文件
#
# 用法:
#   validate_project_structure.sh <project_dir> [--config <json>] [--fix] [--json] [--verbose]
#
# 参数:
#   project_dir - 项目目录路径 (如 CI_ll_com.example.app)
#   --config    - 可选，自定义JSON配置文件路径
#   --fix       - 可选，自动修复权限问题
#   --json      - 可选，输出JSON格式结果
#   --verbose   - 可选，详细输出
#
# 示例:
#   validate_project_structure.sh ./CI_ll_com.opera.browser
#   validate_project_structure.sh ./CI_ll_com.opera.browser --fix
#   validate_project_structure.sh ./CI_ll_com.opera.browser --config custom.json --json

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 全局变量
VERBOSE=false
AUTO_FIX=false
JSON_OUTPUT=false
PROJECT_DIR=""
CONFIG_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 结果统计
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
FIXED_CHECKS=0

# 结果数组（用于JSON输出）
declare -a RESULTS

log_info() {
	if [ "$JSON_OUTPUT" = false ]; then
		echo -e "${BLUE}[INFO]${NC} $1" >&2
	fi
}

log_success() {
	if [ "$JSON_OUTPUT" = false ]; then
		echo -e "${GREEN}[PASS]${NC} $1" >&2
	fi
}

log_error() {
	if [ "$JSON_OUTPUT" = false ]; then
		echo -e "${RED}[FAIL]${NC} $1" >&2
	fi
}

log_warning() {
	if [ "$JSON_OUTPUT" = false ]; then
		echo -e "${YELLOW}[WARN]${NC} $1" >&2
	fi
}

log_fixed() {
	if [ "$JSON_OUTPUT" = false ]; then
		echo -e "${GREEN}[FIXED]${NC} $1" >&2
	fi
}

usage() {
	echo "用法: $0 <project_dir> [--config <json>] [--fix] [--json] [--verbose]"
	echo ""
	echo "参数:"
	echo "  project_dir - 项目目录路径 (如 CI_ll_com.example.app)"
	echo "  --config    - 可选，自定义JSON配置文件路径"
	echo "  --fix       - 可选，自动修复权限问题"
	echo "  --json      - 可选，输出JSON格式结果"
	echo "  --verbose   - 可选，详细输出"
	echo ""
	echo "示例:"
	echo "  $0 ./CI_ll_com.opera.browser"
	echo "  $0 ./CI_ll_com.opera.browser --fix"
	echo "  $0 ./CI_ll_com.opera.browser --config custom.json --json"
}

parse_args() {
	if [ $# -lt 1 ]; then
		usage
		exit 1
	fi

	PROJECT_DIR="$1"
	shift

	while [ $# -gt 0 ]; do
		case "$1" in
		--config)
			CONFIG_FILE="$2"
			shift 2
			;;
		--fix)
			AUTO_FIX=true
			shift
			;;
		--json)
			JSON_OUTPUT=true
			shift
			;;
		--verbose)
			VERBOSE=true
			shift
			;;
		*)
			log_error "未知参数: $1"
			usage
			exit 1
			;;
		esac
	done

	# 验证项目目录
	if [ ! -d "$PROJECT_DIR" ]; then
		log_error "项目目录不存在: $PROJECT_DIR"
		exit 1
	fi

	# 转换为绝对路径
	PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

	# 使用默认配置文件
	if [ -z "$CONFIG_FILE" ]; then
		CONFIG_FILE="${SCRIPT_DIR}/default_check_config.json"
	fi

	if [ ! -f "$CONFIG_FILE" ]; then
		log_error "配置文件不存在: $CONFIG_FILE"
		exit 1
	fi
}

# 检查是否包含通配符
has_wildcard() {
	local pattern="$1"
	[[ "$pattern" == *\** ]] || [[ "$pattern" == *\?* ]]
}

# 检查目录
check_directory() {
	local pattern="$1"
	local path="${PROJECT_DIR}/${pattern}"

	TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

	if [ -d "$path" ]; then
		log_success "目录存在: $pattern"
		PASSED_CHECKS=$((PASSED_CHECKS + 1))
		echo "{\"check\": \"directory\", \"pattern\": \"$pattern\", \"status\": \"pass\"}"
		return 0
	else
		log_error "目录缺失: $pattern"
		FAILED_CHECKS=$((FAILED_CHECKS + 1))
		echo "{\"check\": \"directory\", \"pattern\": \"$pattern\", \"status\": \"fail\", \"message\": \"目录不存在\"}"
		return 1
	fi
}

# 检查文件
check_file() {
	local pattern="$1"
	local min="${2:-1}"
	local path="${PROJECT_DIR}/${pattern}"

	TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

	if has_wildcard "$pattern"; then
		# 通配符模式，统计匹配数量
		local matches=()
		while IFS= read -r -d '' match; do
			matches+=("$match")
		done < <(find "${PROJECT_DIR}" -path "${path}" -print0 2>/dev/null | head -n 100)

		local count=${#matches[@]}

		if [ "$count" -ge "$min" ]; then
			log_success "文件匹配: $pattern (找到 $count 个，需要 >= $min)"
			PASSED_CHECKS=$((PASSED_CHECKS + 1))
			echo "{\"check\": \"file\", \"pattern\": \"$pattern\", \"status\": \"pass\", \"count\": $count}"
			return 0
		else
			log_error "文件不足: $pattern (找到 $count 个，需要 >= $min)"
			FAILED_CHECKS=$((FAILED_CHECKS + 1))
			echo "{\"check\": \"file\", \"pattern\": \"$pattern\", \"status\": \"fail\", \"count\": $count, \"min\": $min, \"message\": \"文件数量不足\"}"
			return 1
		fi
	else
		# 单个文件检查
		if [ -f "$path" ]; then
			log_success "文件存在: $pattern"
			PASSED_CHECKS=$((PASSED_CHECKS + 1))
			echo "{\"check\": \"file\", \"pattern\": \"$pattern\", \"status\": \"pass\"}"
			return 0
		else
			log_error "文件缺失: $pattern"
			FAILED_CHECKS=$((FAILED_CHECKS + 1))
			echo "{\"check\": \"file\", \"pattern\": \"$pattern\", \"status\": \"fail\", \"message\": \"文件不存在\"}"
			return 1
		fi
	fi
}

# 检查可执行权限
check_executable() {
	local pattern="$1"
	local path="${PROJECT_DIR}/${pattern}"

	if has_wildcard "$pattern"; then
		# 通配符模式，展开检查
		local found_any=false
		local all_executable=true
		local files=()

		while IFS= read -r -d '' file; do
			files+=("$file")
			found_any=true
			if [ ! -x "$file" ]; then
				all_executable=false
				TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
				FAILED_CHECKS=$((FAILED_CHECKS + 1))

				if [ "$AUTO_FIX" = true ]; then
					chmod +x "$file"
					log_fixed "已添加可执行权限: ${file#$PROJECT_DIR/}"
					FIXED_CHECKS=$((FIXED_CHECKS + 1))
					PASSED_CHECKS=$((PASSED_CHECKS + 1))
					FAILED_CHECKS=$((FAILED_CHECKS - 1))
				else
					log_error "缺少可执行权限: ${file#$PROJECT_DIR/}"
				fi
			else
				TOTAL_CHECKS=$((TOTAL_CHECKS + 1))
				PASSED_CHECKS=$((PASSED_CHECKS + 1))
				[ "$VERBOSE" = true ] && log_success "可执行权限正常: ${file#$PROJECT_DIR/}"
			fi
		done < <(find "${PROJECT_DIR}" -path "${path}" -type f -print0 2>/dev/null | head -n 100)

		if [ "$found_any" = false ]; then
			log_warning "未找到匹配文件: $pattern"
		fi
	else
		# 单个文件检查
		TOTAL_CHECKS=$((TOTAL_CHECKS + 1))

		if [ ! -f "$path" ]; then
			log_warning "文件不存在，跳过权限检查: $pattern"
			return 0
		fi

		if [ -x "$path" ]; then
			log_success "可执行权限正常: $pattern"
			PASSED_CHECKS=$((PASSED_CHECKS + 1))
			echo "{\"check\": \"executable\", \"pattern\": \"$pattern\", \"status\": \"pass\"}"
		else
			if [ "$AUTO_FIX" = true ]; then
				chmod +x "$path"
				log_fixed "已添加可执行权限: $pattern"
				FIXED_CHECKS=$((FIXED_CHECKS + 1))
				PASSED_CHECKS=$((PASSED_CHECKS + 1))
				echo "{\"check\": \"executable\", \"pattern\": \"$pattern\", \"status\": \"fixed\"}"
			else
				log_error "缺少可执行权限: $pattern"
				FAILED_CHECKS=$((FAILED_CHECKS + 1))
				echo "{\"check\": \"executable\", \"pattern\": \"$pattern\", \"status\": \"fail\", \"message\": \"缺少可执行权限\"}"
			fi
		fi
	fi
}

# JSON解析函数 - 优先使用jq，备选使用python3
json_parse() {
	local json_file="$1"
	local query="$2"

	if command -v jq &>/dev/null; then
		jq -r "$query" "$json_file" 2>/dev/null
	elif command -v python3 &>/dev/null; then
		python3 -c "
import json, sys
with open('$json_file', 'r') as f:
    data = json.load(f)
result = data
for key in '$query'.split('.'):
    if key.startswith('[') and key.endswith(']'):
        idx = int(key[1:-1])
        result = result[idx]
    elif key == '[]':
        for item in result:
            print(json.dumps(item))
        sys.exit(0)
    elif key in result:
        result = result[key]
    else:
        sys.exit(1)
if isinstance(result, list):
    for item in result:
        print(json.dumps(item))
else:
    print(result)
" 2>/dev/null
	else
		return 1
	fi
}

# 解析JSON配置并执行检查
run_checks() {
	log_info "项目目录: $PROJECT_DIR"
	log_info "配置文件: $CONFIG_FILE"
	echo ""

	# 检查JSON解析工具是否可用
	if ! command -v jq &>/dev/null && ! command -v python3 &>/dev/null; then
		log_error "需要安装 jq 或 python3 工具来解析JSON配置"
		log_info "安装方法: sudo apt install jq 或 sudo apt install python3"
		exit 1
	fi

	# 读取checks数组
	local checks_json=$(json_parse "$CONFIG_FILE" '.checks[]')

	if [ -z "$checks_json" ]; then
		log_error "配置文件格式错误或checks数组为空"
		exit 1
	fi

	# 处理每个检查项
	while IFS= read -r check_item; do
		local pattern=$(echo "$check_item" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['pattern'])" 2>/dev/null)
		local type=$(echo "$check_item" | python3 -c "import json,sys; print(json.loads(sys.stdin.read())['type'])" 2>/dev/null)
		local min=$(echo "$check_item" | python3 -c "import json,sys; d=json.loads(sys.stdin.read()); print(d.get('min', ''))" 2>/dev/null)

		case "$type" in
		directory)
			check_directory "$pattern"
			;;
		file)
			check_file "$pattern" "$min"
			;;
		*)
			log_warning "未知检查类型: $type (pattern: $pattern)"
			;;
		esac
	done <<<"$checks_json"

	# 读取executable数组
	local exec_json=$(json_parse "$CONFIG_FILE" '.executable[]')

	if [ -n "$exec_json" ]; then
		log_info ""
		log_info "检查可执行权限..."

		while IFS= read -r exec_pattern; do
			# 去除可能的引号
			exec_pattern=$(echo "$exec_pattern" | tr -d '"')
			check_executable "$exec_pattern"
		done <<<"$exec_json"
	fi
}

# 输出JSON格式结果
output_json_result() {
	local status="pass"
	if [ $FAILED_CHECKS -gt 0 ]; then
		status="fail"
	fi

	cat <<EOF
{
  "project_dir": "$PROJECT_DIR",
  "config_file": "$CONFIG_FILE",
  "summary": {
    "total": $TOTAL_CHECKS,
    "passed": $PASSED_CHECKS,
    "failed": $FAILED_CHECKS,
    "fixed": $FIXED_CHECKS
  },
  "status": "$status"
}
EOF
}

# 输出文本格式结果
output_text_result() {
	echo ""
	echo "================================"
	echo "检查结果汇总"
	echo "================================"
	echo "项目目录: $PROJECT_DIR"
	echo "总检查项: $TOTAL_CHECKS"
	echo "通过: $PASSED_CHECKS"
	echo "失败: $FAILED_CHECKS"

	if [ "$AUTO_FIX" = true ] && [ $FIXED_CHECKS -gt 0 ]; then
		echo "已修复: $FIXED_CHECKS"
	fi

	echo ""

	if [ $FAILED_CHECKS -gt 0 ]; then
		echo -e "${RED}状态: 失败${NC}"
		return 1
	else
		echo -e "${GREEN}状态: 通过${NC}"
		return 0
	fi
}

main() {
	parse_args "$@"

	if [ "$JSON_OUTPUT" = true ]; then
		run_checks >/dev/null 2>&1
		output_json_result
	else
		run_checks
		output_text_result
	fi
}

main "$@"
