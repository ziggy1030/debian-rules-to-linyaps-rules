#!/bin/bash
#=============================================================================
# scan_executables.sh - 掃描 tar 解压根目中的可執行檔案
#=============================================================================
# 功能：掃描指定目錄中的可執行二進制檔案，通過 timeout 15s 運行測試
#       識別可長期運行的主程式
# 用法：scan_executables.sh <extract_dir>
#=============================================================================

set -euo pipefail

# 配置
timeout_seconds=15
current_arch=$(uname -m)

# 參數驗證
if [ $# -lt 1 ]; then
    echo "用法: $0 <extract_dir>" >&2
    exit 1
fi

extract_dir="$1"

if [ -z "${extract_dir}" ] || [ ! -d "${extract_dir}" ]; then
    echo "錯誤: 無效的解壓目錄: ${extract_dir}" >&2
    exit 1
fi

found_binaries=()

# 從 file 命令輸出中提取 ELF 二進制的 CPU 架構
# 返回標準化架構名（如 x86_64、aarch64），非 ELF 文件返回空字符串
get_binary_arch() {
    local file_path="$1"
    local file_output

    file_output=$(file "${file_path}") || return 0

    # 只處理 ELF 文件
    case "${file_output}" in
        *"ELF "*"executable"*|*"ELF "*"shared object"*)
            ;;
        *)
            # 非 ELF（如腳本），跳過架構檢查
            return 0
            ;;
    esac

    # 提取架構字段並映射為 uname -m 標準格式
    case "${file_output}" in
        *"x86-64"*)   echo "x86_64" ;;
        *"aarch64"*)  echo "aarch64" ;;
        *"ARM"*)      echo "arm" ;;
        *"80386"*)    echo "i686" ;;
        *)            echo "" ;;
    esac
}

# 掃描解压根目（非遞歸，只看根目錄）
# 排除：*.so, *.so.*, *.a, *.la, *.o, 隱藏文件
while IFS= read -r binary; do
    # 跳過符號連結
    [ -f "${binary}" ] || continue

    # 架構匹配檢查（僅 ELF 二進制）
    bin_arch=$(get_binary_arch "${binary}")
    if [ -n "${bin_arch}" ] && [ "${bin_arch}" != "${current_arch}" ]; then
        echo "跳過 $(basename "${binary}"): 架構 ${bin_arch} 與當前系統 ${current_arch} 不匹配" >&2
        continue
    fi

    # 嘗試運行 15 秒
    timeout ${timeout_seconds} "${binary}" &
    pid=$!
    
    # 等待 timeout 或直到進程結束
    wait ${pid} 2>/dev/null
    exit_code=$?
    
    # exit_code == 124 表示 timeout（正常運行的程序）
    if [ ${exit_code} -eq 124 ]; then
        found_binaries+=("$(basename "${binary}")")
        echo "$(basename "${binary}")"
    fi
done < <(find "${extract_dir}" -maxdepth 1 -type f \
    ! -name "*.so" \
    ! -name "*.so.*" \
    ! -name "*.a" \
    ! -name "*.la" \
    ! -name "*.o" \
    ! -name ".*" \
    -executable 2>/dev/null)

# 如果找到任何候選，返回成功
if [ ${#found_binaries[@]} -gt 0 ]; then
    exit 0
else
    echo "警告: 未找到可運行的二進制檔案" >&2
    exit 1
fi
