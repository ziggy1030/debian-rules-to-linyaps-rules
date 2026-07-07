#!/bin/bash
# validate_base_runtime.sh - 統一的 base/runtime 配置驗證腳本
#
# 功能：
# 1. 檢查 linglong.yaml 中的 base 和 runtime 字段
# 2. 檢查 pak_linyaps.sh 中的變量定義
# 3. 支持修復模式（--fix）
# 4. 返回標準化錯誤碼
#
# 用法：
#   ./validate_base_runtime.sh <project_dir>           # 僅檢測
#   ./validate_base_runtime.sh <project_dir> --fix     # 檢測並自動修復
#
# 返回碼：
#   0 - 全部通過
#   1 - 發現錯誤（未修復）
#   2 - 已自動修復

set -euo pipefail

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
BLUE='\033[0;34m'
NC='\033[0m'

print_error() {
	echo -e "${RED}✗ 錯誤:${NC} $1" >&2
}

print_warning() {
	echo -e "${YELLOW}⚠ 警告:${NC} $1"
}

print_success() {
	echo -e "${GREEN}✓ 通過:${NC} $1"
}

print_fix() {
	echo -e "${BLUE}↻ 修復:${NC} $1"
}

print_section() {
	echo ""
	echo -e "${BLUE}--- $1 ---${NC}"
}

