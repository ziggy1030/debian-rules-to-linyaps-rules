#!/bin/bash
#=============================================================================
# extract_appimage.sh - AppImage 解壓腳本
#=============================================================================
# 功能：解壓 AppImage 文件到指定目錄
# 用法：extract_appimage.sh <appimage_path> <output_dir>
#
# 解壓方式：chmod +x + --appimage-extract
# 輸出：在 output_dir 下生成 squashfs-root/ 目錄
#=============================================================================

set -euo pipefail

# 參數驗證
if [ $# -lt 2 ]; then
    echo "用法: $0 <appimage_path> <output_dir>" >&2
    exit 1
fi

appimage_path="$1"
output_dir="$2"

# 驗證輸入文件
if [ ! -f "${appimage_path}" ]; then
    echo "錯誤: AppImage 文件不存在: ${appimage_path}" >&2
    exit 1
fi

# 驗證文件格式（必須是 ELF 或 AppImage）
file_output=$(file "${appimage_path}")
case "${file_output}" in
    *"ELF"*|*"AppImage"*)
        # 有效的 AppImage 文件
        ;;
    *)
        echo "錯誤: 文件不是有效的 AppImage: ${appimage_path}" >&2
        echo "  file 輸出: ${file_output}" >&2
        exit 1
        ;;
esac

# 創建輸出目錄
mkdir -p "${output_dir}"

# 解壓 AppImage
# 使用 --appimage-extract 而非 --appimage-extract-and-run
# 這樣只解壓不運行，更安全
echo "正在解壓 AppImage: ${appimage_path}"
cd "${output_dir}"
chmod +x "${appimage_path}"
"${appimage_path}" --appimage-extract > /dev/null 2>&1

# 驗證解壓結果
if [ ! -d "${output_dir}/squashfs-root" ]; then
    echo "錯誤: 解壓失敗，squashfs-root 目錄不存在" >&2
    exit 1
fi

# 檢查 AppRun 是否存在（AppImage 規範要求）
if [ ! -e "${output_dir}/squashfs-root/AppRun" ]; then
    echo "警告: squashfs-root 中未找到 AppRun（某些 AppImage 變體可能使用 AppRun.wrapped）" >&2
fi

echo "AppImage 解壓成功: ${output_dir}/squashfs-root"
ls -la "${output_dir}/squashfs-root" | head -20

exit 0
