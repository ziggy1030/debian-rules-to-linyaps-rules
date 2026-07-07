#!/bin/bash
# validate_bin_nesting.sh - 检测并修复 binary/bin/bin/ 嵌套错误路径
#
# 问题原因：
# 1. handle_special_paths.sh 将 /usr/bin/* 复制到 binary/bin/
# 2. pak_linyaps.sh 又创建 binary/bin/ 用于软链
# 3. linglong.yaml 的 build 脚本创建 ${prefix}/bin/
# 4. cp -rf /project/binary/* ${prefix}/ 导致 files/bin/bin/ 嵌套
#
# 用法：
#   validate_bin_nesting.sh <directory> [--fix]
#
# 参数：
#   directory - 要检查的目录（如 binary/ 或 files/）
#   --fix     - 可选，自动修复检测到的问题

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VERBOSE=false
AUTO_FIX=false
CHECK_DIR=""
ISSUES_FOUND=0
FIXES_APPLIED=0

log_info() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
log_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }

usage() {
	echo "用法: $0 <directory> [--fix]"
	echo ""
	echo "参数:"
	echo "  directory - 要检查的目录（如 binary/ 或 files/）"
	echo "  --fix     - 可选，自动修复检测到的问题"
	echo ""
	echo "示例:"
	echo "  $0 ./binary"
	echo "  $0 ./files --fix"
}

