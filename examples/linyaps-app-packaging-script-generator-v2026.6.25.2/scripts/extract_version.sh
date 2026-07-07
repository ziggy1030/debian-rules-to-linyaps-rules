#!/bin/bash
# 從 URL 中提取版本號的工具腳本
# 用法: ./extract_version.sh <url> [pkg_name] [--regex-file <file.json>]
#
# 提取策略（按優先級）:
#   1. 從 --regex-file 中的 version_extract_examples 匹配
#   2. 通用版本號模式匹配 (x.y.z 或 x.y.z.w)
#
# 輸出: 版本號字符串（成功）或空字符串（失敗）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ============================================================
# 顏色定義
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*" >&2; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*" >&2; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*" >&2; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ============================================================
# 使用說明
# ============================================================
show_help() {
    cat <<'HELP'
從 URL 中提取版本號

用法:
  ./extract_version.sh <url> [pkg_name] [--regex-file <file.json>]

參數:
  <url>              資源下載 URL（必填）
  [pkg_name]         包名，用於匹配 version_extract_examples（可選）
  --regex-file       包含 version_extract_examples 的 JSON 文件（可選）

輸出:
  版本號字符串（stdout），日誌信息輸出到 stderr

範例:
  # 通用版本號提取
  ./extract_version.sh "https://example.com/opera-stable_130.0.5847.92_amd64.deb"
  # 輸出: 130.0.5847.92

  # 使用自定義 regex
  ./extract_version.sh "https://example.com/firefox-151.0.en-US.linux-x86_64.tar.xz" firefox --regex-file task.json

  # 配合其他腳本
  version=$(./extract_version.sh "$url" "$pkg_name")
HELP
}

# ============================================================
# 參數解析
# ============================================================
URL=""
PKG_NAME=""
REGEX_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            exit 0
            ;;
        --regex-file)
            REGEX_FILE="$2"
            shift 2
            ;;
        -*)
            log_err "未知選項: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$URL" ]]; then
                URL="$1"
            elif [[ -z "$PKG_NAME" ]]; then
                PKG_NAME="$1"
            else
                log_err "過多參數: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

if [[ -z "$URL" ]]; then
    log_err "缺少 URL 參數"
    show_help
    exit 1
fi

# ============================================================
# 策略 1: 從 regex-file 中的 version_extract_examples 匹配
# ============================================================
if [[ -n "$REGEX_FILE" && -n "$PKG_NAME" && -f "$REGEX_FILE" ]]; then
    regex=$(python3 -c "
import json, re, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

pkg_name = sys.argv[2].lower()
url = sys.argv[3]

for ex in data.get('version_extract_examples', []):
    pat = ex.get('url_pattern', '').lower()
    # 檢查 URL 模式中的關鍵字是否與包名匹配
    keywords = pkg_name.split('.')
    if any(kw in pat for kw in keywords if len(kw) > 2):
        extract_re = ex.get('extract_regex', '')
        if extract_re:
            m = re.search(extract_re, url)
            if m:
                print(m.group(1) if m.lastindex else m.group(0))
                sys.exit(0)

# 沒有匹配到
sys.exit(1)
" "$REGEX_FILE" "$PKG_NAME" "$URL" 2>/dev/null) && {
        echo "$regex"
        exit 0
    }
fi

# ============================================================
# 策略 2: 通用版本號模式匹配
# ============================================================
version=$(echo "$URL" | grep -oP '\d+\.\d+\.\d+(?:\.\d+)?' | head -1) || true

if [[ -n "$version" ]]; then
    echo "$version"
    exit 0
fi

# ============================================================
# 策略 3: 雙段版本號 (x.y) 作為最後手段
# ============================================================
version=$(echo "$URL" | grep -oP '\d+\.\d+' | head -1) || true

if [[ -n "$version" ]]; then
    log_warn "僅提取到雙段版本號: $version"
    echo "$version"
    exit 0
fi

log_err "無法從 URL 提取版本號: $URL"
exit 1
