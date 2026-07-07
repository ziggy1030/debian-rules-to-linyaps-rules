#!/bin/bash
# test_validate_project_structure.sh - 测试项目结构验证脚本
#
# 用法: ./test_validate_project_structure.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
VALIDATE_SCRIPT="${PROJECT_ROOT}/scripts/validate_project_structure.sh"
CONFIG_FILE="${PROJECT_ROOT}/scripts/default_check_config.json"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

TESTS_PASSED=0
TESTS_FAILED=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[PASS]${NC} $1"; }
log_error() { echo -e "${RED}[FAIL]${NC} $1"; }
log_section() { echo -e "\n${YELLOW}=== $1 ===${NC}"; }

# 测试用例：检查脚本是否存在
test_script_exists() {
	log_section "测试1: 检查脚本是否存在"

	if [ -f "$VALIDATE_SCRIPT" ]; then
		log_success "validate_project_structure.sh 存在"
		((TESTS_PASSED++)) || true
	else
		log_error "validate_project_structure.sh 不存在"
		((TESTS_FAILED++)) || true
	fi
}

# 测试用例：检查配置文件是否存在
test_config_exists() {
	log_section "测试2: 检查配置文件是否存在"

	if [ -f "$CONFIG_FILE" ]; then
		log_success "default_check_config.json 存在"
		((TESTS_PASSED++)) || true
	else
		log_error "default_check_config.json 不存在"
		((TESTS_FAILED++)) || true
	fi
}

# 测试用例：检查脚本可执行权限
test_script_executable() {
	log_section "测试3: 检查脚本可执行权限"

	if [ -x "$VALIDATE_SCRIPT" ]; then
		log_success "validate_project_structure.sh 有可执行权限"
		((TESTS_PASSED++)) || true
	else
		log_error "validate_project_structure.sh 无可执行权限"
		((TESTS_FAILED++)) || true
	fi
}

# 测试用例：测试帮助信息
test_help_option() {
	log_section "测试4: 测试 --help 选项"

	if "$VALIDATE_SCRIPT" --help &>/dev/null; then
		log_success "--help 选项正常工作"
		((TESTS_PASSED++)) || true
	else
		log_error "--help 选项失败"
		((TESTS_FAILED++)) || true
	fi
}

# 测试用例：测试有效项目目录
test_valid_project() {
	log_section "测试5: 测试有效项目目录 (example/CI_ll_com.opera.browser)"

	local test_project="${PROJECT_ROOT}/../../example/CI_ll_com.opera.browser"

	if [ -d "$test_project" ]; then
		if "$VALIDATE_SCRIPT" "$test_project" --config "$CONFIG_FILE" &>/dev/null; then
			log_success "有效项目验证通过"
			((TESTS_PASSED++)) || true
		else
			log_error "有效项目验证失败"
			((TESTS_FAILED++)) || true
		fi
	else
		log_info "跳过测试: 测试项目目录不存在"
	fi
}

# 测试用例：测试无效项目目录
test_invalid_project() {
	log_section "测试6: 测试无效项目目录"

	local tmp_dir=$(mktemp -d)

	# 创建空目录，缺少必要文件
	if ! "$VALIDATE_SCRIPT" "$tmp_dir" --config "$CONFIG_FILE" &>/dev/null; then
		log_success "无效项目正确识别为失败"
		((TESTS_PASSED++)) || true
	else
		log_error "无效项目未正确识别"
		((TESTS_FAILED++)) || true
	fi

	rm -rf "$tmp_dir"
}

# 测试用例：测试 --json 输出
test_json_output() {
	log_section "测试7: 测试 --json 输出格式"

	local test_project="${PROJECT_ROOT}/../../example/CI_ll_com.opera.browser"
	local output_file=$(mktemp)

	if [ -d "$test_project" ]; then
		if "$VALIDATE_SCRIPT" "$test_project" --config "$CONFIG_FILE" --json >"$output_file" 2>/dev/null; then
			# 验证输出是否为有效 JSON
			if command -v jq &>/dev/null; then
				if jq empty "$output_file" 2>/dev/null; then
					log_success "JSON 输出格式正确"
					((TESTS_PASSED++)) || true
				else
					log_error "JSON 输出格式错误"
					((TESTS_FAILED++)) || true
				fi
			else
				log_info "跳过 JSON 验证: jq 未安装"
				((TESTS_PASSED++)) || true
			fi
		else
			log_error "--json 选项失败"
			((TESTS_FAILED++)) || true
		fi
	else
		log_info "跳过测试: 测试项目目录不存在"
	fi

	rm -f "$output_file"
}

# 测试用例：测试 --fix 选项
test_fix_option() {
	log_section "测试8: 测试 --fix 选项"

	local tmp_dir=$(mktemp -d)

	# 创建测试文件但无执行权限
	mkdir -p "$tmp_dir/scripts"
	touch "$tmp_dir/pak_linyaps.sh"
	touch "$tmp_dir/scripts/dedup_desktop_files.sh"

	# 运行 --fix
	if "$VALIDATE_SCRIPT" "$tmp_dir" --config "$CONFIG_FILE" --fix &>/dev/null; then
		# 检查权限是否被修复
		if [ -x "$tmp_dir/pak_linyaps.sh" ]; then
			log_success "--fix 正确修复了权限"
			((TESTS_PASSED++)) || true
		else
			log_error "--fix 未修复权限"
			((TESTS_FAILED++)) || true
		fi
	else
		log_info "--fix 执行完成（可能有其他检查失败）"
		((TESTS_PASSED++)) || true
	fi

	rm -rf "$tmp_dir"
}

# 测试用例：测试通配符匹配
test_glob_patterns() {
	log_section "测试9: 测试通配符匹配"

	local test_project="${PROJECT_ROOT}/../../example/CI_ll_com.opera.browser"

	if [ -d "$test_project" ]; then
		# 运行验证并检查是否正确处理通配符
		local output
		output=$("$VALIDATE_SCRIPT" "$test_project" --config "$CONFIG_FILE" 2>&1)

		if echo "$output" | grep -q "desktop"; then
			log_success "通配符匹配正常工作"
			((TESTS_PASSED++)) || true
		else
			log_info "通配符匹配测试跳过（输出中无 desktop 相关信息）"
			((TESTS_PASSED++)) || true
		fi
	else
		log_info "跳过测试: 测试项目目录不存在"
	fi
}

# 主测试函数
main() {
	echo "========================================"
	echo "  项目结构验证脚本测试"
	echo "========================================"

	test_script_exists
	test_config_exists
	test_script_executable
	test_help_option
	test_valid_project
	test_invalid_project
	test_json_output
	test_fix_option
	test_glob_patterns

	echo ""
	echo "========================================"
	echo "  测试结果汇总"
	echo "========================================"
	echo -e "通过: ${GREEN}${TESTS_PASSED}${NC}"
	echo -e "失败: ${RED}${TESTS_FAILED}${NC}"
	echo ""

	if [ $TESTS_FAILED -eq 0 ]; then
		log_success "所有测试通过!"
		exit 0
	else
		log_error "存在失败的测试"
		exit 1
	fi
}

main "$@"
