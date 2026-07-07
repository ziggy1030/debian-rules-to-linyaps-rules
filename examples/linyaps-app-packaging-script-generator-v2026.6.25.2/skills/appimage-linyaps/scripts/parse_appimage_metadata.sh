#!/bin/bash
#=============================================================================
# parse_appimage_metadata.sh - AppImage 元數據提取腳本
#=============================================================================
# 功能：從 AppImage 文件和 desktop 文件中提取元數據
# 用法：parse_appimage_metadata.sh <appimage_file> <squashfs_root_dir>
#
# 輸出：key=value 格式的元數據，可直接 eval 載入
# 提取的元數據：
#   - app_name: 應用名稱（從 desktop Name= 提取）
#   - package_id: 玲瓏包 ID（從 desktop 文件名推導）
#   - description: 應用描述（從 desktop Comment= 提取）
#   - exec_command: Exec 命令（從 desktop Exec= 提取）
#   - icon_name: 圖標名稱（從 desktop Icon= 提取）
#   - version: 版本號（從文件名正則提取）
#=============================================================================

set -euo pipefail

# 參數驗證
if [ $# -lt 2 ]; then
    echo "用法: $0 <appimage_file> <squashfs_root_dir>" >&2
    exit 1
fi

appimage_file="$1"
squashfs_root="$2"

if [ ! -f "${appimage_file}" ]; then
    echo "錯誤: AppImage 文件不存在: ${appimage_file}" >&2
    exit 1
fi

if [ ! -d "${squashfs_root}" ]; then
    echo "錯誤: squashfs-root 目錄不存在: ${squashfs_root}" >&2
    exit 1
fi

# 查找 desktop 文件
desktop_file=$(find "${squashfs_root}" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null | head -1)

if [ -z "${desktop_file}" ]; then
    echo "警告: 未找到 desktop 文件，將使用默認值" >&2
fi

# 提取 app_name（從 desktop Name=）
app_name=""
if [ -n "${desktop_file}" ]; then
    app_name=$(grep "^Name=" "${desktop_file}" 2>/dev/null | head -1 | cut -d'=' -f2-)
fi

# 如果 Name= 為空，從文件名推導
if [ -z "${app_name}" ]; then
    filename=$(basename "${appimage_file}")
    # 移除 .AppImage 後綴和版本號
    app_name=$(echo "${filename}" | sed -E 's/[-_]?[vV]?[0-9]+\.[0-9]+(\.[0-9]+)*([-_][0-9]+)?[-_]?//;s/\.AppImage$//;s/\.appimage$//')
    # 如果還是空，使用文件名
    if [ -z "${app_name}" ]; then
        app_name="${filename%.*}"
    fi
fi

# 提取 package_id（從 desktop 文件名推導）
package_id=""
if [ -n "${desktop_file}" ]; then
    desktop_name=$(basename "${desktop_file}" .desktop)
    # 如果 desktop 文件名是反向域名格式（如 com.example.app），直接使用
    if [[ "${desktop_name}" =~ ^[a-z][a-z0-9]*\.[a-z][a-z0-9]*\.[a-z] ]]; then
        package_id="${desktop_name}"
    fi
fi

# 如果無法從 desktop 推導，從 app_name 生成
if [ -z "${package_id}" ]; then
    # 將 app_name 轉換為小寫，替換非字母數字字符為點
    package_id=$(echo "${app_name}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/./g' | sed 's/\.\.*/\./g' | sed 's/^\.//;s/\.$//')
    # 如果太短，添加 org. 前綴
    if [[ ${#package_id} -lt 5 ]]; then
        package_id="org.${package_id}"
    fi
fi

# 提取 description（從 desktop Comment=）
description=""
if [ -n "${desktop_file}" ]; then
    description=$(grep "^Comment=" "${desktop_file}" 2>/dev/null | head -1 | cut -d'=' -f2-)
fi

# 如果 Comment= 為空，使用默認描述
if [ -z "${description}" ]; then
    description="Converted from AppImage: $(basename "${appimage_file}")"
fi

# 提取 exec_command（從 desktop Exec=）
exec_command=""
if [ -n "${desktop_file}" ]; then
    exec_line=$(grep "^Exec=" "${desktop_file}" 2>/dev/null | head -1)
    if [ -n "${exec_line}" ]; then
        exec_command="${exec_line#Exec=}"
        # 移除引號
        exec_command=$(echo "${exec_command}" | sed "s/^['\"]//;s/['\"]$//")
        # 移除參數佔位符
        exec_command=$(echo "${exec_command}" | sed 's/\s*%[UuFfickDdNn]//g')
    fi
fi

# 提取 icon_name（從 desktop Icon=）
icon_name=""
if [ -n "${desktop_file}" ]; then
    icon_line=$(grep "^Icon=" "${desktop_file}" 2>/dev/null | head -1)
    if [ -n "${icon_line}" ]; then
        icon_name="${icon_line#Icon=}"
        # 移除路徑前綴和擴展名，只保留圖標名稱
        icon_name=$(echo "${icon_name}" | sed -E 's#.*/([^.]*)\..*$#\1#')
    fi
fi

# 提取版本號（從文件名正則提取）
version=""
filename=$(basename "${appimage_file}")

# 嘗試多種版本號模式
# 模式1: -v1.2.3 或 -V1.2.3
if [[ "${filename}" =~ [-_][vV]([0-9]+\.[0-9]+(\.[0-9]+)*) ]]; then
    version="${BASH_REMATCH[1]}"
# 模式2: -1.2.3- 或 _1.2.3_
elif [[ "${filename}" =~ [-_]([0-9]+\.[0-9]+(\.[0-9]+)*)[-_] ]]; then
    version="${BASH_REMATCH[1]}"
# 模式3: 1.2.3 在文件名開頭
elif [[ "${filename}" =~ ^([0-9]+\.[0-9]+(\.[0-9]+)*) ]]; then
    version="${BASH_REMATCH[1]}"
# 模式4: 任何位置的版本號
elif [[ "${filename}" =~ ([0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)*) ]]; then
    version="${BASH_REMATCH[1]}"
fi

# 如果無法提取版本號，使用默認值
if [ -z "${version}" ]; then
    version="1.0.0.0"
fi

# 確保版本號是 X.Y.Z.W 格式（ll-builder 要求）
# 補全不足4位的版本號
IFS='.' read -ra version_parts <<< "${version}"
while [ ${#version_parts[@]} -lt 4 ]; do
    version_parts+=("0")
done
version="${version_parts[0]}.${version_parts[1]}.${version_parts[2]}.${version_parts[3]}"

# 輸出元數據（key=value 格式）
echo "app_name=${app_name}"
echo "package_id=${package_id}"
echo "description=${description}"
echo "exec_command=${exec_command}"
echo "icon_name=${icon_name}"
echo "version=${version}"

exit 0
