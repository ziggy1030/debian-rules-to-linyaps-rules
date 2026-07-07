#!/bin/bash
# validate_pak_script.sh - 驗證 pak_linyaps.sh 腳本中的 base/runtime 配置
#
# 功能：
# 1. 檢查腳本中 base_id、base_version、runtime_id、runtime_version 的定義
# 2. 檢測變量引用（如 base_id="${base_id}"）而非實際值
# 3. 檢測空值定義
# 4. 支持自動修復模式（--fix）：將變量引用替換為默認值
#
# 用法：
#   ./validate_pak_script.sh <project_dir>           # 僅檢測
#   ./validate_pak_script.sh <project_dir> --fix     # 檢測並自動修復
#
# 返回碼：
#   0 - 全部通過
#   1 - 發現錯誤（未修復）
#   2 - 已自動修復

set -uo pipefail

# 默認值
DEFAULT_BASE_ID="org.deepin.base"
DEFAULT_BASE_VERSION="25.2.2"
DEFAULT_RUNTIME_ID="org.deepin.runtime.dtk"
DEFAULT_RUNTIME_VERSION="25.2.2"

# 狀態
FIX_MODE=false
HAS_ERRORS=0
HAS_FIXES=0

# 顏色輸出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_error() {
	echo -e "${RED}錯誤:${NC} $1" >&2
}

print_warning() {
	echo -e "${YELLOW}警告:${NC} $1" >&2
}

print_success() {
	echo -e "${GREEN}通過:${NC} $1"
}

print_fix() {
	echo -e "${GREEN}修復:${NC} $1"
}

usage() {
	cat <<EOF
用法: $0 <project_dir> [--fix]

驗證 pak_linyaps.sh 腳本中的 base/runtime 配置

參數:
  <project_dir>  工程目錄路徑（如 CI_ll_com.example.app）
  --fix          自動修復檢測到的問題

檢查項:
  1. base_id、base_version、runtime_id、runtime_version 是否定義
  2. 值是否為實際值（非變量引用）
  3. 值是否為空
  4. ID 格式是否符合反向域名規範
  5. Version 格式是否為 X.Y.Z 或 X.Y.Z.W

返回碼:
  0 - 全部通過
  1 - 發現錯誤（未修復）
  2 - 已自動修復
EOF
	exit 0
}

# 解析參數
PROJECT_DIR=""

for arg in "$@"; do
	case "${arg}" in
	--fix)
		FIX_MODE=true
		;;
	-h | --help)
		usage
		;;
	*)
		if [ -z "${PROJECT_DIR}" ]; then
			PROJECT_DIR="${arg}"
		else
			echo "未知參數: ${arg}" >&2
			usage
		fi
		;;
	esac
done

if [ -z "${PROJECT_DIR}" ]; then
	echo "錯誤: 請指定工程目錄路徑" >&2
	usage
fi

# 查找 pak_linyaps.sh
SCRIPT_FILE=""
if [ -f "${PROJECT_DIR}/pak_linyaps.sh" ]; then
	SCRIPT_FILE="${PROJECT_DIR}/pak_linyaps.sh"
elif [ -f "${PROJECT_DIR}/templates/pak_linyaps.sh" ]; then
	SCRIPT_FILE="${PROJECT_DIR}/templates/pak_linyaps.sh"
else
	echo "錯誤: 在 ${PROJECT_DIR} 中找不到 pak_linyaps.sh" >&2
	exit 1
fi

echo "========================================"
echo "pak_linyaps.sh 腳本驗證"
echo "========================================"
echo "腳本路徑: ${SCRIPT_FILE}"
echo "修復模式: ${FIX_MODE}"
echo ""

