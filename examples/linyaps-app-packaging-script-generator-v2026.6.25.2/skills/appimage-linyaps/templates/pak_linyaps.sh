#!/bin/bash

#=============================================================================
# pak_linyaps.sh - AppImage to Linglong Converter
#=============================================================================
# 基於 tar-linyaps 的 pak_linyaps.sh 模板，專門處理 AppImage 應用包
# 差異於 tar 版：
#   - 使用 --src_path 接受 AppImage 文件路徑（與 tar/deb 統一）
#   - 使用 extract_appimage.sh 解壓而非 tar -xf
#   - 調用 resolve_exec_command.sh 解析 Exec 命令
#   - 調用 parse_appimage_metadata.sh 提取元數據
#   - 保留 squashfs-root 原始目錄結構（wrapper 機制）
#=============================================================================

srcType="appimage"
templateVer="2026.6.9.1"

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

# AppImage 專用參數
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
	"aarch64")
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

	# 驗證文件格式（必須是 ELF 或 AppImage）
	local file_output
	file_output=$(file "${src_path}")
	case "${file_output}" in
	*"ELF"*|*"AppImage"*)
		echo "驗證通過: src_path='${src_path}'"
		return 0
		;;
	*)
		echo "錯誤: 文件不是有效的 AppImage: ${src_path}" >&2
		echo "  file 輸出: ${file_output}" >&2
		return 1
		;;
	esac
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
		echo "請指定 AppImage 文件完整路徑 src_path" >&2
		exit 1
	elif [ ! -f "${src_path}" ]; then
		echo "指定的 AppImage 文件不存在: ${src_path}" >&2
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

	# package_id 用於 wrapper 檔案名和 lib 目錄前綴，若未指定則發出警告
	# fallback 鏈在 build_pak() 中處理：package_id -> binary_name -> app_name -> "app"
	if [ -z "${package_id}" ]; then
		echo "警告: --package_id 未指定，wrapper 前綴將從 binary_name/app_name 推導" >&2
	fi
}

# 數據重新組裝檢查
data_regroup_check() {
	src_path=$(readlink -f "${src_path}")
	output_dir=$(readlink -f "${output_dir}")

	version_check_regroup
	validate_required_fields
	validate_src_path
}

# 初始化構建目錄（與 tar 版一致的通用機制）
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

