#!/bin/bash

#=============================================================================
# pak_linyaps.sh - Tar Binary Package to Linglong Converter
#=============================================================================
# 基於 deb-linglong-packer 的 pak_linyaps.sh 模板，專門處理 tar 歸檔二進制包
# 差異於 deb 版：
#   - 使用 --src_path 替代 --deb_path 接受 tar 解压根目
#   - 使用 tar -xf 解壓而非 dpkg -x
#   - 調用 handle_special_paths.sh 處理路徑轉換（與 deb 版一致）
#=============================================================================

srcType="tar"
templateVer="2026.06.02"

set -x

# 默認 base/runtime 配置
DEFAULT_BASE_ID="org.deepin.base"
DEFAULT_BASE_VERSION="25.2.2"
DEFAULT_RUNTIME_ID="org.deepin.runtime.dtk"
DEFAULT_RUNTIME_VERSION="25.2.2"

base_id="${DEFAULT_BASE_ID}"
base_version="${DEFAULT_BASE_VERSION}"
runtime_id="${DEFAULT_RUNTIME_ID}"
runtime_version="${DEFAULT_RUNTIME_VERSION}"

# 白名單配置文件路徑
whitelist_file=""

# Options
auto_clean=""
auto_push="${push}"
repo_name="nightly"
repo_url="https://repo-dev.cicd.getdeepin.org"
push_account_user=""
push_account_passwd=""

# Tar 專用參數
src_path=""
binary_name=""

init_global_data() {
	ARCH=$(uname -m)

	origin_version=""
	ll_version=""
	binary_arch=""
	linyaps_arch=""
	output_dir=""
	build_tmp_dir=""

	project_root="$(dirname "$(readlink -f "$0")")"
	default_output_dir="${project_root}/bins"

	COMMANDLINE="$@"
	for COMMAND in $COMMANDLINE; do
		key=$(echo $COMMAND | awk -F= '{print $1}')
		val=$(echo $COMMAND | awk -F= '{print $2}')

		case $key in
		--linyaps_arch)
			linyaps_arch="$val"
			;;
		--origin_version)
			origin_version="$val"
			;;
		--ll_version)
			ll_version="$val"
			;;
		--src_path)
			src_path="$val"
			;;
		--output_dir)
			output_dir="$val"
			;;
		--build_tmp_dir)
			build_tmp_dir="$val"
			;;
		--base_id)
			base_id="$val"
			;;
		--base_version)
			base_version="$val"
			;;
		--runtime_id)
			runtime_id="$val"
			;;
		--runtime_version)
			runtime_version="$val"
			;;
		--whitelist)
			whitelist_file="$val"
			;;
		--binary_name)
			binary_name="$val"
			;;
		--package_id)
			package_id="$val"
			;;
		--app_name)
			app_name="$val"
			;;
		--app_version)
			app_version="$val"
			;;
		--description)
			description="$val"
			;;
		--icon_path)
			icon_path="$val"
			;;
		esac
	done

	# 初始化構建緩存目錄
	if [ -n "${build_tmp_dir}" ]; then
		build_tmp_dir=$(readlink -f "${build_tmp_dir}")
	else
		build_tmp_dir=$(mktemp -d)
	fi

	mkdir -p "${build_tmp_dir}" || {
		echo "錯誤: 無法創建構建緩存目錄: ${build_tmp_dir}" >&2
		exit 1
	}

	case "${linyaps_arch}" in
	"x86_64")
		binary_arch="amd64"
		;;
	"arm64")
		binary_arch="arm64"
		;;
	*)
		echo "Unsupported architecture: ${linyaps_arch}"
		exit 1
		;;
	esac

	validate_base_runtime
}