parse_args() {
	if [ $# -lt 1 ]; then
		usage
		exit 1
	fi

	CHECK_DIR="$1"
	if [ "$2" = "--fix" ]; then
		AUTO_FIX=true
	elif [ "$2" = "--verbose" ]; then
		VERBOSE=true
	elif [ "$2" = "--fix" ] && [ "$3" = "--verbose" ]; then
		AUTO_FIX=true
		VERBOSE=true
	fi

	if [ ! -d "${CHECK_DIR}" ]; then
		log_error "目录不存在: ${CHECK_DIR}"
		exit 1
	fi

	CHECK_DIR=$(readlink -f "${CHECK_DIR}")
}

# 检测 nested bin/ 嵌套（binary/bin/bin/ 或 files/bin/bin/）
detect_nested_bin() {
	log_info "检测 nested bin/ 嵌套问题..."

	local nested_count=0

	# 查找 nested bin/ 目录
	while IFS= read -r nested_bin; do
		((nested_count++)) || true
		log_warning "  发现嵌套 bin/: ${nested_bin}"

		# 列出嵌套 bin/ 中的内容
		if [ -d "${nested_bin}" ]; then
			log_info "    内容:"
			while IFS= read -r item; do
				log_info "      - $(basename "${item}")"
			done < <(find "${nested_bin}" -maxdepth 1 -type f -o -type l 2>/dev/null)
		fi

		((ISSUES_FOUND++)) || true
	done < <(find "${CHECK_DIR}" -path "*/bin/bin" -type d 2>/dev/null)

	if [ ${nested_count} -eq 0 ]; then
		log_success "  未发现嵌套 bin/ 问题"
	else
		log_warning "  共发现 ${nested_count} 个嵌套 bin/ 目录"
	fi
}

# 检测软链指向问题
detect_symlink_issues() {
	log_info "检测软链指向问题..."

	local symlink_count=0
	local broken_count=0

	while IFS= read -r link; do
		((symlink_count++)) || true
		local target=$(readlink "${link}")
		local link_name=$(basename "${link}")

		if [ ! -e "${link}" ]; then
			((broken_count++)) || true
			log_warning "  断开软链: ${link_name} -> ${target}"
			((ISSUES_FOUND++)) || true
		elif [ "${VERBOSE}" = "true" ]; then
			log_info "  正常软链: ${link_name} -> ${target}"
		fi
	done < <(find "${CHECK_DIR}" -type l 2>/dev/null)

	if [ ${symlink_count} -eq 0 ]; then
		log_info "  未发现软链"
	else
		log_info "  共 ${symlink_count} 个软链，${broken_count} 个断开"
	fi
}

# 修复嵌套 bin/ 问题
fix_nested_bin() {
	log_info "修复嵌套 bin/ 问题..."

	local fixed_count=0

	while IFS= read -r nested_bin; do
		# 获取父目录
		local parent_dir=$(dirname "${nested_bin}")

		log_info "  处理: ${nested_bin}"
		log_info "    父目录: ${parent_dir}"

		# 将 nested bin/ 内容上移到父目录
		if [ -d "${nested_bin}" ]; then
			# 检查父目录中是否已有同名文件
			local has_conflict=false
			while IFS= read -r item; do
				local item_name=$(basename "${item}")
				if [ -e "${parent_dir}/${item_name}" ]; then
					log_warning "    冲突: ${item_name} 已存在"
					has_conflict=true
				fi
			done < <(find "${nested_bin}" -maxdepth 1 2>/dev/null)

			if [ "${has_conflict}" = "false" ]; then
				# 移动内容到父目录
				mv "${nested_bin}"/* "${parent_dir}/" 2>/dev/null || true
				rmdir "${nested_bin}" 2>/dev/null || true
				log_success "    已修复: 移动内容到 ${parent_dir}"
				((fixed_count++)) || true
				((FIXES_APPLIED++)) || true
			else
				log_warning "    跳过: 存在冲突"
			fi
		fi
	done < <(find "${CHECK_DIR}" -path "*/bin/bin" -type d 2>/dev/null)

	log_info "  修复完成: ${fixed_count} 个嵌套 bin/ 已处理"
}

# 验证打包前的 binary/ 结构
validate_binary_structure() {
	log_info "验证 binary/ 目录结构..."

	local bin_count=0

	# 统计 bin/ 目录数量
	while IFS= read -r bin_dir; do
		((bin_count++)) || true
	done < <(find "${CHECK_DIR}" -type d -name "bin" 2>/dev/null)

	log_info "  bin/ 目录数量: ${bin_count}"

	if [ ${bin_count} -gt 1 ]; then
		log_warning "  检测到多个 bin/ 目录，可能存在嵌套问题"
		((ISSUES_FOUND++)) || true
	fi

	# 检查 binary/bin/ 是否存在
	if [ -d "${CHECK_DIR}/bin" ]; then
		log_info "  发现 binary/bin/ 目录"

		# 列出内容
		local bin_content=$(find "${CHECK_DIR}/bin" -maxdepth 1 -type f -o -type l 2>/dev/null | wc -l)
		log_info "    内容数量: ${bin_content}"
	fi
}

# 打印检查报告
print_report() {
	echo ""
	echo "========================================="
	echo "  检查报告"
	echo "========================================="
	echo "  检查目录: ${CHECK_DIR}"
	echo "  发现问题: ${ISSUES_FOUND}"
	echo "  修复项数: ${FIXES_APPLIED}"
	echo "========================================="

	if [ ${ISSUES_FOUND} -gt 0 ]; then
		if [ "${AUTO_FIX}" = "true" ]; then
			echo -e "${YELLOW}  状态: 已自动修复${NC}"
		else
			echo -e "${RED}  状态: 发现问题，建议使用 --fix 修复${NC}"
		fi
	else
		echo -e "${GREEN}  状态: 检查通过${NC}"
	fi
	echo "========================================="
}

main() {
	parse_args "$@"

	echo "========================================="
	echo "  binary/ 嵌套路径检查脚本"
	echo "========================================="
	echo "检查目录: ${CHECK_DIR}"
	echo "自动修复: ${AUTO_FIX}"
	echo "========================================="

	# 执行检查
	detect_nested_bin
	validate_binary_structure
	detect_symlink_issues

	# 自动修复
	if [ "${AUTO_FIX}" = "true" ] && [ ${ISSUES_FOUND} -gt 0 ]; then
		echo ""
		fix_nested_bin
	fi

	# 打印报告
	print_report

	# 返回状态
	if [ ${ISSUES_FOUND} -gt 0 ]; then
		exit 1
	else
		exit 0
	fi
}

main "$@"