# 檢查變量定義是否為變量引用
# 模式：var_name="${var_name}" 或 var_name='$var_name' 或 var_name=$var_name
check_variable_reference() {
	local var_name="$1"
	local expected_default="$2"
	local line_content

	# 查找變量定義行（排除注釋行和 case 內部的引用）
	# 只檢查頂部定義和 DEFAULT_ 前綴的定義
	line_content=$(grep -n "^[[:space:]]*${var_name}=" "${SCRIPT_FILE}" 2>/dev/null | head -1 || true)

	if [ -z "${line_content}" ]; then
		print_error "${var_name} 未在腳本中定義"
		HAS_ERRORS=1

		if [ "${FIX_MODE}" = true ]; then
			# 在 ll_id 行之後插入定義
			local insert_line
			insert_line=$(grep -n "^ll_id=" "${SCRIPT_FILE}" | tail -1 | cut -d: -f1)
			if [ -n "${insert_line}" ]; then
				sed -i "${insert_line}a\\${var_name}=\"${expected_default}\"" "${SCRIPT_FILE}"
				print_fix "已在第 $((insert_line + 1)) 行添加 ${var_name}=\"${expected_default}\""
				HAS_FIXES=1
			fi
		fi
		return 1
	fi

	local line_num
	line_num=$(echo "${line_content}" | cut -d: -f1)
	local line_val
	line_val=$(echo "${line_content}" | cut -d= -f2- | sed 's/^"//;s/"$//')

	# 檢查是否為變量引用模式
	# 模式1: ${var_name} - 自引用
	# 模式2: $var_name - 自引用
	# 模式3: ${DEFAULT_var_name} - 引用默認值（正確）
	if [[ "${line_val}" =~ ^\$\{?${var_name}\}?$ ]]; then
		print_error "第 ${line_num} 行: ${var_name}='${line_val}' 是變量自引用，實際值為空！"
		echo "  這是 LLM 生成時的常見錯誤，變量自引用不會產生任何值。" >&2
		echo "  正確寫法: ${var_name}=\"${expected_default}\"" >&2
		HAS_ERRORS=1

		if [ "${FIX_MODE}" = true ]; then
			# 使用行號精確替換，避免 sed 對 ${} 的特殊處理問題
			sed -i "${line_num}c\\${var_name}=\"${expected_default}\"" "${SCRIPT_FILE}"
			print_fix "已將第 ${line_num} 行修復為 ${var_name}=\"${expected_default}\""
			HAS_FIXES=1
		fi
		return 1
	fi

	# 檢查是否引用了 DEFAULT_ 前綴變量（正確模式）
	if [[ "${line_val}" =~ ^\$\{?DEFAULT_${var_name}\}?$ ]]; then
		print_success "${var_name}='${line_val}' (引用默認值定義，正確)"
		# 驗證 DEFAULT_ 變量是否存在
		local default_line
		default_line=$(grep -n "^[[:space:]]*DEFAULT_${var_name}=" "${SCRIPT_FILE}" 2>/dev/null | head -1 || true)
		if [ -z "${default_line}" ]; then
			print_warning "DEFAULT_${var_name} 未定義，${var_name} 的值可能為空"
		fi
		return 0
	fi

	# 檢查值是否為空
	if [ -z "${line_val}" ]; then
		print_error "第 ${line_num} 行: ${var_name} 的值為空"
		HAS_ERRORS=1

		if [ "${FIX_MODE}" = true ]; then
			sed -i "${line_num}c\\${var_name}=\"${expected_default}\"" "${SCRIPT_FILE}"
			print_fix "已將第 ${line_num} 行修復為 ${var_name}=\"${expected_default}\""
			HAS_FIXES=1
		fi
		return 1
	fi

	# 檢查是否為其他變量引用（非自引用，但也非實際值）
	if [[ "${line_val}" =~ ^\$\{?[a-zA-Z_][a-zA-Z0-9_]*\}?$ ]]; then
		print_warning "第 ${line_num} 行: ${var_name}='${line_val}' 是變量引用，請確認引用的變量已正確定義"
		# 變量引用不一定是錯誤，僅警告
		return 0
	fi

	# 值是實際值，進一步驗證格式
	if [[ "${var_name}" == *_id ]]; then
		# ID 格式驗證：反向域名格式
		if [[ ! "${line_val}" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$ ]]; then
			print_warning "${var_name}='${line_val}' 格式可能不正確（期望反向域名格式如 org.deepin.base）"
		else
			print_success "${var_name}='${line_val}' (格式正確)"
		fi
	elif [[ "${var_name}" == *_version ]]; then
		# Version 格式驗證
		if [[ ! "${line_val}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
			print_error "第 ${line_num} 行: ${var_name}='${line_val}' 版本格式不正確（期望 X.Y.Z 或 X.Y.Z.W）"
			HAS_ERRORS=1
		else
			print_success "${var_name}='${line_val}' (格式正確)"
		fi
	fi

	return 0
}

# 檢查 case 語句中是否有多餘的自引用賦值
check_case_self_reference() {
	echo ""
	echo "--- 檢查 case 語句中的自引用賦值 ---"

	# 查找 case 塊中的自引用賦值
	# 模式：base_id="${base_id}" 等
	local self_ref_lines
	self_ref_lines=$(grep -n 'base_id="\${base_id}"\|base_version="\${base_version}"\|runtime_id="\${runtime_id}"\|runtime_version="\${runtime_version}"' "${SCRIPT_FILE}" 2>/dev/null || true)

	if [ -n "${self_ref_lines}" ]; then
		print_warning "case 語句中發現自引用賦值（無實際作用，建議移除）："
		echo "${self_ref_lines}" | while IFS= read -r line; do
			echo "  ${line}"
		done

		if [ "${FIX_MODE}" = true ]; then
			# 移除 case 塊中的自引用賦值行
			sed -i '/base_id="\${base_id}"/d' "${SCRIPT_FILE}"
			sed -i '/base_version="\${base_version}"/d' "${SCRIPT_FILE}"
			sed -i '/runtime_id="\${runtime_id}"/d' "${SCRIPT_FILE}"
			sed -i '/runtime_version="\${runtime_version}"/d' "${SCRIPT_FILE}"
			print_fix "已移除 case 語句中的自引用賦值行"
			HAS_FIXES=1
		fi
	else
		print_success "case 語句中無自引用賦值"
	fi
}

# 檢查 DEFAULT_ 變量定義
check_default_variables() {
	echo ""
	echo "--- 檢查默認值定義 ---"

	local defaults=(
		"DEFAULT_BASE_ID:${DEFAULT_BASE_ID}"
		"DEFAULT_BASE_VERSION:${DEFAULT_BASE_VERSION}"
		"DEFAULT_RUNTIME_ID:${DEFAULT_RUNTIME_ID}"
		"DEFAULT_RUNTIME_VERSION:${DEFAULT_RUNTIME_VERSION}"
	)

	for default_def in "${defaults[@]}"; do
		IFS=':' read -r var_name expected_val <<<"${default_def}"

		local line_content
		line_content=$(grep -n "^[[:space:]]*${var_name}=" "${SCRIPT_FILE}" 2>/dev/null | head -1 || true)

		if [ -z "${line_content}" ]; then
			print_warning "${var_name} 未定義（建議添加以支持命令行參數覆蓋）"

			if [ "${FIX_MODE}" = true ]; then
				# 在 ll_id 行之後插入默認值定義
				local insert_line
				insert_line=$(grep -n "^ll_id=" "${SCRIPT_FILE}" | tail -1 | cut -d: -f1)
				if [ -n "${insert_line}" ]; then
					sed -i "${insert_line}a\\${var_name}=\"${expected_val}\"" "${SCRIPT_FILE}"
					print_fix "已添加 ${var_name}=\"${expected_val}\""
					HAS_FIXES=1
				fi
			fi
		else
			local line_val
			line_val=$(echo "${line_content}" | cut -d= -f2- | sed 's/^"//;s/"$//')
			print_success "${var_name}='${line_val}'"
		fi
	done
}

# 檢查命令行參數支持
check_cli_params() {
	echo ""
	echo "--- 檢查命令行參數支持 ---"

	local params=(
		"--base_id"
		"--base_version"
		"--runtime_id"
		"--runtime_version"
	)

	for param in "${params[@]}"; do
		local var_name
		var_name=$(echo "${param}" | sed 's/^--//')

		if grep -q "${param})" "${SCRIPT_FILE}" 2>/dev/null; then
			print_success "命令行參數 ${param} 已支持"
		else
			print_warning "命令行參數 ${param} 未支持（建議添加以支持運行時覆蓋）"

			if [ "${FIX_MODE}" = true ]; then
				# 在 --build_tmp_dir) 之後添加參數解析
				local insert_line
				insert_line=$(grep -n "\-\-build_tmp_dir)" "${SCRIPT_FILE}" | tail -1 | cut -d: -f1)
				if [ -n "${insert_line}" ]; then
					local next_line=$((insert_line + 2)) # 跳過賦值行
					sed -i "${next_line}a\\		${param})\n\t\t\t${var_name}=\"\$val\"\n\t\t\t;;" "${SCRIPT_FILE}"
					print_fix "已添加 ${param} 參數解析"
					HAS_FIXES=1
				fi
			fi
		fi
	done
}

# 檢查 validate_base_runtime 函數
check_validate_function() {
	echo ""
	echo "--- 檢查驗證函數 ---"

	if grep -q "validate_base_runtime" "${SCRIPT_FILE}" 2>/dev/null; then
		print_success "validate_base_runtime() 函數已存在"
	else
		print_warning "validate_base_runtime() 函數未定義（建議添加以支持運行時驗證）"
	fi

	# 檢查是否在 init_global_data 中調用
	if grep -A5 "esac" "${SCRIPT_FILE}" | grep -q "validate_base_runtime"; then
		print_success "validate_base_runtime 在 init_global_data() 末尾被調用"
	else
		print_warning "validate_base_runtime 未在 init_global_data() 末尾調用"
	fi

	# 檢查白名單驗證函數
	if grep -q "validate_base_runtime_whitelist" "${SCRIPT_FILE}" 2>/dev/null; then
		print_success "validate_base_runtime_whitelist() 白名單驗證函數已存在"
	else
		print_warning "validate_base_runtime_whitelist() 白名單驗證函數未定義（建議添加以支持白名單校驗）"
	fi
}

# 白名單驗證
check_whitelist() {
	echo ""
	echo "--- 白名單驗證 ---"

	local whitelist_file=""

	# 按優先級查找白名單配置文件
	if [ -n "${LINGLONG_WHITELIST_FILE:-}" ] && [ -f "${LINGLONG_WHITELIST_FILE}" ]; then
		whitelist_file="${LINGLONG_WHITELIST_FILE}"
	elif [ -f "${PROJECT_DIR}/config/base_runtime_whitelist.conf" ]; then
		whitelist_file="${PROJECT_DIR}/config/base_runtime_whitelist.conf"
	else
		local script_dir
		script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
		if [ -f "${script_dir}/../config/base_runtime_whitelist.conf" ]; then
			whitelist_file="${script_dir}/../config/base_runtime_whitelist.conf"
		fi
	fi

	if [ -z "${whitelist_file}" ]; then
		print_warning "未找到白名單配置文件，跳過白名單驗證"
		print_warning "可通過環境變量 LINGLONG_WHITELIST_FILE 指定白名單路徑"
		return 0
	fi

	if [ ! -r "${whitelist_file}" ]; then
		print_error "白名單配置文件不可讀: ${whitelist_file}"
		HAS_ERRORS=1
		return 1
	fi

	echo "白名單文件: ${whitelist_file}"

	# 從腳本中提取 base_id、base_version、runtime_id、runtime_version 的實際值
	local script_base_id="" script_base_version="" script_runtime_id="" script_runtime_version=""

	# 提取頂部變量定義（排除 DEFAULT_ 前綴和 case 內部的賦值）
	script_base_id=$(grep -E "^[[:space:]]*base_id=" "${SCRIPT_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)
	script_base_version=$(grep -E "^[[:space:]]*base_version=" "${SCRIPT_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)
	script_runtime_id=$(grep -E "^[[:space:]]*runtime_id=" "${SCRIPT_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)
	script_runtime_version=$(grep -E "^[[:space:]]*runtime_version=" "${SCRIPT_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)

	# 跳過變量引用
	if [[ "${script_base_id}" =~ ^\$\{?DEFAULT_ ]] && [[ "${script_base_version}" =~ ^\$\{?DEFAULT_ ]]; then
		# 引用 DEFAULT_ 變量，提取 DEFAULT_ 值
		script_base_id=$(grep -E "^[[:space:]]*DEFAULT_BASE_ID=" "${SCRIPT_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)
		script_base_version=$(grep -E "^[[:space:]]*DEFAULT_BASE_VERSION=" "${SCRIPT_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)
		script_runtime_id=$(grep -E "^[[:space:]]*DEFAULT_RUNTIME_ID=" "${SCRIPT_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)
		script_runtime_version=$(grep -E "^[[:space:]]*DEFAULT_RUNTIME_VERSION=" "${SCRIPT_FILE}" 2>/dev/null | head -1 | cut -d= -f2- | sed 's/^"//;s/"$//' || true)
	fi

	# 跳過無法解析的值
	if [[ "${script_base_id}" =~ ^\$\{?[a-zA-Z_] ]] || [ -z "${script_base_id}" ]; then
		print_warning "base_id 值為變量引用或為空，跳過白名單驗證"
		return 0
	fi

	# 在白名單中查找
	local found=0
	local matched_desc=""

	while IFS= read -r line || [ -n "${line}" ]; do
		[[ "${line}" =~ ^[[:space:]]*# ]] && continue
		[[ "${line}" =~ ^[[:space:]]*$ ]] && continue

		local wl_base wl_runtime wl_desc
		read -r wl_base wl_runtime wl_desc <<<"${line}"

		if [ "${wl_base}" = "${script_base_id}/${script_base_version}" ]; then
			if [ "${wl_runtime}" = "${script_runtime_id}/${script_runtime_version}" ]; then
				found=1
				matched_desc="${wl_desc}"
				break
			fi
			if [ "${wl_runtime}" = "-" ] && [ -z "${script_runtime_id}" ]; then
				found=1
				matched_desc="${wl_desc}"
				break
			fi
		fi
	done <"${whitelist_file}"

	if [ "${found}" -eq 1 ]; then
		print_success "base/runtime 組合在白名單中: ${script_base_id}/${script_base_version} + ${script_runtime_id}/${script_runtime_version} (${matched_desc})"
	else
		print_warning "base/runtime 組合不在白名單中: ${script_base_id}/${script_base_version} + ${script_runtime_id}/${script_runtime_version}"
		echo "  白名單中可用的組合：" >&2
		while IFS= read -r line || [ -n "${line}" ]; do
			[[ "${line}" =~ ^[[:space:]]*# ]] && continue
			[[ "${line}" =~ ^[[:space:]]*$ ]] && continue
			local wl_base wl_runtime wl_desc
			read -r wl_base wl_runtime wl_desc <<<"${line}"
			echo "    ${wl_base} + ${wl_runtime}  # ${wl_desc}" >&2
		done <"${whitelist_file}"
	fi
}

# 執行所有檢查
echo "--- 檢查變量定義 ---"
check_variable_reference "base_id" "${DEFAULT_BASE_ID}"
check_variable_reference "base_version" "${DEFAULT_BASE_VERSION}"
check_variable_reference "runtime_id" "${DEFAULT_RUNTIME_ID}"
check_variable_reference "runtime_version" "${DEFAULT_RUNTIME_VERSION}"

check_case_self_reference
check_default_variables
check_cli_params
check_validate_function
check_whitelist

# 輸出結果
echo ""
echo "========================================"
if [ "${HAS_ERRORS}" -eq 0 ]; then
	echo "驗證結果: 全部通過 ✓"
	exit 0
elif [ "${HAS_FIXES}" -gt 0 ] && [ "${FIX_MODE}" = true ]; then
	echo "驗證結果: 已自動修復 ${HAS_FIXES} 個問題"
	exit 2
else
	echo "驗證結果: 發現錯誤，請修復後重新驗證"
	echo "提示: 使用 --fix 參數可自動修復部分問題"
	exit 1
fi