# 驗證 base/runtime 配置
validate_base_runtime() {
	local has_error=0
	local has_warning=0

	local fields=(
		"base_id:${base_id}:org[0-9a-z]*\\.[0-9a-z][0-9a-z.]*:基礎運行時ID"
		"base_version:${base_version}:版本號:基礎運行時版本"
		"runtime_id:${runtime_id}:org[0-9a-z]*\\.[0-9a-z][0-9a-z.]*:應用運行時ID"
		"runtime_version:${runtime_version}:版本號:應用運行時版本"
	)

	for field_def in "${fields[@]}"; do
		IFS=: read -r field_name field_value _ field_desc <<<"${field_def}"

		if [ -z "${field_value}" ]; then
			echo "錯誤: ${field_desc} (${field_name}) 為空！" >&2
			has_error=1
			continue
		fi

		if [[ "${field_value}" =~ ^\$\{?[a-zA-Z_][a-zA-Z0-9_]*\}?$ ]]; then
			echo "錯誤: ${field_desc} (${field_name}) 的值為變量引用 '${field_value}'" >&2
			has_error=1
			continue
		fi

		if [[ "${field_name}" == *_version ]]; then
			if [[ ! "${field_value}" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
				echo "錯誤: ${field_desc} (${field_name}='${field_value}') 版本格式不正確" >&2
				has_error=1
				continue
			fi
		fi

		echo "驗證通過: ${field_desc} (${field_name}='${field_value}')"
	done

	if [ "${has_error}" -eq 0 ]; then
		validate_base_runtime_whitelist
	fi
}

validate_base_runtime_whitelist() {
	if [ -z "${whitelist_file}" ]; then
		whitelist_file="${project_root}/config/base_runtime_whitelist.conf"
		if [ ! -f "${whitelist_file}" ]; then
			whitelist_file="${skill_root}/../config/base_runtime_whitelist.conf"
		fi
	fi

	if [ ! -f "${whitelist_file}" ]; then
		echo "警告: 白名單文件不存在: ${whitelist_file}" >&2
		return 0
	fi

	if grep -q "^${base_id}/${base_version}:${runtime_id}/${runtime_version}$" "${whitelist_file}"; then
		echo "白名單驗證通過: ${base_id}/${base_version}:${runtime_id}/${runtime_version}"
		return 0
	else
		echo "錯誤: base/runtime 組合不在白名單中" >&2
		echo "  當前: ${base_id}/${base_version}:${runtime_id}/${runtime_version}" >&2
		echo "  請查看 ${whitelist_file} 获取合規組合" >&2
		return 1
	fi
}

# 驗證 src_path 是否有效
validate_src_path() {
	if [ -z "${src_path}" ]; then
		echo "錯誤: --src_path 參數為空" >&2
		return 1
	fi

	if [ ! -f "${src_path}" ]; then
		echo "錯誤: --src_path 文件不存在: ${src_path}" >&2
		return 1
	fi

	echo "驗證通過: src_path='${src_path}'"
	return 0
}

# 驗證 binary_name（若已指定則驗證存在性和可執行性）
# 注意：binary_name 為可選參數，為空時不報錯，由 build_pak() 中的自動偵測邏輯處理
validate_binary_name() {
	if [ -z "${binary_name}" ]; then
		echo "提示: --binary_name 未指定，將嘗試自動偵測"
		return 0
	fi

	local binary_path="${binary_dir:-${src_path}}/${binary_name}"
	if [ ! -f "${binary_path}" ]; then
		echo "錯誤: binary 不存在: ${binary_path}" >&2
		return 1
	fi

	if [ ! -x "${binary_path}" ]; then
		echo "錯誤: binary 不可執行: ${binary_path}" >&2
		return 1
	fi

	# 對 ELF 二進制進行架構兼容性檢查（非 ELF 如腳本則跳過）
	local resolved_path
	resolved_path=$(readlink -f "${binary_path}" 2>/dev/null) || {
		echo "錯誤: binary 符號連結已損壞: ${binary_path}" >&2
		return 1
	}
	if ! check_elf_compatibility "${resolved_path}"; then
		echo "錯誤: binary 架構不兼容: ${binary_path} -> ${resolved_path}" >&2
		return 1
	fi

	echo "驗證通過: binary_name='${binary_name}'"
	return 0
}

# 檢查 ELF 二進制的架構兼容性
# 參數：文件路徑
# 返回值：
#   0 - 兼容（非 ELF 或架構匹配）
#   1 - 不兼容（架構不匹配、未知架構、或文件無效）
# 使用 file 命令檢測 ELF 類型並提取架構，與 uname -m 比較
check_elf_compatibility() {
	local file_path="$1"

	if [ ! -f "${file_path}" ]; then
		echo "  跳過: 文件不存在或無效: ${file_path}" >&2
		return 1
	fi

	local file_output
	file_output=$(file "${file_path}") || return 1

	# 非 ELF 文件（如 shell 腳本），視為有效，跳過架構檢查
	case "${file_output}" in
	*"ELF "*"executable"* | *"ELF "*"shared object"*) ;;
	*)
		return 0
		;;
	esac

	# ELF 文件：提取架構字段並映射為 uname -m 標準格式
	local elf_arch=""
	case "${file_output}" in
	*"x86-64"*) elf_arch="x86_64" ;;
	*"aarch64"*) elf_arch="aarch64" ;;
	*"ARM"*) elf_arch="arm" ;;
	*"80386"*) elf_arch="i686" ;;
	*)
		echo "  跳過: 無法識別 ELF 架構: ${file_path}" >&2
		echo "    file 輸出: ${file_output}" >&2
		return 1
		;;
	esac

	# 與當前系統架構比較
	local host_arch
	host_arch=$(uname -m)
	if [ "${elf_arch}" != "${host_arch}" ]; then
		echo "  跳過: 架構不匹配 ${elf_arch} != ${host_arch}: ${file_path}" >&2
		return 1
	fi

	return 0
}