# 主構建流程（AppImage 專用構建流程）
build_pak() {
	## Extract the AppImage package
	binary_tmp_dir="${build_tmp_dir}/tmp"
	binary_dir="${build_tmp_dir}/binary/"

	# 解壓 AppImage
	# 使用 extract_appimage.sh 腳本解壓 AppImage 文件
	# 解壓後會在 binary_tmp_dir 下生成 squashfs-root/ 目錄
	mkdir -p "${binary_tmp_dir}"
	echo "正在解壓 AppImage: ${src_path}"
	"${project_root}/scripts/extract_appimage.sh" "${src_path}" "${binary_tmp_dir}"

	# 驗證解壓結果
	if [ ! -d "${binary_tmp_dir}/squashfs-root" ]; then
		echo "錯誤: AppImage 解壓失敗，squashfs-root 目錄不存在" >&2
		exit 1
	fi

	# 創建 binary 目錄結構
	# binary/ 目錄的內容會複製到 files/ 根目錄
	# files/ 映射到 /usr/，所以 files/bin/ -> /usr/bin/
	mkdir -p "${binary_dir}"

	# 將 squashfs-root 保持原始結構，安裝到 lib/${APP_PREFIX}/
	# APP_PREFIX 優先使用 package_id，fallback 到 binary_name -> app_name -> "app"
	local app_prefix="${package_id:-${binary_name:-${app_name:-app}}}"
	if [ -z "${app_prefix}" ]; then
		echo "錯誤: 無法確定 app_prefix（package_id/binary_name/app_name 均為空）" >&2
		exit 1
	fi
	mkdir -p "${binary_dir}/lib/${app_prefix}"
	cp -rf "${binary_tmp_dir}/squashfs-root"/* "${binary_dir}/lib/${app_prefix}/"

	# 創建 bin/ 目錄用於存放 wrapper 腳本
	mkdir -p "${binary_dir}/bin"

	# AppRun 優先策略（借鑒 ll-pica 方案）
	# 優先級：AppRun > resolve_exec_command.sh 解析 > 默認 AppRun
	# 原因：AppRun 是 AppImage 的標準入口，最可靠
	#       resolve_exec_command.sh 作為 fallback，防止 AppRun 缺失
	local wrapper_target=""

	# 1. 檢測 AppRun 是否存在（最高優先級）
	if [ -f "${binary_dir}/lib/${app_prefix}/AppRun" ]; then
		wrapper_target="AppRun"
		echo "✓ 檢測到 AppRun，使用 ll-pica wrapper 方案"
	# 2. 檢測 AppRun.wrapped 是否存在
	elif [ -f "${binary_dir}/lib/${app_prefix}/AppRun.wrapped" ]; then
		wrapper_target="AppRun.wrapped"
		echo "✓ 檢測到 AppRun.wrapped，使用 wrapped 入口"
	# 3. Fallback：從 desktop 文件解析 Exec 命令
	else
		echo "未檢測到 AppRun，嘗試從 desktop 文件解析..."
		local resolved_exec=""
		if [ -n "${binary_name}" ]; then
			echo "使用用戶指定的 binary_name: ${binary_name}"
			resolved_exec="${binary_name}"
		else
			resolved_exec=$("${project_root}/scripts/resolve_exec_command.sh" "${binary_tmp_dir}/squashfs-root" 2>/dev/null || echo "")
			if [ -n "${resolved_exec}" ]; then
				echo "從 desktop 文件提取到 binary_name: ${resolved_exec}"
			else
				echo "警告: 無法從 desktop 文件提取 binary_name，將使用 AppRun 作為 fallback" >&2
				resolved_exec="AppRun"
			fi
		fi
		wrapper_target="${resolved_exec}"
	fi

	# 創建 wrapper 腳本
	# wrapper 位於 bin/ 目錄，使用相對路徑直接指向 lib/ 下的二進制
	# 始終使用相對路徑 exec，不使用 cd（遵循 wrapper 設計原則）
	# 注意：使用 \$@ 而非 $@，防止 envsubst 替換
	cat >"${binary_dir}/bin/${app_prefix}.wrapper" <<WRAPPER_EOF
#!/bin/bash
# Wrapper script generated by pak_linyaps.sh (AppImage version)
# AppRun 優先策略：${wrapper_target}
# 使用 cd+pwd 解析 wrapper 自身的絕對路徑，確保 \$PATH 執行時也能正確工作
script_dir="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\${script_dir}/../lib/${app_prefix}/${wrapper_target}" "\$@"
WRAPPER_EOF

	chmod +x "${binary_dir}/bin/${app_prefix}.wrapper"
	echo "Created wrapper script: bin/${app_prefix}.wrapper -> lib/${app_prefix}/${wrapper_target}"

	# 更新 linglong.yaml 的 command 字段
	# 將 command 設置為 wrapper 腳本路徑（數組格式，ll-builder 要求）
	if [ -f "${build_tmp_dir}/linglong.yaml" ]; then
		# 1. 刪除 command 後可能存在的舊列表項
		sed -i '/^\s*command:/{n;/^\s*-\s*/d}' "${build_tmp_dir}/linglong.yaml"
		# 2. 替換 command 行
		sed -i "s|^\s*command:.*|command:|" "${build_tmp_dir}/linglong.yaml"
		# 3. 在 command 行後追加列表項（YAML 數組格式）
		sed -i '/^\s*command:/a\  - '"${app_prefix}"'.wrapper' "${build_tmp_dir}/linglong.yaml"
		echo "Updated linglong.yaml command to array format: [${app_prefix}.wrapper]"
	fi

	# 更新 desktop 文件的 Exec= 字段
	# 替換所有 desktop 的 Exec= 為 wrapper
	for desktop_file in $(find "${build_tmp_dir}" -name "*.desktop" -type f 2>/dev/null); do
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
			new_exec="Exec=${app_prefix}.wrapper"
			if [ -n "${exec_args}" ]; then
				new_exec="${new_exec} ${exec_args}"
			fi
			# 在文件中替換該行
			sed -i "s|${exec_line}|${new_exec}|" "${desktop_file}"
		done < <(grep "^Exec=" "${desktop_file}")
		echo "Updated Exec= in: ${desktop_file} (wrapper: ${app_prefix}.wrapper)"
	done

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
