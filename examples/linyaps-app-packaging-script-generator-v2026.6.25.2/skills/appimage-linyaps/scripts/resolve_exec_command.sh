#!/bin/bash
#=============================================================================
# resolve_exec_command.sh - AppImage Exec 命令解析腳本
#=============================================================================
# 功能：從 AppImage 的 desktop 文件中準確提取 Exec 命令
# 用法：resolve_exec_command.sh <squashfs_root_dir>
#
# 輸出：解析後的 binary name（供 wrapper 使用）
# 返回值：0=成功，1=失敗
#
# 支持的 Exec 模式：
#   - AppRun 直接調用：Exec=AppRun %U
#   - AppRun.wrapped：Exec=AppRun.wrapped
#   - 直接二進制：Exec=myapp --gui
#   - 帶 ${HERE} 變量：Exec=${HERE}/usr/bin/myapp
#   - 帶引號：Exec="/path/to/AppRun" %U
#=============================================================================

set -euo pipefail

# 參數驗證
if [ $# -lt 1 ]; then
    echo "用法: $0 <squashfs_root_dir>" >&2
    exit 1
fi

squashfs_root="$1"

if [ ! -d "${squashfs_root}" ]; then
    echo "錯誤: squashfs-root 目錄不存在: ${squashfs_root}" >&2
    exit 1
fi

# 查找 desktop 文件
desktop_file=$(find "${squashfs_root}" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null | head -1)

if [ -z "${desktop_file}" ]; then
    echo "錯誤: 未找到 desktop 文件" >&2
    exit 1
fi

# 提取 Exec= 字段
exec_line=$(grep "^Exec=" "${desktop_file}" 2>/dev/null | head -1)

if [ -z "${exec_line}" ]; then
    echo "錯誤: desktop 文件中未找到 Exec= 字段" >&2
    exit 1
fi

# 移除 "Exec=" 前綴
exec_value="${exec_line#Exec=}"

# 移除引號（支持單引號和雙引號）
exec_value=$(echo "${exec_value}" | sed "s/^['\"]//;s/['\"]$//")

# 移除參數（%U, %f, %u, %F, %i, %c, %k 等 desktop 文件佔位符）
exec_value=$(echo "${exec_value}" | sed 's/\s*%[UuFfickDdNn]//g')

# 處理 ${HERE} 變量（替換為相對路徑 .）
# ${HERE} 在 AppImage 中表示 AppRun 所在目錄
exec_value=$(echo "${exec_value}" | sed 's/\${HERE}\//\.\//g')

# 提取第一個參數（binary name 或路徑）
exec_cmd=$(echo "${exec_value}" | awk '{print $1}')

# 如果是路徑，提取文件名
if [[ "${exec_cmd}" == */* ]]; then
    exec_cmd=$(basename "${exec_cmd}")
fi

# 驗證提取結果
if [ -z "${exec_cmd}" ]; then
    echo "錯誤: 無法從 Exec= 中提取命令" >&2
    echo "  原始 Exec= 行: ${exec_line}" >&2
    exit 1
fi

# 檢查命令是否在 squashfs-root 中存在
# 嘗試多種可能的路徑
possible_paths=(
    "${squashfs_root}/${exec_cmd}"
    "${squashfs_root}/usr/bin/${exec_cmd}"
    "${squashfs_root}/bin/${exec_cmd}"
)

found=false
for path in "${possible_paths[@]}"; do
    if [ -e "${path}" ]; then
        found=true
        break
    fi
done

if [ "${found}" = false ]; then
    echo "警告: 提取的命令 '${exec_cmd}' 在 squashfs-root 中未找到" >&2
    echo "  嘗試的路徑:" >&2
    for path in "${possible_paths[@]}"; do
        echo "    - ${path}" >&2
    done
    # 不退出，繼續返回結果（可能是符號連結或特殊情況）
fi

echo "${exec_cmd}"
exit 0