# 從 desktop 文件中自動提取 binary_name
# 核心思路：從所有 .desktop 文件的 Exec= 字段中提取二進制名稱，
# 統計每個名稱出現次數，返回出現次數最多的作為 binary_name
# 參數：一個或多個搜索目錄（如 "${binary_dir}" "${files_res_dir}"）
extract_binary_name_from_desktop() {
	local search_dirs=("$@")

	if [ ${#search_dirs[@]} -eq 0 ]; then
		echo ""
		return 1
	fi

	local names_file
	names_file=$(mktemp)

	# 遍歷所有 .desktop 文件，提取 Exec= 中的二進制名稱
	while IFS= read -r file; do
		while IFS= read -r line; do
			# 移除 "Exec=" 前綴
			cmd="${line#*=}"
			# 移除引號包裹的參數，保留第一個參數
			cmd=$(echo "$cmd" | sed 's/"[^"]*"/""/g' | awk '{print $1}')
			if [ -n "$cmd" ]; then
				basename "$cmd" 2>/dev/null
			fi
		done < <(grep "^Exec=" "$file" 2>/dev/null)
	done < <(find "${search_dirs[@]}" -name "*.desktop" -type f 2>/dev/null) >"$names_file"

	# 統計出現次數，返回最多的
	local result
	result=$(sort "$names_file" | uniq -c | sort -rn | head -1 | awk '{print $2}')

	rm -f "$names_file"
	echo "$result"
}

# 自動偵測 binary_name（兩級 fallback）
# 1. 優先從 desktop 文件的 Exec= 提取
# 2. 若無 desktop，嘗試調用 scan_executables.sh 掃描
# 參數：一個或多個搜索目錄（如 "${binary_dir}" "${files_res_dir}"）
# 返回偵測到的 binary_name（空字串表示失敗）
auto_detect_binary_name() {
	local search_dirs=("$@")

	echo "--- 自動偵測 binary_name ---" >&2

	if [ ${#search_dirs[@]} -eq 0 ]; then
		echo "錯誤: 未指定搜索目錄" >&2
		echo ""
		return 1
	fi

	# 第一級：從 desktop 文件提取
	local detected
	detected=$(extract_binary_name_from_desktop "${search_dirs[@]}")
	if [ -n "${detected}" ]; then
		echo "從 desktop Exec= 偵測到: ${detected}" >&2
		echo "${detected}"
		return 0
	fi
	echo "未找到 desktop 文件或 Exec= 為空" >&2

	# 第二級：調用 scan_executables.sh 掃描（只用第一個目錄）
	local scan_script="${project_root}/scripts/scan_executables.sh"
	if [ ! -f "${scan_script}" ]; then
		echo "警告: scan_executables.sh 不存在: ${scan_script}" >&2
		echo ""
		return 1
	fi

	echo "嘗試 scan_executables.sh 掃描..." >&2
	detected=$("${scan_script}" "${search_dirs[0]}" 2>/dev/null | head -1)
	if [ -n "${detected}" ]; then
		echo "從可執行檔掃描偵測到: ${detected}" >&2
		echo "${detected}"
		return 0
	fi

	echo "錯誤: 無法自動偵測 binary_name" >&2
	echo ""
	return 1
}

# 從 origin_version 生成 ll_version（X.Y.Z.W 格式）
generate_version_from_origin() {
	local origin_ver="$1"

	if [[ -z "${origin_ver}" ]]; then
		echo "錯誤: origin_version 為空" >&2
		return 1
	fi

	local version_parts=()
	local temp_version="${origin_ver}"

	while [[ "${temp_version}" =~ ([0-9]+)(.*) ]]; do
		version_parts+=("${BASH_REMATCH[1]}")
		temp_version="${BASH_REMATCH[2]#*[!0-9]}"
	done

	if [[ ${#version_parts[@]} -lt 1 ]]; then
		echo "錯誤: origin_version 格式不正確，無法提取足夠的數字部分" >&2
		return 1
	fi

	local major="${version_parts[0]:-0}"
	local minor="${version_parts[1]:-0}"
	local patch="${version_parts[2]:-0}"
	local build="${version_parts[3]:-0}"

	local generated_version="${major}.${minor}.${patch}.${build}"

	if [[ "${generated_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "${generated_version}"
		return 0
	else
		echo "錯誤: 生成的版本號格式不正確: ${generated_version}" >&2
		return 1
	fi
}

# 版本檢查與重新組裝
version_check_regroup() {
	if [[ -n "${ll_version}" &&
		"${ll_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		echo "使用已有的 ll_version=${ll_version}"
	else
		echo "ll_version 格式不正確或為空，嘗試使用 origin_version 生成"

		local generated_version
		if generated_version=$(generate_version_from_origin "${origin_version}"); then
			ll_version="${generated_version}"
			echo "使用 origin_version=${origin_version} 生成 ll_version=${ll_version}"
		else
			echo "無法從 origin_version 生成有效的版本號"
			exit 1
		fi
	fi

	echo "最終 ll_version=${ll_version}"
}

# 驗證必填字段
validate_required_fields() {
	if [ -z "${src_path}" ]; then
		echo "請指定源包完整路徑 src_path" >&2
		exit 1
	elif [ ! -f "${src_path}" ]; then
		echo "指定的源包文件不存在: ${src_path}" >&2
		exit 1
	fi

	if [ -z "${output_dir}" ]; then
		output_dir="${default_output_dir}"
	fi

	if [ ! -d "${output_dir}" ]; then
		echo "輸出目錄不存在，嘗試創建: ${output_dir}"
		if mkdir -p "${output_dir}"; then
			echo "成功創建輸出目錄: ${output_dir}"
		else
			echo "錯誤: 無法創建輸出目錄: ${output_dir}" >&2
			exit 1
		fi
	fi

	if [ -z "${ll_version}" ]; then
		echo "請單獨指定 ll_version 或提供正確的 origin_version" >&2
		exit 1
	fi

	if [ -z "${linyaps_arch}" ]; then
		linyaps_arch=$(uname -m)
	fi
}

# 數據重新組裝檢查
data_regroup_check() {
	src_path=$(readlink -f "${src_path}")
	output_dir=$(readlink -f "${output_dir}")

	version_check_regroup
	validate_required_fields
}

# 初始化構建目錄（與 deb 版一致的通用機制）
# 準備構建環境：複製 files_res、腳本、生成 linglong.yaml
build_dir_init() {
	# 檢測錯誤的環境變量設置
	# command 應該由 build_pak() 中的 wrapper 機制通過 sed 替換，不是 envsubst
	if [ -n "${command:-}" ]; then
		echo "警告: 檢測到 'command' 環境變量已設置: '${command}'" >&2
		echo "  command 應該由 build_pak() 中的 wrapper 機制通過 sed 替換" >&2
		echo "  如果您在 build_dir_init() 中使用了 'export command=...'，請刪除該行" >&2
		echo "  此警告不會阻止構建，因為 sed 會覆蓋錯誤的值" >&2
	fi

	## Generate linyaps building dir
	mkdir -p "${build_tmp_dir}/binary"
	cd "${build_tmp_dir}"

	# 注意：模板文件位於 templates/ 目錄下
	cp -rf "${project_root}/templates/files_res" \
		"${build_tmp_dir}"

	## 複製腳本到構建目錄，供 linglong.yaml build 階段使用
	mkdir -p "${build_tmp_dir}/scripts"
	cp -f "${project_root}/scripts/"*.sh "${build_tmp_dir}/scripts/"

	## Generate linyaps res
	## Envs for linglong.yaml
	## 注意：不要 export command，command 由 build_pak() 中的 wrapper 機制通過 sed 替換
	## base/runtime 由 build_pak() 透過 sed 延遲注入
	export prefix="\$PREFIX"
	export package_id="${package_id}"
	export app_name="${app_name}"
	export description="${description}"
	export ll_version=${ll_version}
	export ll_architecture=${linyaps_arch}

	# 注意：模板文件位於 templates/ 目錄下
	cat "${project_root}/templates/linglong.yaml" |
		envsubst >"${build_tmp_dir}/linglong.yaml"

	# 檢測模板中的 version 字段是否仍為變量（防止 LLM 錯誤替換為絕對值）
	# 正常模板中 version 應為 ${ll_version}，envsubst 後會替換為真實版本號
	# 若 LLM 已將 version 寫死（如 version: "1.0"），則 envsubst 無法正確替換
	if ! grep -q '\${ll_version}' "${project_root}/templates/linglong.yaml" 2>/dev/null; then
		echo "錯誤: linglong.yaml 模板中未找到 \${ll_version} 變量！" >&2
		echo "  version 字段已被 LLM 錯誤替換為絕對值，envsubst 將無法正確替換" >&2
		echo "  請檢查: ${project_root}/templates/linglong.yaml" >&2
		echo "  兩個 version 字段（頂層 version 和 package.version）都必須保持為 \${ll_version}" >&2
		exit 1
	fi
}

# 主構建流程（與 deb 版一致的完整構建流程）
build_pak() {
	## Extract the binary package
	binary_tmp_dir="${build_tmp_dir}/tmp"
	binary_dir="${build_tmp_dir}/binary/"

	# 解壓 tar 包
	# 注意：必須使用 -C 選項指定解壓目標目錄
	# 錯誤寫法：tar -xf "${src_path}" "${binary_tmp_dir}/"（會把路徑當作歸檔內文件名）
	mkdir -p "${binary_tmp_dir}"
	tar -xf "${src_path}" -C "${binary_tmp_dir}"

	# 創建 binary 目錄結構
	# binary/ 目錄的內容會複製到 files/ 根目錄
	# files/ 映射到 /usr/，所以 files/bin/ -> /usr/bin/
	mkdir -p "${binary_dir}"

	# 調用特殊路徑處理腳本
	# 處理 tar 中的文件路徑轉換，包括：
	# 1. /usr/ 下的內容直接複製到 binary/ (對應 files/)
	# 2. 非 /usr 標準路徑（如 /opt/uTools/）直接放到 binary/ 下作為未歸類目錄
	#    例如：/opt/uTools/ -> binary/uTools/ (去掉 opt/ 層級)
	# 3. 支持包含空格、括號、中文、&、@、#、$ 等特殊字符的路徑
	# 注意：此操作必須在所有軟鏈動作之前完成，否則軟鏈關係將被破壞
	"${project_root}/scripts/handle_special_paths.sh" "${binary_tmp_dir}" "${binary_dir}"

	# 創建 bin/ 目錄用於存放 wrapper 腳本
	# 注意：此操作必須在特殊路徑處理完成之後進行
	mkdir -p "${binary_dir}/bin"

	# 處理二進制文件：創建 wrapper 腳本
	# 在 files/bin/ 創建 wrapper 腳本，執行實際二進制文件
	# 注意：此操作必須在所有文件複製和路徑處理完成之後進行

	# 標記 binary_name 是否為用戶顯式指定
	# 用於決定 desktop Exec= 替換策略：
	#   - 客製化模式（用戶指定）：無條件替換所有 desktop 的 Exec= 為 wrapper
	#   - 自動偵測模式（從 desktop 提取）：只替換 Exec= 包含 binary_name 的行
	is_custom_binary_name=false
	if [ -n "${binary_name}" ]; then
		is_custom_binary_name=true
	fi

	if [ -z "${binary_name}" ]; then
		# 未指定 binary_name 時，自動從 desktop 文件中提取
		# 同時搜索 binary/（解壓的 tar 內容）和 files_res/（LLM 初始化的模板資源）
		echo "binary_name not specified, auto-detecting from desktop files..."
		binary_name=$(extract_binary_name_from_desktop "${binary_dir}" "${build_tmp_dir}/files_res")
		if [ -z "${binary_name}" ]; then
			# 第二級 fallback：調用 scan_executables.sh 掃描
			echo "未從 desktop 偵測到 binary_name，嘗試 scan_executables.sh 掃描..."
			local scan_script="${project_root}/scripts/scan_executables.sh"
			if [ -f "${scan_script}" ]; then
				binary_name=$("${scan_script}" "${binary_dir}" 2>/dev/null | head -1)
			fi
		fi
		if [ -n "${binary_name}" ]; then
			echo "Auto-detected binary_name: ${binary_name}"
		else
			echo "Warning: Could not auto-detect binary_name"
		fi
	fi

	if [ -n "${binary_name}" ]; then
		# 在 binary/ 目錄下查找二進制文件（可能有多個匹配，如 bin/ 和 opt/ 下）
		# 逐個檢查：跳過損壞軟鏈、架構不匹配的 ELF，直到找到有效的 binary
		actual_binary=""
		real_binary=""
		rel_binary=""
		while IFS= read -r candidate; do
			# 解析真實路徑，跳過損壞的符號連結
			local resolved
			resolved=$(readlink -f "${candidate}" 2>/dev/null) || {
				echo "  跳過損壞軟鏈: ${candidate}" >&2
				continue
			}
			# 檢查 ELF 架構兼容性
			if check_elf_compatibility "${resolved}"; then
				actual_binary="${candidate}"
				real_binary="${resolved}"
				echo "  選中有效的 binary: ${candidate} -> ${resolved}" >&2
				break
			fi
		done < <(find "${binary_dir}" -type f -name "${binary_name}" -executable 2>/dev/null | sort)

		if [ -n "${actual_binary}" ] && [ -n "${real_binary}" ]; then
			# 計算相對於 binary/ 的路徑
			rel_binary="${real_binary#${binary_dir}}"

			# 創建 wrapper 腳本
			# wrapper 位於 bin/ 目錄，使用相對路徑直接指向原始二進制
			# 文件名使用 .wrapper 後綴，避免與原始二進制名衝突
			# 注意：使用 \$@ 而非 $@，防止 envsubst 替換
			cat >"${binary_dir}/bin/${binary_name}.wrapper" <<WRAPPER_EOF
#!/bin/bash
# Wrapper script generated by pak_linyaps.sh
# 使用 cd+pwd 解析 wrapper 自身的絕對路徑，確保 \$PATH 執行時也能正確工作
script_dir="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\${script_dir}/../${rel_binary}" "\$@"
WRAPPER_EOF

			chmod +x "${binary_dir}/bin/${binary_name}.wrapper"
			echo "Created wrapper script: bin/${binary_name}.wrapper -> ../${rel_binary}"
			echo "  (wrapper resolves absolute path first, then uses relative path)"

			# 更新 linglong.yaml 的 command 字段
			# 將 command 設置為 wrapper 腳本路徑（數組格式，ll-builder 要求）
			if [ -f "${build_tmp_dir}/linglong.yaml" ]; then
				# 1. 刪除 command 後可能存在的舊列表項
				sed -i '/^\s*command:/{n;/^\s*-\s*/d}' "${build_tmp_dir}/linglong.yaml"
				# 2. 替換 command 行
				sed -i "s|^\s*command:.*|command:|" "${build_tmp_dir}/linglong.yaml"
				# 3. 在 command 行後追加列表項（YAML 數組格式）
				sed -i '/^\s*command:/a\  - '"${binary_name}"'.wrapper' "${build_tmp_dir}/linglong.yaml"
				echo "Updated linglong.yaml command to array format: [${binary_name}.wrapper]"
			fi

			# 更新 desktop 文件的 Exec= 字段
			# 根據 binary_name 來源採用不同替換策略：
			#   - 客製化模式：無條件替換所有 desktop 的 Exec= 為 wrapper
			#   - 自動偵測模式：只替換 Exec= 包含 binary_name 的行
			for desktop_file in $(find "${build_tmp_dir}" -name "*.desktop" -type f 2>/dev/null); do
				if [ "${is_custom_binary_name}" = "true" ]; then
					# 客製化模式：無條件替換所有 Exec= 行
					# 處理 env 前綴（如 Exec=env VAR=val binary args）
					# 移除 env 前綴，將第一個二進制參數替換為 wrapper，保留其餘參數
					while IFS= read -r exec_line; do
						[ -z "${exec_line}" ] && continue
						# 提取 Exec= 後的完整值
						exec_value="${exec_line#Exec=}"
						# 移除 env VAR=val 前綴（支持多個 KEY=VALUE 環境變數）
						exec_value=$(echo "${exec_value}" | sed 's/^env \(\S*=\S*\s\)*//')
						# 提取第一個參數（二進制名/路徑）和其餘參數
						exec_bin=$(echo "${exec_value}" | awk '{print $1}')
						exec_args=$(echo "${exec_value}" | awk '{$1=""; print $0}' | sed 's/^ //')
						# 替換為 wrapper
						new_exec="Exec=${binary_name}.wrapper"
						if [ -n "${exec_args}" ]; then
							new_exec="${new_exec} ${exec_args}"
						fi
						# 在文件中替換該行
						sed -i "s|${exec_line}|${new_exec}|" "${desktop_file}"
					done < <(grep "^Exec=" "${desktop_file}")
					echo "Updated Exec= in: ${desktop_file} (custom binary: ${binary_name}.wrapper)"
				else
					# 自動偵測模式：只替換 Exec= 包含 binary_name 的行
					if grep -q "Exec=.*${binary_name}" "${desktop_file}"; then
						sed -i "s|Exec=[^ ]*${binary_name}[^ ]*|Exec=${binary_name}.wrapper|g" "${desktop_file}"
						echo "Updated Exec= in: ${desktop_file}"
					fi
				fi
			done
		else
			echo "Warning: No valid binary found for '${binary_name}' in ${binary_dir} (all candidates failed ELF compatibility check or not found)"
		fi
	fi

	# 注入 base/runtime 到 linglong.yaml（延遲注入，支援 CLI 參數動態覆蓋）
	# 模板中 base/runtime 為空佔位符 ""，由 sed 在構建時動態寫入
	# 執行時機：wrapper 創建完成、desktop Exec 更新之後，ll-builder build 之前
	if [ -f "${build_tmp_dir}/linglong.yaml" ]; then
		sed -i "s|^\s*base:.*|base: ${base_id}/${base_version}|" "${build_tmp_dir}/linglong.yaml"
		echo "Updated linglong.yaml base: ${base_id}/${base_version}"
		sed -i "s|^\s*runtime:.*|runtime: ${runtime_id}/${runtime_version}|" "${build_tmp_dir}/linglong.yaml"
		echo "Updated linglong.yaml runtime: ${runtime_id}/${runtime_version}"
	fi

	# 第一步去重：刪除 binary/ 中與 files_res/ 內容重複的 desktop 文件
	# 在 ll-builder build 之前執行，避免重複文件進入最終包
	# 參數說明：
	#   - 第一個參數：待去重的目標目錄 (binary/)
	#   - --reference-dir：參考目錄 (files_res/)
	# 效果：刪除 binary/ 中與 files_res/ 內容相同的 desktop 文件
	"${project_root}/scripts/dedup_desktop_files.sh" "${build_tmp_dir}/binary" --reference-dir "${build_tmp_dir}/files_res"

	# 第二步去重：對 files_res/ 內部的 desktop 文件進行去重（保底檢測）
	# 避免相同內容的 desktop 文件重複打包
	"${project_root}/scripts/dedup_desktop_files.sh" "${build_tmp_dir}/files_res"

	# 驗證並修復嵌套 bin/ 路徑問題
	# 檢測 binary/bin/bin/ 嵌套問題並自動修復
	"${project_root}/scripts/validate_bin_nesting.sh" "${binary_dir}" --fix

	# 創建玲瓏構建標識文件
	# binary/ 目錄對應 linglong.yaml 中的 ${prefix}
	# 此文件用於標識由 linyaps 系統生成的構建產物
	touch "${binary_dir}/.linyaps_genius"
	echo "Created identity file: ${binary_dir}/.linyaps_genius"

	## Building & Exporting
	ll-builder build --skip-output-check
	building_status=$?
	if [ "${building_status}" = "0" ]; then
		echo "Building success ! "
	else
		echo "Building failed ! "
		exit 1
	fi
	ll-builder export --no-develop --layer

	## Check layers
	binary_layer=$(find "${build_tmp_dir}" -type f \
		-name "*binary.layer")
	if [ -z ${binary_layer} ]; then
		echo "Failed to build paks !"
		exit 1
	else
		mv "${binary_layer}" "${output_dir}"
	fi
}

push_dev() {
	## Check data
	export LINGLONG_USERNAME="${LINGLONG_USERNAME:-$push_account_user}"
	export LINGLONG_PASSWORD="${LINGLONG_PASSWORD:-$push_account_passwd}"
	for data in repo_name repo_url LINGLONG_USERNAME LINGLONG_PASSWORD; do
		if [ -z "${!data}" ]; then
			echo "Error: Required '$data' is missing"
			exit 1
		fi
	done
	## Push
	cd "${build_tmp_dir}"
	ll-builder push --repo-name ${repo_name} --repo-url ${repo_url}
}

main() {
	init_global_data "$@"
	data_regroup_check
	build_dir_init
	build_pak

	## Auto push
	if [[ -n "${auto_push}" && ("${auto_push}" =~ ^[Tt][Rr][Uu][Ee]$ ||
		"${auto_push}" =~ ^[Tt]$) ]]; then
		push_dev
	else
		echo "Skip auto push due to empty or false value of auto_push"
	fi

	## Clean up
	if [ -z "${auto_clean}" ] || [ "${auto_clean}" = "TRUE" ] || [ "${auto_clean}" = "true" ]; then
		rm -rf "${build_tmp_dir}"
	fi
}

main "$@"
exit 0
