#!/bin/bash
# 特殊格式路径处理脚本
# 用于处理 deb 包解压后包含特殊字符路径的转换逻辑
#
# 功能：
# 1. 处理 /usr/ 下的标准目录
# 2. 处理 /opt/、/var/、/srv/ 等非标准路径
# 3. 标准化目录名（处理空格、特殊字符等）
# 4. 生成路径映射文件，供软链创建使用
#
# 用法：
#   handle_special_paths.sh <src_dir> <dest_dir> [--verbose]
#
# 参数：
#   src_dir   - deb 包解压后的源目录（如 binary_tmp_dir）
#   dest_dir  - 目标目录（如 binary_dir）
#   --verbose - 可选，显示详细日志
#
# 输出：
#   在 dest_dir 下生成 .path_mapping 文件，记录原始路径到标准化路径的映射
#   格式: 原始目录名|标准化目录名
#
# 示例：
#   handle_special_paths.sh /tmp/build/tmp /tmp/build/binary --verbose

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 全局变量
VERBOSE=false
SRC_DIR=""
DEST_DIR=""
PATH_MAPPING_FILE=""

# 统计变量
STAT_COPIED_FILES=0
STAT_COPIED_DIRS=0
STAT_NORMALIZED_FILES=0
STAT_NORMALIZED_DIRS=0
STAT_SKIPPED_FILES=0
STAT_WARNINGS=0
STAT_ERRORS=0

# 日志函数
log_info() {
	if [ "${VERBOSE}" = "true" ]; then
		echo -e "${BLUE}[INFO]${NC} $1" >&2
	fi
}