usage() {
	cat <<EOF
用法: $0 <project_dir> [--fix]

統一驗證玲瓏工程的 base/runtime 配置

參數:
  <project_dir>  工程目錄路徑（如 CI_ll_com.example.app）
  --fix          自動修復檢測到的問題

檢查範圍:
  1. linglong.yaml 中的 base/runtime 字段格式和值
  2. pak_linyaps.sh 中的變量定義和引用

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

echo "========================================"
echo "玲瓏工程 base/runtime 統一驗證"
echo "========================================"
echo "工程目錄: ${PROJECT_DIR}"
echo "修復模式: ${FIX_MODE}"
echo ""

# ==========================================
# Part 1: 驗證 linglong.yaml
# ==========================================
validate_yaml() {
	print_section "驗證 linglong.yaml"

	local yaml_file=""
	if [ -f "${PROJECT_DIR}/linglong.yaml" ]; then
		yaml_file="${PROJECT_DIR}/linglong.yaml"
	elif [ -f "${PROJECT_DIR}/templates/linglong.yaml" ]; then
		yaml_file="${PROJECT_DIR}/templates/linglong.yaml"
	else
		print_warning "找不到 linglong.yaml，跳過 YAML 驗證"
		return 0
	fi

	echo "YAML 文件: ${yaml_file}"

	# 檢查 base 字段
	local base_value
	base_value=$(grep "^base:" "${yaml_file}" 2>/dev/null | sed 's/^base:[[:space:]]*//' || true)

	if [ -z "${base_value}" ]; then
		print_error "base 字段缺失或為空"
		HAS_ERRORS=1

		if [ "${FIX_MODE}" = true ]; then
			sed -i "s|^base:.*|base: ${DEFAULT_BASE_ID}/${DEFAULT_BASE_VERSION}|" "${yaml_file}" 2>/dev/null ||
				echo "base: ${DEFAULT_BASE_ID}/${DEFAULT_BASE_VERSION}" >>"${yaml_file}"
			print_fix "已設置 base: ${DEFAULT_BASE_ID}/${DEFAULT_BASE_VERSION}"
			HAS_FIXES=1
		fi
	elif [[ "${base_value}" =~ ^\$\{?[a-zA-Z_] ]]; then
		print_error "base 字段包含未替換的變量引用: '${base_value}'"
		echo "  這表示 envsubst 替換失敗，變量值可能為空" >&2
		HAS_ERRORS=1

		if [ "${FIX_MODE}" = true ]; then
			sed -i "s|^base:.*|base: ${DEFAULT_BASE_ID}/${DEFAULT_BASE_VERSION}|" "${yaml_file}"
			print_fix "已將 base 修復為: ${DEFAULT_BASE_ID}/${DEFAULT_BASE_VERSION}"
			HAS_FIXES=1
		fi
	elif [[ "${base_value}" == "/" ]]; then
		print_error "base 字段值為 '/'（變量替換後 ID 和版本都為空）"
		HAS_ERRORS=1

		if [ "${FIX_MODE}" = true ]; then
			sed -i "s|^base:.*|base: ${DEFAULT_BASE_ID}/${DEFAULT_BASE_VERSION}|" "${yaml_file}"
			print_fix "已將 base 修復為: ${DEFAULT_BASE_ID}/${DEFAULT_BASE_VERSION}"
			HAS_FIXES=1
		fi
	else
		# 驗證格式
		if [[ "${base_value}" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+\/[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
			print_success "base: ${base_value} (格式正確)"
		else
			print_warning "base: ${base_value} (格式可能不正確，期望 org.xxx.xxx/X.Y.Z)"
		fi
	fi

	# 檢查 runtime 字段
	local runtime_value
	runtime_value=$(grep "^runtime:" "${yaml_file}" 2>/dev/null | sed 's/^runtime:[[:space:]]*//' || true)

	if [ -z "${runtime_value}" ]; then
		print_warning "runtime 字段缺失或為空（部分應用可能不需要 runtime）"

		if [ "${FIX_MODE}" = true ]; then
			# runtime 不是必須的，但如果存在且為空則修復
			if grep -q "^runtime:" "${yaml_file}"; then
				sed -i "s|^runtime:.*|runtime: ${DEFAULT_RUNTIME_ID}/${DEFAULT_RUNTIME_VERSION}|" "${yaml_file}"
				print_fix "已設置 runtime: ${DEFAULT_RUNTIME_ID}/${DEFAULT_RUNTIME_VERSION}"
				HAS_FIXES=1
			fi
		fi
	elif [[ "${runtime_value}" =~ ^\$\{?[a-zA-Z_] ]]; then
		print_error "runtime 字段包含未替換的變量引用: '${runtime_value}'"
		HAS_ERRORS=1

		if [ "${FIX_MODE}" = true ]; then
			sed -i "s|^runtime:.*|runtime: ${DEFAULT_RUNTIME_ID}/${DEFAULT_RUNTIME_VERSION}|" "${yaml_file}"
			print_fix "已將 runtime 修復為: ${DEFAULT_RUNTIME_ID}/${DEFAULT_RUNTIME_VERSION}"
			HAS_FIXES=1
		fi
	elif [[ "${runtime_value}" == "/" ]]; then
		print_error "runtime 字段值為 '/'（變量替換後 ID 和版本都為空）"
		HAS_ERRORS=1

		if [ "${FIX_MODE}" = true ]; then
			sed -i "s|^runtime:.*|runtime: ${DEFAULT_RUNTIME_ID}/${DEFAULT_RUNTIME_VERSION}|" "${yaml_file}"
			print_fix "已將 runtime 修復為: ${DEFAULT_RUNTIME_ID}/${DEFAULT_RUNTIME_VERSION}"
			HAS_FIXES=1
		fi
	else
		# 驗證格式
		if [[ "${runtime_value}" =~ ^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+\/[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
			print_success "runtime: ${runtime_value} (格式正確)"
		else
			print_warning "runtime: ${runtime_value} (格式可能不正確，期望 org.xxx.xxx/X.Y.Z)"
		fi
	fi
}

# ==========================================
# Part 2: 驗證 pak_linyaps.sh
# ==========================================
validate_script() {
	print_section "驗證 pak_linyaps.sh"

	local script_file=""
	if [ -f "${PROJECT_DIR}/pak_linyaps.sh" ]; then
		script_file="${PROJECT_DIR}/pak_linyaps.sh"
	elif [ -f "${PROJECT_DIR}/templates/pak_linyaps.sh" ]; then
		script_file="${PROJECT_DIR}/templates/pak_linyaps.sh"
	else
		print_warning "找不到 pak_linyaps.sh，跳過腳本驗證"
		return 0
	fi

	echo "腳本文件: ${script_file}"

	# 檢查變量定義
	local var_defs=(
		"base_id:${DEFAULT_BASE_ID}"
		"base_version:${DEFAULT_BASE_VERSION}"
		"runtime_id:${DEFAULT_RUNTIME_ID}"
		"runtime_version:${DEFAULT_RUNTIME_VERSION}"
	)

	for var_def in "${var_defs[@]}"; do
		IFS=':' read -r var_name expected_val <<<"${var_def}"

		# 查找頂部變量定義（排除注釋行和 case 內部）
		local line_content
		line_content=$(grep -n "^[[:space:]]*${var_name}=" "${script_file}" 2>/dev/null | head -1 || true)

		if [ -z "${line_content}" ]; then
			print_error "${var_name} 未在腳本中定義"
			HAS_ERRORS=1

			if [ "${FIX_MODE}" = true ]; then
				local insert_line
				insert_line=$(grep -n "^ll_id=" "${script_file}" | tail -1 | cut -d: -f1)
				if [ -n "${insert_line}" ]; then
					sed -i "${insert_line}a\\${var_name}=\"${expected_val}\"" "${script_file}"
					print_fix "已添加 ${var_name}=\"${expected_val}\""
					HAS_FIXES=1
				fi
			fi
			continue
		fi

		local line_num
		line_num=$(echo "${line_content}" | cut -d: -f1)
		local line_val
		line_val=$(echo "${line_content}" | cut -d= -f2- | sed 's/^"//;s/"$//')

		# 檢查變量自引用
		if [[ "${line_val}" =~ ^\$\{?${var_name}\}?$ ]]; then
			print_error "第 ${line_num} 行: ${var_name}='${line_val}' 是變量自引用（值為空）"
			HAS_ERRORS=1

			if [ "${FIX_MODE}" = true ]; then
				sed -i "${line_num}s|${var_name}=.*|${var_name}=\"${expected_val}\"|" "${script_file}"
				print_fix "已修復為 ${var_name}=\"${expected_val}\""
				HAS_FIXES=1
			fi
			continue
		fi

		# 檢查空值
		if [ -z "${line_val}" ]; then
			print_error "第 ${line_num} 行: ${var_name} 值為空"
			HAS_ERRORS=1

			if [ "${FIX_MODE}" = true ]; then
				sed -i "${line_num}s|${var_name}=.*|${var_name}=\"${expected_val}\"|" "${script_file}"
				print_fix "已修復為 ${var_name}=\"${expected_val}\""
				HAS_FIXES=1
			fi
			continue
		fi

		# 檢查 DEFAULT_ 引用（正確模式）
		if [[ "${line_val}" =~ ^\$\{?DEFAULT_${var_name}\}?$ ]]; then
			print_success "${var_name}='${line_val}' (引用默認值)"
			continue
		fi

		# 值為實際值
		print_success "${var_name}='${line_val}'"
	done

	# 檢查 case 中的自引用賦值
	local self_ref_count
	self_ref_count=$(grep -c 'base_id="\${base_id}"\|base_version="\${base_version}"\|runtime_id="\${runtime_id}"\|runtime_version="\${runtime_version}"' "${script_file}" 2>/dev/null || echo "0")

	if [ "${self_ref_count}" -gt 0 ]; then
		print_warning "case 語句中發現 ${self_ref_count} 處自引用賦值（無實際作用）"

		if [ "${FIX_MODE}" = true ]; then
			sed -i '/base_id="\${base_id}"/d' "${script_file}"
			sed -i '/base_version="\${base_version}"/d' "${script_file}"
			sed -i '/runtime_id="\${runtime_id}"/d' "${script_file}"
			sed -i '/runtime_version="\${runtime_version}"/d' "${script_file}"
			print_fix "已移除 case 語句中的自引用賦值"
			HAS_FIXES=1
		fi
	fi

	# 檢查 validate_base_runtime 函數
	if grep -q "validate_base_runtime" "${script_file}" 2>/dev/null; then
		print_success "validate_base_runtime() 函數已存在"
	else
		print_warning "validate_base_runtime() 函數未定義（建議添加運行時驗證）"
	fi
}

# ==========================================
# Part 3: 交叉驗證（YAML 和腳本一致性）
# ==========================================
cross_validate() {
	print_section "交叉驗證"

	local yaml_file=""
	if [ -f "${PROJECT_DIR}/linglong.yaml" ]; then
		yaml_file="${PROJECT_DIR}/linglong.yaml"
	elif [ -f "${PROJECT_DIR}/templates/linglong.yaml" ]; then
		yaml_file="${PROJECT_DIR}/templates/linglong.yaml"
	fi

	local script_file=""
	if [ -f "${PROJECT_DIR}/pak_linyaps.sh" ]; then
		script_file="${PROJECT_DIR}/pak_linyaps.sh"
	elif [ -f "${PROJECT_DIR}/templates/pak_linyaps.sh" ]; then
		script_file="${PROJECT_DIR}/templates/pak_linyaps.sh"
	fi

	if [ -z "${yaml_file}" ] || [ -z "${script_file}" ]; then
		print_warning "缺少 YAML 或腳本文件，跳過交叉驗證"
		return 0
	fi

	# 檢查 YAML 中的 base/runtime 是否使用 envsubst 變量
	local base_value
	base_value=$(grep "^base:" "${yaml_file}" 2>/dev/null | sed 's/^base:[[:space:]]*//' || true)

	if [[ "${base_value}" =~ \$\{base_id\} ]]; then
		# YAML 使用變量替換，檢查腳本中是否有對應的 export
		if grep -q "export base_id=" "${script_file}" 2>/dev/null; then
			print_success "YAML base 變量與腳本 export 匹配"
		else
			print_error "YAML 使用 \${base_id} 變量，但腳本中缺少 'export base_id=' 語句"
			HAS_ERRORS=1
		fi
	fi

	local runtime_value
	runtime_value=$(grep "^runtime:" "${yaml_file}" 2>/dev/null | sed 's/^runtime:[[:space:]]*//' || true)

	if [[ "${runtime_value}" =~ \$\{runtime_id\} ]]; then
		if grep -q "export runtime_id=" "${script_file}" 2>/dev/null; then
			print_success "YAML runtime 變量與腳本 export 匹配"
		else
			print_error "YAML 使用 \${runtime_id} 變量，但腳本中缺少 'export runtime_id=' 語句"
			HAS_ERRORS=1
		fi
	fi
}

# ==========================================
# Part 4: 白名單驗證
# ==========================================
validate_whitelist() {
	print_section "白名單驗證"

	local whitelist_file=""

	# 按優先級查找白名單配置文件：
	# 1. 環境變量指定的路徑
	# 2. 工程目錄下的 config/base_runtime_whitelist.conf
	# 3. 腳本所在目錄的 config/base_runtime_whitelist.conf
	if [ -n "${LINGLONG_WHITELIST_FILE:-}" ] && [ -f "${LINGLONG_WHITELIST_FILE}" ]; then
		whitelist_file="${LINGLONG_WHITELIST_FILE}"
	elif [ -f "${PROJECT_DIR}/config/base_runtime_whitelist.conf" ]; then
		whitelist_file="${PROJECT_DIR}/config/base_runtime_whitelist.conf"
	else
		# 嘗試相對於腳本目錄查找
		local script_dir
		script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
		if [ -f "${script_dir}/../config/base_runtime_whitelist.conf" ]; then
			whitelist_file="${script_dir}/../config/base_runtime_whitelist.conf"
		fi
	fi

	# 白名單文件不存在時跳過驗證
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

	# 從 linglong.yaml 提取 base 和 runtime 值
	local yaml_file=""
	if [ -f "${PROJECT_DIR}/linglong.yaml" ]; then
		yaml_file="${PROJECT_DIR}/linglong.yaml"
	elif [ -f "${PROJECT_DIR}/templates/linglong.yaml" ]; then
		yaml_file="${PROJECT_DIR}/templates/linglong.yaml"
	fi

	if [ -z "${yaml_file}" ]; then
		print_warning "找不到 linglong.yaml，跳過白名單驗證"
		return 0
	fi

	# 提取 base 和 runtime 值
	local base_value runtime_value
	base_value=$(grep "^base:" "${yaml_file}" 2>/dev/null | sed 's/^base:[[:space:]]*//' || true)
	runtime_value=$(grep "^runtime:" "${yaml_file}" 2>/dev/null | sed 's/^runtime:[[:space:]]*//' || true)

	# 跳過變量引用（envsubst 未替換的情況）
	if [[ "${base_value}" =~ ^\$\{?[a-zA-Z_] ]]; then
		print_warning "base 值為變量引用 '${base_value}'，跳過白名單驗證（需先完成變量替換）"
		return 0
	fi

	# 解析 base_id/base_version 和 runtime_id/runtime_version
	local base_id="" base_version="" runtime_id="" runtime_version=""

	if [[ "${base_value}" =~ ^(.+)/(.+)$ ]]; then
		base_id="${BASH_REMATCH[1]}"
		base_version="${BASH_REMATCH[2]}"
	fi

	if [ -n "${runtime_value}" ] && [[ "${runtime_value}" =~ ^(.+)/(.+)$ ]]; then
		runtime_id="${BASH_REMATCH[1]}"
		runtime_version="${BASH_REMATCH[2]}"
	fi

	# 在白名單中查找
	local found=0
	local matched_desc=""

	while IFS= read -r line || [ -n "${line}" ]; do
		# 跳過注釋和空行
		[[ "${line}" =~ ^[[:space:]]*# ]] && continue
		[[ "${line}" =~ ^[[:space:]]*$ ]] && continue

		# 提取字段
		local wl_base wl_runtime wl_desc
		read -r wl_base wl_runtime wl_desc <<<"${line}"

		# 精確匹配
		if [ "${wl_base}" = "${base_id}/${base_version}" ]; then
			if [ "${wl_runtime}" = "${runtime_id}/${runtime_version}" ]; then
				found=1
				matched_desc="${wl_desc}"
				break
			fi
			# 匹配無 runtime 的情況
			if [ "${wl_runtime}" = "-" ] && [ -z "${runtime_id}" ]; then
				found=1
				matched_desc="${wl_desc}"
				break
			fi
		fi
	done <"${whitelist_file}"

	if [ "${found}" -eq 1 ]; then
		print_success "base/runtime 組合在白名單中: ${base_id}/${base_version} + ${runtime_id}/${runtime_version} (${matched_desc})"
	else
		print_warning "base/runtime 組合不在白名單中: ${base_id}/${base_version} + ${runtime_id}/${runtime_version}"
		echo "  白名單中可用的組合：" >&2
		while IFS= read -r line || [ -n "${line}" ]; do
			[[ "${line}" =~ ^[[:space:]]*# ]] && continue
			[[ "${line}" =~ ^[[:space:]]*$ ]] && continue
			local wl_base wl_runtime wl_desc
			read -r wl_base wl_runtime wl_desc <<<"${line}"
			echo "    ${wl_base} + ${wl_runtime}  # ${wl_desc}" >&2
		done <"${whitelist_file}"
		# 不在白名單中為警告，不阻止構建
	fi
}

# ==========================================
# 執行驗證
# ==========================================
validate_yaml
validate_script
cross_validate
validate_whitelist

# 輸出結果
echo ""
echo "========================================"
if [ "${HAS_ERRORS}" -eq 0 ]; then
	echo "驗證結果: 全部通過 ✓"
	exit 0
elif [ "${HAS_FIXES}" -gt 0 ] && [ "${FIX_MODE}" = true ]; then
	echo "驗證結果: 已自動修復 ${HAS_FIXES} 個問題"
	echo "建議: 修復後重新運行驗證確認問題已解決"
	exit 2
else
	echo "驗證結果: 發現 ${HAS_ERRORS} 個錯誤"
	echo "提示: 使用 --fix 參數可自動修復部分問題"
	exit 1
fi