log_success() {
	echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
	echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

# 显示使用说明
usage() {
	echo "用法: $0 <src_dir> <dest_dir> [--verbose]"
	echo ""
	echo "参数:"
	echo "  src_dir   - deb 包解压后的源目录"
	echo "  dest_dir  - 目标目录"
	echo "  --verbose - 显示详细日志"
	echo ""
	echo "输出:"
	echo "  在 dest_dir 下生成 .path_mapping 文件"
	echo ""
	echo "示例:"
	echo "  $0 /tmp/build/tmp /tmp/build/binary"
	echo "  $0 /tmp/build/tmp /tmp/build/binary --verbose"
}

# 解析参数
parse_args() {
	if [ $# -lt 2 ]; then
		usage
		exit 1
	fi

	SRC_DIR="$1"
	DEST_DIR="$2"

	if [ "$3" = "--verbose" ]; then
		VERBOSE=true
	fi

	# 验证源目录存在
	if [ ! -d "${SRC_DIR}" ]; then
		log_error "源目录不存在: ${SRC_DIR}"
		exit 1
	fi

	# 创建目标目录
	mkdir -p "${DEST_DIR}"

	# 初始化路径映射文件
	PATH_MAPPING_FILE="${DEST_DIR}/.path_mapping"
	echo "# 原始目录名|标准化目录名" >"${PATH_MAPPING_FILE}"
	echo "# 生成时间: $(date)" >>"${PATH_MAPPING_FILE}"
}

# 标准化目录名
# 将空格、逗号、括号、&、@、#、$ 等特殊字符和中文替换为安全字符
normalize_dirname() {
	local original_name="$1"
	local normalized_name="${original_name}"

	# 检查是否需要标准化
	local needs_normalization=false

	# 检查空格
	if [[ "${normalized_name}" =~ [[:space:]] ]]; then
		needs_normalization=true
	fi

	# 检查逗号
	if [[ "${normalized_name}" =~ , ]]; then
		needs_normalization=true
	fi

	# 检查括号
	if [[ "${normalized_name}" =~ [()\[\]] ]]; then
		needs_normalization=true
	fi

	# 检查 & # $ 等特殊符号（保留 @ 符号，因为 @ 可以作为路径名合法存在）
	if echo "${normalized_name}" | grep -q '[&#$]'; then
		needs_normalization=true
	fi

	# 检查连字符（目录名以 - 开头时需要处理）
	if [[ "${normalized_name}" =~ ^- ]]; then
		needs_normalization=true
	fi

	# 检查是否包含非ASCII字符（中文等）- 使用更可靠的方式检测
	if [[ "${normalized_name}" == *[![:ascii:]]* ]]; then
		needs_normalization=true
	fi

	if [ "${needs_normalization}" = "true" ]; then
		# 执行标准化
		# 1. 空格替换为下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/[[:space:]]/_/g')

		# 2. 逗号替换为下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/,/_/g')

		# 3. 括号替换为下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/[()\[\]]/_/g')

		# 4. 特殊符号 & # $ 替换为下划线（保留 @ 符号）
		normalized_name=$(echo "${normalized_name}" | sed 's/\&/\_/g' | sed 's/[#$]/_/g')

		# 5. 连字符处理：目录名以 - 开头时替换为 _
		if [[ "${normalized_name}" =~ ^- ]]; then
			normalized_name="_${normalized_name:1}"
		fi

		# 6. 中文处理：替换为哈希值
		# 检测非ASCII字符并替换为哈希值
		if [[ "${normalized_name}" == *[![:ascii:]]* ]]; then
			# 计算哈希值（使用MD5的前8位）
			local hash
			hash=$(echo -n "${normalized_name}" | md5sum | cut -c1-8)
			# 替换所有非ASCII字符为下划线（使用更兼容的方式）
			normalized_name=$(echo "${normalized_name}" | sed 's/[^ -~]/_/g')
			# 在末尾添加哈希值
			normalized_name="${normalized_name}_${hash}"
		fi

		# 清理连续下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/__*/_/g')

		# 清理首尾下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/^_//;s/_$//')

		log_info "  标准化: '${original_name}' -> '${normalized_name}'"
	fi

	echo "${normalized_name}"
}

# 标准化文件名（与目录名使用相同的逻辑）
normalize_filename() {
	local original_name="$1"
	local normalized_name="${original_name}"

	# 检查是否需要标准化
	local needs_normalization=false

	# 检查空格
	if [[ "${normalized_name}" =~ [[:space:]] ]]; then
		needs_normalization=true
	fi

	# 检查逗号
	if [[ "${normalized_name}" =~ , ]]; then
		needs_normalization=true
	fi

	# 检查括号
	if [[ "${normalized_name}" =~ [()\[\]] ]]; then
		needs_normalization=true
	fi

	# 检查 & # $ 等特殊符号（保留 @ 符号，因为 @ 可以作为路径名合法存在）
	if echo "${normalized_name}" | grep -q '[&#$]'; then
		needs_normalization=true
	fi

	# 检查连字符（文件名以 - 开头时需要处理）
	if [[ "${normalized_name}" =~ ^- ]]; then
		needs_normalization=true
	fi

	# 检查是否包含非ASCII字符（中文等）
	if [[ "${normalized_name}" == *[![:ascii:]]* ]]; then
		needs_normalization=true
	fi

	if [ "${needs_normalization}" = "true" ]; then
		# 执行标准化
		# 1. 空格替换为下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/[[:space:]]/_/g')

		# 2. 逗号替换为下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/,/_/g')

		# 3. 括号替换为下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/[()\[\]]/_/g')

		# 4. 特殊符号 & # $ 替换为下划线（保留 @ 符号）
		normalized_name=$(echo "${normalized_name}" | sed 's/\&/\_/g' | sed 's/[#$]/_/g')

		# 5. 连字符处理：文件名以 - 开头时替换为 _
		if [[ "${normalized_name}" =~ ^- ]]; then
			normalized_name="_${normalized_name:1}"
		fi

		# 6. 中文处理：替换为哈希值
		if [[ "${normalized_name}" == *[![:ascii:]]* ]]; then
			# 计算哈希值（使用MD5的前8位）
			local hash
			hash=$(echo -n "${normalized_name}" | md5sum | cut -c1-8)
			# 替换所有非ASCII字符为下划线
			normalized_name=$(echo "${normalized_name}" | sed 's/[^ -~]/_/g')
			# 在末尾添加哈希值
			normalized_name="${normalized_name}_${hash}"
		fi

		# 清理连续下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/__*/_/g')

		# 清理首尾下划线
		normalized_name=$(echo "${normalized_name}" | sed 's/^_//;s/_$//')

		log_info "  文件名标准化: '${original_name}' -> '${normalized_name}'"
	fi

	echo "${normalized_name}"
}

# 递归复制目录并标准化所有文件名
copy_with_normalized_names() {
	local src_dir="$1"
	local dest_dir="$2"

	# 确保目标目录存在
	mkdir -p "${dest_dir}"

	# 遍历源目录中的所有项（文件和目录）
	for item in "${src_dir}"/*; do
		if [ -e "${item}" ]; then
			local item_name=$(basename "${item}")
			local normalized_name=$(normalize_filename "${item_name}")

			# 记录文件名映射（如果与原名不同）
			if [ "${item_name}" != "${normalized_name}" ]; then
				record_path_mapping "file:${item_name}" "file:${normalized_name}"
			fi

			if [ -d "${item}" ]; then
				# 递归处理子目录
				copy_with_normalized_names "${item}" "${dest_dir}/${normalized_name}"
			else
				# 复制文件并保留软链
				# 使用 cp -a 保留软链、权限、时间戳等所有属性
				cp -a "${item}" "${dest_dir}/${normalized_name}" 2>/dev/null || true
			fi
		fi
	done
}

# 记录路径映射
# 格式: 类型|原始名称|标准化名称|原始路径|标准化路径
record_path_mapping() {
	local original_name="$1"
	local normalized_name="$2"
	local original_path="${3:-}"
	local normalized_path="${4:-}"

	if [ "${original_name}" != "${normalized_name}" ]; then
		# 记录详细映射信息
		if [ -n "${original_path}" ] && [ -n "${normalized_path}" ]; then
			echo "${original_name}|${normalized_name}|${original_path}|${normalized_path}" >>"${PATH_MAPPING_FILE}"
		else
			echo "${original_name}|${normalized_name}" >>"${PATH_MAPPING_FILE}"
		fi
		log_info "  记录映射: ${original_name} -> ${normalized_name}"
	fi
}

# 检测路径冲突
# 检查是否存在同名文件/目录冲突
detect_path_conflicts() {
	log_info "检测路径冲突..."

	local conflicts_found=0

	# 使用关联数组检测同名冲突
	declare -A seen_paths

	# 检查目标目录中的所有路径
	while IFS= read -r path; do
		local path_name=$(basename "${path}")

		if [ -n "${seen_paths[${path_name}]}" ]; then
			log_warning "  路径冲突: '${path_name}' 出现多次"
			log_warning "    - ${seen_paths[${path_name}]}"
			log_warning "    - ${path}"
			((conflicts_found++)) || true
			((STAT_WARNINGS++)) || true
		else
			seen_paths[${path_name}]="${path}"
		fi
	done < <(find "${DEST_DIR}" -mindepth 1 2>/dev/null)

	if [ ${conflicts_found} -eq 0 ]; then
		log_info "  未检测到路径冲突"
	else
		log_warning "  检测到 ${conflicts_found} 个路径冲突"
	fi
}

# 递归复制目录并标准化所有文件名和目录名
copy_dir_with_normalization() {
	local src_dir="$1"
	local dest_dir="$2"

	# 确保目标目录存在
	mkdir -p "${dest_dir}"

	# 遍历源目录中的所有项（文件和目录）
	for item in "${src_dir}"/*; do
		if [ -e "${item}" ]; then
			local item_name=$(basename "${item}")
			local normalized_name=$(normalize_filename "${item_name}")

			# 记录文件名映射（如果与原名不同）
			if [ "${item_name}" != "${normalized_name}" ]; then
				record_path_mapping "file:${item_name}" "file:${normalized_name}"
				((STAT_NORMALIZED_FILES++)) || true
			fi

			if [ -d "${item}" ]; then
				# 递归处理子目录
				copy_dir_with_normalization "${item}" "${dest_dir}/${normalized_name}"
			else
				# 复制文件并保留所有属性（包括软链）
				# 使用 cp -a 保留软链、权限、时间戳等所有属性
				# -a 等同于 -dR --preserve=all，其中 -d 表示保留软链不解引用
				if cp -a "${item}" "${dest_dir}/${normalized_name}" 2>/dev/null; then
					((STAT_COPIED_FILES++)) || true
					# 检查是否为软链并记录日志
					if [ -L "${item}" ]; then
						local link_target=$(readlink "${item}")
						log_info "  保留软链: ${item_name} -> ${link_target}"
					fi
				else
					log_error "复制失败: ${item} -> ${dest_dir}/${normalized_name}"
					((STAT_ERRORS++)) || true
				fi
			fi
		else
			# 源文件不存在（可能是断开的符号链接）
			((STAT_SKIPPED_FILES++)) || true
		fi
	done
}

# Linyaps 规范目录列表（这些目录可以直接在 files/ 下）
# 其他目录将作为非规范目录处理
declare -a Linyaps_STANDARD_DIRS=("bin" "lib" "share" "sbin" "libexec" "lib64")

# 检查目录是否为 linyaps 规范目录
is_linyaps_standard_dir() {
	local dir_name="$1"
	for std_dir in "${Linyaps_STANDARD_DIRS[@]}"; do
		if [ "${dir_name}" = "${std_dir}" ]; then
			return 0
		fi
	done
	return 1
}

# 处理 /usr/ 目录 - 同时支持传统 deb 结构和 linyaps flatpak-like 结构
process_usr_paths() {
	log_info "处理 /usr/ 目录..."

	# 优先检查 /usr/ 目录（传统 deb 包结构）
	if [ -d "${SRC_DIR}/usr" ]; then
		log_info "检测到传统 deb 包结构 (/usr/)"
		# 动态遍历 /usr/ 下的所有子目录
		for subdir in "${SRC_DIR}/usr/"*; do
			if [ -d "${subdir}" ]; then
				subdir_name=$(basename "${subdir}")

				# 排除 applications 和 icons（由其他脚本处理）
				case "${subdir_name}" in
				applications | icons)
					log_info "  跳过: /usr/${subdir_name} (由其他脚本处理)"
					;;
				*)
					log_info "  处理: /usr/${subdir_name}"
					# 标准化目录名
					local normalized_subdir=$(normalize_dirname "${subdir_name}")

					# 记录目录映射
					if [ "${subdir_name}" != "${normalized_subdir}" ]; then
						record_path_mapping "dir:${subdir_name}" "dir:${normalized_subdir}"
						((STAT_NORMALIZED_DIRS++)) || true
					fi

					# 使用标准化复制函数处理目录内容
					copy_dir_with_normalization "${subdir}" "${DEST_DIR}/${normalized_subdir}"
					((STAT_COPIED_DIRS++)) || true
					;;
				esac
			fi
		done
	else
		log_info "未找到 /usr/ 目录，检查 linyaps flatpak-like 结构..."
		# 检查是否直接存在规范目录（linyaps flatpak-like 结构）
		for subdir in "${SRC_DIR}"/*; do
			if [ -d "${subdir}" ]; then
				subdir_name=$(basename "${subdir}")

				# 只处理 linyaps 规范目录
				if is_linyaps_standard_dir "${subdir_name}"; then
					log_info "  处理规范目录 (linyaps): ${subdir_name}/"
					# 标准化目录名
					local normalized_subdir=$(normalize_dirname "${subdir_name}")

					# 记录目录映射
					if [ "${subdir_name}" != "${normalized_subdir}" ]; then
						record_path_mapping "dir:${subdir_name}" "dir:${normalized_subdir}"
						((STAT_NORMALIZED_DIRS++)) || true
					fi

					# 使用标准化复制函数处理目录内容
					copy_dir_with_normalization "${subdir}" "${DEST_DIR}/${normalized_subdir}"
					((STAT_COPIED_DIRS++)) || true
				else
					log_info "  跳过非规范目录: ${subdir_name}/ (将按非规范目录处理)"
				fi
			fi
		done
	fi
}

# 处理非标准路径（/opt、/var、/srv 等）- 动态遍历
# 同时处理 linyaps 非规范目录
process_non_standard_paths() {
	log_info "处理非标准路径..."

	# 动态遍历 SRC_DIR 下的所有顶层项（目录和文件）
	for top_item in "${SRC_DIR}"/*; do
		if [ -d "${top_item}" ]; then
			dir_name=$(basename "${top_item}")

			# 跳过 usr 目录（由 process_usr_paths 处理）
			# 跳过 linyaps 规范目录（bin, lib, share, sbin, libexec, lib64）
			# 这些目录已经在 process_usr_paths 中作为规范目录处理过了
			if is_linyaps_standard_dir "${dir_name}"; then
				log_info "  跳过规范目录: ${dir_name}/ (已在 process_usr_paths 中处理)"
				continue
			fi

			case "${dir_name}" in
			usr)
				continue
				;;
			opt | var | srv | etc)
				# FHS 规则目录：剥离前缀，展平一层
				# 例如 /opt/uTools/ → binary/uTools/
				log_info "处理 FHS 目录 /${dir_name}/ (剥离前缀，展平一层)..."
				process_non_usr_subdirs "${top_item}"
				;;
			*)
				# 非规则目录（如 app/、data/ 等）：完整复制为子目录，不展平
				# 例如 app/ → binary/app/
				log_info "处理非规则目录: ${dir_name}/ (完整复制为子目录)..."
				local normalized_dir=$(normalize_dirname "${dir_name}")

				# 记录目录映射
				if [ "${dir_name}" != "${normalized_dir}" ]; then
					record_path_mapping "dir:${dir_name}" "dir:${normalized_dir}"
					((STAT_NORMALIZED_DIRS++)) || true
				fi

				# 检查目标目录是否已存在（路径冲突检测）
				if [ -d "${DEST_DIR}/${normalized_dir}" ]; then
					log_warning "目标目录已存在，将合并内容: ${normalized_dir}"
					((STAT_WARNINGS++)) || true
				fi

				# 使用标准化复制函数将整个目录完整复制到目标
				copy_dir_with_normalization "${top_item}" "${DEST_DIR}/${normalized_dir}"
				log_info "  复制完成(非规则目录): ${dir_name}/ -> ${normalized_dir}/"
				((STAT_COPIED_DIRS++)) || true
				;;
			esac
		elif [ -e "${top_item}" ] || [ -L "${top_item}" ]; then
			# 处理顶层文件和符号链接（如 .desktop 文件、可执行文件等）
			local file_name=$(basename "${top_item}")

			# 跳过隐藏文件
			case "${file_name}" in
			.*)
				continue
				;;
			esac

			log_info "  处理顶层文件: ${file_name}"

			# 标准化文件名
			local normalized_name=$(normalize_filename "${file_name}")

			# 记录文件映射
			record_path_mapping "file:${file_name}" "file:${normalized_name}"

			# 检查目标是否已存在
			if [ -e "${DEST_DIR}/${normalized_name}" ] || [ -L "${DEST_DIR}/${normalized_name}" ]; then
				log_warning "目标文件已存在，将覆盖: ${normalized_name}"
				((STAT_WARNINGS++)) || true
			fi

			# 复制文件并保留所有属性（包括符号链接）
			if cp -a "${top_item}" "${DEST_DIR}/${normalized_name}" 2>/dev/null; then
				((STAT_COPIED_FILES++)) || true
				if [ -L "${top_item}" ]; then
					local link_target=$(readlink "${top_item}")
					log_info "  保留软链: ${file_name} -> ${link_target}"
				fi
				log_info "  复制完成(顶层文件): ${file_name} -> ${normalized_name}"
			else
				log_error "复制失败(顶层文件): ${top_item} -> ${DEST_DIR}/${normalized_name}"
				((STAT_ERRORS++)) || true
			fi
		fi
	done
}

# 处理非 /usr/ 目录的子目录和文件
process_non_usr_subdirs() {
	local parent_dir="$1"

	for subdir in "${parent_dir}"/*; do
		if [ -d "${subdir}" ]; then
			original_name=$(basename "${subdir}")

			# 检查是否包含需要处理的字符并记录日志
			if [[ "${original_name}" =~ [[:space:]] ]]; then
				log_warning "检测到空格字符: ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if [[ "${original_name}" =~ , ]]; then
				log_warning "检测到逗号字符: ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if [[ "${original_name}" =~ [()\[\]] ]]; then
				log_warning "检测到括号字符: ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			# 检查 & @ # $ 等特殊符号（使用 grep 避免 bash 正则表达式中 & 的问题）
			if echo "${original_name}" | grep -q '[&@#$]'; then
				log_warning "检测到特殊符号: ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if [[ "${original_name}" =~ ^- ]]; then
				log_warning "检测到以连字符开头的目录名: ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if [[ "${original_name}" == *[![:ascii:]]* ]]; then
				log_warning "检测到非ASCII字符(中文等): ${original_name}"
				((STAT_WARNINGS++)) || true
			fi

			log_info "  处理子目录: ${original_name}"

			# 标准化目录名
			normalized_name=$(normalize_dirname "${original_name}")

			# 记录目录映射
			record_path_mapping "dir:${original_name}" "dir:${normalized_name}"

			# 检查目标目录是否已存在（路径冲突检测）
			if [ -d "${DEST_DIR}/${normalized_name}" ]; then
				log_warning "目标目录已存在，将合并内容: ${normalized_name}"
				((STAT_WARNINGS++)) || true
			fi

			# 使用标准化复制函数处理目录内容（包括文件名）
			copy_dir_with_normalization "${subdir}" "${DEST_DIR}/${normalized_name}"

			log_info "  复制完成: ${original_name} -> ${normalized_name}"
			((STAT_COPIED_DIRS++)) || true
		elif [ -e "${subdir}" ] || [ -L "${subdir}" ]; then
			# 处理非目录项：文件、符号链接等
			original_name=$(basename "${subdir}")

			# 检查是否包含需要处理的字符并记录日志
			if [[ "${original_name}" =~ [[:space:]] ]]; then
				log_warning "检测到空格字符(文件): ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if [[ "${original_name}" =~ , ]]; then
				log_warning "检测到逗号字符(文件): ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if [[ "${original_name}" =~ [()\[\]] ]]; then
				log_warning "检测到括号字符(文件): ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if echo "${original_name}" | grep -q '[&@#$]'; then
				log_warning "检测到特殊符号(文件): ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if [[ "${original_name}" =~ ^- ]]; then
				log_warning "检测到以连字符开头的文件名: ${original_name}"
				((STAT_WARNINGS++)) || true
			fi
			if [[ "${original_name}" == *[![:ascii:]]* ]]; then
				log_warning "检测到非ASCII字符(文件): ${original_name}"
				((STAT_WARNINGS++)) || true
			fi

			log_info "  处理文件: ${original_name}"

			# 标准化文件名
			normalized_name=$(normalize_filename "${original_name}")

			# 记录文件映射
			record_path_mapping "file:${original_name}" "file:${normalized_name}"

			# 检查目标是否已存在（路径冲突检测）
			if [ -e "${DEST_DIR}/${normalized_name}" ] || [ -L "${DEST_DIR}/${normalized_name}" ]; then
				log_warning "目标文件已存在，将覆盖: ${normalized_name}"
				((STAT_WARNINGS++)) || true
			fi

			# 复制文件并保留所有属性（包括符号链接）
			if cp -a "${subdir}" "${DEST_DIR}/${normalized_name}" 2>/dev/null; then
				((STAT_COPIED_FILES++)) || true
				# 检查是否为符号链接并记录日志
				if [ -L "${subdir}" ]; then
					local link_target=$(readlink "${subdir}")
					log_info "  保留软链: ${original_name} -> ${link_target}"
				fi
				log_info "  复制完成(文件): ${original_name} -> ${normalized_name}"
			else
				log_error "复制失败(文件): ${subdir} -> ${DEST_DIR}/${normalized_name}"
				((STAT_ERRORS++)) || true
			fi
		fi
	done
}

# 检测并报告潜在问题
detect_potential_issues() {
	log_info "检测潜在问题..."

	local issues_found=0

	# 检查目录名是否包含需要特殊处理的字符
	while IFS= read -r dir; do
		dirname=$(basename "${dir}")

		# 检查空格
		if [[ "${dirname}" =~ [[:space:]] ]]; then
			log_warning "目录包含空格: ${dir}"
			((issues_found++)) || true
			((STAT_WARNINGS++)) || true
		fi

		# 检查逗号
		if [[ "${dirname}" =~ , ]]; then
			log_warning "目录包含逗号: ${dir}"
			((issues_found++)) || true
			((STAT_WARNINGS++)) || true
		fi

		# 检查连字符（以 - 开头）
		if [[ "${dirname}" =~ ^- ]]; then
			log_warning "目录以连字符开头: ${dir}"
			((issues_found++)) || true
			((STAT_WARNINGS++)) || true
		fi

		# 检查非ASCII字符（中文等）
		if [[ "${dirname}" =~ [^[:ascii:]] ]]; then
			log_warning "目录包含非ASCII字符: ${dir}"
			((issues_found++)) || true
			((STAT_WARNINGS++)) || true
		fi
	done < <(find "${DEST_DIR}" -type d 2>/dev/null)

	# 检查文件名
	while IFS= read -r file; do
		filename=$(basename "${file}")

		if [[ "${filename}" =~ [[:space:]] ]]; then
			log_warning "文件包含空格: ${file}"
			((issues_found++)) || true
			((STAT_WARNINGS++)) || true
		fi

		if [[ "${filename}" =~ , ]]; then
			log_warning "文件包含逗号: ${file}"
			((issues_found++)) || true
			((STAT_WARNINGS++)) || true
		fi

		if [[ "${filename}" =~ ^- ]]; then
			log_warning "文件以连字符开头: ${file}"
			((issues_found++)) || true
			((STAT_WARNINGS++)) || true
		fi

		if [[ "${filename}" =~ [^[:ascii:]] ]]; then
			log_warning "文件包含非ASCII字符: ${file}"
			((issues_found++)) || true
			((STAT_WARNINGS++)) || true
		fi
	done < <(find "${DEST_DIR}" -type f 2>/dev/null)

	if [ ${issues_found} -eq 0 ]; then
		log_info "未检测到潜在问题"
	else
		log_info "检测到 ${issues_found} 个潜在问题（已记录日志）"
	fi
}

# 修复软链相对路径
# 在文件复制完成后，重新计算所有软链的相对路径
fix_symlink_paths() {
	log_info "修复软链相对路径..."

	local fixed_count=0
	local broken_count=0

	# 查找所有软链
	while IFS= read -r symlink; do
		if [ -L "${symlink}" ]; then
			local link_name=$(basename "${symlink}")
			local link_dir=$(dirname "${symlink}")
			local old_target=$(readlink "${symlink}")

			# 检查软链目标是否存在（相对于软链所在目录）
			if [ ! -e "${symlink}" ]; then
				# 软链断开，尝试修复
				log_warning "  发现断开的软链: ${link_name} -> ${old_target}"

				# 尝试在 DEST_DIR 中查找目标文件
				# 1. 先尝试解析绝对路径目标
				local target_basename=$(basename "${old_target}")

				# 2. 在 DEST_DIR 中查找同名文件
				local found_target=$(find "${DEST_DIR}" -type f -name "${target_basename}" 2>/dev/null | head -n 1)

				if [ -n "${found_target}" ]; then
					# 找到目标文件，计算新的相对路径
					local rel_target=$(realpath --relative-to="${link_dir}" "${found_target}")

					# 删除旧软链
					rm -f "${symlink}"

					# 创建新软链
					ln -sf "${rel_target}" "${symlink}"

					log_success "  修复软链: ${link_name} -> ${rel_target}"
					((fixed_count++)) || true
				else
					log_warning "  无法找到目标文件: ${target_basename}"
					((broken_count++)) || true
					((STAT_WARNINGS++)) || true
				fi
			else
				# 软链正常，检查是否需要调整相对路径
				# 获取软链目标的绝对路径
				local abs_target=$(readlink -f "${symlink}")

				# 检查目标是否在 DEST_DIR 内
				if [[ "${abs_target}" == "${DEST_DIR}"* ]]; then
					# 目标在 DEST_DIR 内，检查相对路径是否正确
					local current_rel=$(readlink "${symlink}")
					local correct_rel=$(realpath --relative-to="${link_dir}" "${abs_target}")

					if [ "${current_rel}" != "${correct_rel}" ]; then
						# 相对路径不正确，修复
						rm -f "${symlink}"
						ln -sf "${correct_rel}" "${symlink}"
						log_info "  调整软链路径: ${link_name} -> ${correct_rel}"
						((fixed_count++)) || true
					fi
				fi
			fi
		fi
	done < <(find "${DEST_DIR}" -type l 2>/dev/null)

	log_info "  修复了 ${fixed_count} 个软链"
	if [ ${broken_count} -gt 0 ]; then
		log_warning "  ${broken_count} 个软链无法修复（目标文件不存在）"
	fi
}

# 验证 linyaps 目录结构
# 检查 files/ 下的关键目录结构是否符合预期
validate_linyaps_structure() {
	log_info "验证 linyaps 目录结构..."

	local validation_passed=true
	local missing_dirs=0

	# 检查关键目录是否存在（对于 linyaps 容器方案）
	# files/ 映射到 /usr/，所以关键目录应该在 files/ 下
	local key_dirs=("bin" "lib" "share")
	for dir in "${key_dirs[@]}"; do
		if [ -d "${DEST_DIR}/${dir}" ]; then
			log_info "  ✓ 目录存在: files/${dir}/"
		else
			log_warning "  ✗ 目录缺失: files/${dir}/ (可选，但推荐存在)"
			((missing_dirs++)) || true
		fi
	done

	# 检查是否有未归类的目录（非标准 /usr 子目录）
	local unclassified_dirs=()
	for item in "${DEST_DIR}"/*; do
		if [ -d "${item}" ]; then
			local item_name=$(basename "${item}")
			# 跳过标准目录和隐藏目录
			case "${item_name}" in
			bin | lib | share | etc | var | srv | opt)
				# 这些是已知的目录类型
				;;
			.*)
				# 隐藏目录（如 .path_mapping）
				;;
			*)
				# 未归类的目录
				unclassified_dirs+=("${item_name}")
				;;
			esac
		fi
	done

	if [ ${#unclassified_dirs[@]} -gt 0 ]; then
		log_info "  发现 ${#unclassified_dirs[@]} 个未归类目录（可能是 /opt、/var 等映射）:"
		for dir in "${unclassified_dirs[@]}"; do
			log_info "    - ${dir}/"
		done
	fi

	# 检查软链是否正确（如果有 bin/ 目录）
	if [ -d "${DEST_DIR}/bin" ]; then
		local symlink_count=0
		while IFS= read -r link; do
			if [ -L "${link}" ]; then
				((symlink_count++)) || true
				# 检查软链目标是否存在
				local target=$(readlink "${link}")
				if [ ! -e "${DEST_DIR}/${target}" ] && [ ! -e "${DEST_DIR}/../${target}" ]; then
					log_warning "  ✗ 软链断开: bin/${link##*/} -> ${target}"
					((STAT_WARNINGS++)) || true
				fi
			fi
		done < <(find "${DEST_DIR}/bin" -maxdepth 1 -type l 2>/dev/null)

		if [ ${symlink_count} -gt 0 ]; then
			log_info "  发现 ${symlink_count} 个软链"
		fi
	fi

	# 返回验证结果
	if [ ${missing_dirs} -gt 0 ]; then
		log_warning "目录结构验证: 发现 ${missing_dirs} 个缺失目录"
	else
		log_success "目录结构验证: 通过"
	fi
}

# 路径完整性检查
# 对比源目录和目标目录的文件统计
verify_path_integrity() {
	log_info "路径完整性检查..."

	# 统计源目录
	local src_file_count=$(find "${SRC_DIR}" -type f 2>/dev/null | wc -l)
	local src_dir_count=$(find "${SRC_DIR}" -type d 2>/dev/null | wc -l)

	# 统计目标目录（排除 .path_mapping）
	local dest_file_count=$(find "${DEST_DIR}" -type f ! -name ".path_mapping" 2>/dev/null | wc -l)
	local dest_dir_count=$(find "${DEST_DIR}" -type d 2>/dev/null | wc -l)

	log_info "  源目录: ${src_file_count} 个文件, ${src_dir_count} 个目录"
	log_info "  目标目录: ${dest_file_count} 个文件, ${dest_dir_count} 个目录"

	# 检查文件数量差异
	if [ ${src_file_count} -eq ${dest_file_count} ]; then
		log_success "  文件数量验证: 通过 (${src_file_count} == ${dest_file_count})"
	else
		local diff=$((src_file_count - dest_file_count))
		if [ ${diff} -gt 0 ]; then
			log_warning "  文件数量差异: 源目录多 ${diff} 个文件（可能是被排除的目录）"
		else
			log_warning "  文件数量差异: 目标目录多 $((-diff)) 个文件"
		fi
		((STAT_WARNINGS++)) || true
	fi

	# 检查目录数量差异
	if [ ${src_dir_count} -le ${dest_dir_count} ]; then
		log_success "  目录数量验证: 通过"
	else
		log_warning "  目录数量差异: 源目录 ${src_dir_count} 个，目标目录 ${dest_dir_count} 个"
		((STAT_WARNINGS++)) || true
	fi
}

# 打印统计报告
print_statistics() {
	log_info "========================================="
	log_info "  处理统计报告"
	log_info "========================================="
	log_info "  复制文件数: ${STAT_COPIED_FILES}"
	log_info "  复制目录数: ${STAT_COPIED_DIRS}"
	log_info "  标准化文件数: ${STAT_NORMALIZED_FILES}"
	log_info "  标准化目录数: ${STAT_NORMALIZED_DIRS}"
	log_info "  跳过文件数: ${STAT_SKIPPED_FILES}"
	log_info "  警告数: ${STAT_WARNINGS}"
	log_info "  错误数: ${STAT_ERRORS}"
	log_info "========================================="

	# 返回统计信息
	local total_dirs=$(find "${DEST_DIR}" -type d 2>/dev/null | wc -l)
	local total_files=$(find "${DEST_DIR}" -type f ! -name ".path_mapping" 2>/dev/null | wc -l)
	log_info "目标目录总计: ${total_dirs} 个目录, ${total_files} 个文件"

	# 显示路径映射文件位置
	if [ -f "${PATH_MAPPING_FILE}" ]; then
		local mapping_count=$(grep -v "^#" "${PATH_MAPPING_FILE}" | grep -c "|" 2>/dev/null) || mapping_count=0
		if [ "${mapping_count}" -gt 0 ]; then
			log_info "路径映射文件: ${PATH_MAPPING_FILE} (${mapping_count} 个映射)"
		fi
	fi
}

# 检测并剥离 tar 包的单一顶层包装目录
# 许多 tar 包解压后会产生一个顶层目录，包含所有实际内容
# 例如: binary_tmp/Postman-with-desktop-with-icons/{app/, *.desktop, Postman}
# 需要剥离 "Postman-with-desktop-with-icons/" 这一层
strip_wrapper_directory() {
	log_info "检测 tar 包包装目录..."

	# 如果存在 usr/ 目录，说明是 deb 结构，不需要剥离
	if [ -d "${SRC_DIR}/usr" ]; then
		log_info "  检测到 deb 结构 (/usr/)，跳过包装目录剥离"
		return 0
	fi

	# 如果顶层直接包含 linyaps 规范目录，说明已经是正确结构
	local has_standard_dir=false
	for std_dir in "${LINYAPS_STANDARD_DIRS[@]}"; do
		if [ -d "${SRC_DIR}/${std_dir}" ]; then
			has_standard_dir=true
			break
		fi
	done
	if [ "${has_standard_dir}" = "true" ]; then
		log_info "  检测到 linyaps 规范目录结构，跳过包装目录剥离"
		return 0
	fi

	# 统计顶层目录和文件数量
	local top_level_count=0
	local top_level_dir=""
	for item in "${SRC_DIR}"/*; do
		if [ -e "${item}" ] || [ -L "${item}" ]; then
			((top_level_count++)) || true
			if [ -d "${item}" ]; then
				top_level_dir="${item}"
			fi
		fi
	done

	# 如果只有一个顶层项且是目录，可能是包装目录
	if [ ${top_level_count} -eq 1 ] && [ -n "${top_level_dir}" ] && [ -d "${top_level_dir}" ]; then
		local wrapper_name=$(basename "${top_level_dir}")
		log_info "  检测到单一顶层包装目录: ${wrapper_name}/"

		# 检查包装目录内是否有内容
		local inner_count=0
		for item in "${top_level_dir}"/*; do
			if [ -e "${item}" ] || [ -L "${item}" ]; then
				((inner_count++)) || true
			fi
		done

		if [ ${inner_count} -eq 0 ]; then
			log_warning "  包装目录为空，跳过剥离: ${wrapper_name}/"
			return 0
		fi

		# 将 SRC_DIR 指向包装目录内部
		# 使用 mv 将内容上移一层，避免后续路径处理复杂化
		log_info "  剥离包装目录: ${wrapper_name}/ -> ${SRC_DIR}/"
		local tmp_dir="${SRC_DIR}/._strip_tmp"
		mv "${top_level_dir}" "${tmp_dir}"

		# 将内容移到 SRC_DIR 下
		for item in "${tmp_dir}"/*; do
			if [ -e "${item}" ] || [ -L "${item}" ]; then
				mv "${item}" "${SRC_DIR}/"
			fi
		done
		# 处理隐藏文件（如果有）
		for item in "${tmp_dir}"/.*; do
			local item_name=$(basename "${item}")
			if [ "${item_name}" != "." ] && [ "${item_name}" != ".." ] && ([ -e "${item}" ] || [ -L "${item}" ]); then
				mv "${item}" "${SRC_DIR}/"
			fi
		done
		rmdir "${tmp_dir}"

		log_success "  包装目录剥离完成: ${wrapper_name}/"
	else
		log_info "  未检测到单一包装目录（顶层 ${top_level_count} 项），跳过剥离"
	fi
}

# 主函数
main() {
	parse_args "$@"

	log_info "========================================="
	log_info "  特殊格式路径处理脚本"
	log_info "  (Linyaps 容器方案优化版)"
	log_info "========================================="
	log_info "源目录: ${SRC_DIR}"
	log_info "目标目录: ${DEST_DIR}"
	log_info "========================================="

	# 步骤 0: 检测并剥离 tar 包包装目录
	strip_wrapper_directory

	# 步骤 1: 处理 /usr/ 标准路径
	process_usr_paths

	# 步骤 2: 处理非标准路径（包含标准化）
	process_non_standard_paths

	# 步骤 3: 修复软链相对路径
	# 在文件复制完成后，重新计算所有软链的相对路径
	fix_symlink_paths

	# 步骤 4: 检测潜在问题
	detect_potential_issues

	# 步骤 5: 验证 linyaps 目录结构
	validate_linyaps_structure

	# 步骤 6: 路径完整性检查
	verify_path_integrity

	# 步骤 7: 检测路径冲突
	detect_path_conflicts

	# 打印统计报告
	print_statistics

	# 最终状态
	if [ ${STAT_ERRORS} -gt 0 ]; then
		log_error "路径处理完成，但有 ${STAT_ERRORS} 个错误"
		exit 1
	elif [ ${STAT_WARNINGS} -gt 0 ]; then
		log_warning "路径处理完成，但有 ${STAT_WARNINGS} 个警告"
	else
		log_success "路径处理完成，无错误"
	fi
}

# 执行主函数
main "$@"
