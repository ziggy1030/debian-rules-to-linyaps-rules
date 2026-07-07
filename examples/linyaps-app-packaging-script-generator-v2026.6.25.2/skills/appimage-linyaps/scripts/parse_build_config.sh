#!/bin/bash
#=============================================================================
# parse_build_config.sh - 解析並驗證 appimage-linyaps 構建配置 JSON 文件
#=============================================================================
# 功能：讀取 JSON 配置文件，驗證必填欄位，輸出解析結果供後續流程使用
# 用法：parse_build_config.sh <config.json>
# 輸出：以 key=value 格式輸出到 stdout，錯誤信息輸出到 stderr
#
# JSON 結構：
#   {
#     "main": { ... },      ← 必填欄位
#     "optional": { ... }   ← 可選欄位（含默認值）
#   }
#=============================================================================

set -euo pipefail

#=============================================================================
# 配置定義
#=============================================================================

# 必填欄位列表（main 分組）
# 注意：appimage_file 和 appimage_url 至少需要提供一個
REQUIRED_FIELDS=("app_name" "package_id" "description")

# 可選欄位列表（optional 分組，含默認值，空字串表示無默認值）
declare -A OPTIONAL_FIELDS=(
    ["appimage_file"]=""
    ["appimage_url"]=""
    ["exec_command"]=""
    ["icon_url"]=""
    ["app_version"]=""
    ["base_id"]="org.deepin.base"
    ["base_version"]="25.2.2"
    ["runtime_id"]="org.deepin.runtime.dtk"
    ["runtime_version"]="25.2.2"
    ["linyaps_arch"]="x86_64"
    ["output_dir"]="./output"
)

# main 分組已知欄位
MAIN_KNOWN_FIELDS=("appimage_file" "appimage_url" "app_name" "package_id" "description" "icon_url" "exec_command")

# optional 分組已知欄位
OPTIONAL_KNOWN_FIELDS=("app_version" "base_id" "base_version"
    "runtime_id" "runtime_version" "linyaps_arch" "output_dir")

#=============================================================================
# 輔助函數
#=============================================================================

usage() {
    cat <<'EOF'
用法: parse_build_config.sh <config.json>

解析並驗證 appimage-linyaps 構建配置 JSON 文件。

JSON 結構：
  {
    "main": { ... },      ← 必填欄位
    "optional": { ... }   ← 可選欄位
  }

main（必填）：
  app_name       - 應用名稱
  package_id     - 玲瓏包 ID（反向域名格式）
  description    - 應用描述
  appimage_file  - AppImage 本地文件路徑（與 appimage_url 二選一）
  appimage_url   - AppImage 下載 URL（與 appimage_file 二選一）

main（可選）：
  exec_command   - 顯式指定 Exec 命令（跳過自動提取）
  icon_url       - icon 下載 URL

optional（可選）：
  app_version    - 版本號（默認：從文件名提取）
  base_id        - base 層 ID（默認：org.deepin.base）
  base_version   - base 層版本（默認：25.2.2）
  runtime_id     - runtime 層 ID（默認：org.deepin.runtime.dtk）
  runtime_version - runtime 層版本（默認：25.2.2）
  linyaps_arch   - 目標架構（默認：x86_64）
  output_dir     - 輸出目錄（默認：./output）

輸出格式：key=value，每行一個，可直接 eval 載入。
EOF
    exit 0
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_info() {
    echo "[INFO] $*" >&2
}

# 檢查 jq 是否可用
check_dependencies() {
    if ! command -v jq &>/dev/null; then
        log_error "缺少依賴：jq"
        log_error "請安裝 jq: sudo apt install jq / sudo dnf install jq"
        exit 1
    fi
}

# 驗證 JSON 文件格式
validate_json_format() {
    local json_file="$1"

    if [ ! -f "${json_file}" ]; then
        log_error "配置文件不存在: ${json_file}"
        exit 1
    fi

    if ! jq empty "${json_file}" 2>/dev/null; then
        log_error "配置文件不是有效的 JSON 格式: ${json_file}"
        exit 1
    fi
}

# 驗證頂層結構（必須包含 main 和 optional 對象）
validate_top_structure() {
    local json_file="$1"

    local main_type
    main_type=$(jq -r '.main | type' "${json_file}")
    if [ "${main_type}" != "object" ]; then
        log_error "缺少頂層 \"main\" 對象或類型不正確（當前: ${main_type}）"
        exit 1
    fi

    local optional_type
    optional_type=$(jq -r '.optional | type' "${json_file}")
    if [ "${optional_type}" != "object" ]; then
        log_error "缺少頂層 \"optional\" 對象或類型不正確（當前: ${optional_type}）"
        exit 1
    fi
}

# 驗證必填欄位（main 分組）
validate_required_fields() {
    local json_file="$1"
    local has_error=0

    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        value=$(jq -r ".main.${field}" "${json_file}")

        if [ "${value}" = "null" ] || [ -z "${value}" ]; then
            log_error "main 缺少必填欄位: ${field}"
            has_error=1
        fi
    done

    # 特殊驗證：appimage_file 或 appimage_url 至少需要一個
    local appimage_file
    appimage_file=$(jq -r '.main.appimage_file // empty' "${json_file}")
    local appimage_url
    appimage_url=$(jq -r '.main.appimage_url // empty' "${json_file}")

    if [ -z "${appimage_file}" ] && [ -z "${appimage_url}" ]; then
        log_error "main 中 appimage_file 和 appimage_url 至少需要提供一個"
        has_error=1
    fi

    if [ "${has_error}" -eq 1 ]; then
        log_error "請參考範例文件填寫 main 中的所有必填欄位"
        exit 1
    fi
}

# 檢測未知欄位（分別檢查 main 和 optional 分組）
check_unknown_fields() {
    local json_file="$1"

    # 檢查 main 分組
    local main_keys
    main_keys=$(jq -r '.main | keys[]' "${json_file}" 2>/dev/null)
    for key in ${main_keys}; do
        local is_known=0
        for known in "${MAIN_KNOWN_FIELDS[@]}"; do
            if [ "${key}" = "${known}" ]; then
                is_known=1
                break
            fi
        done
        if [ "${is_known}" -eq 0 ]; then
            log_warn "main 中檢測到未知欄位: ${key}（將被忽略）"
        fi
    done

    # 檢查 optional 分組
    local optional_keys
    optional_keys=$(jq -r '.optional | keys[]' "${json_file}" 2>/dev/null)
    for key in ${optional_keys}; do
        local is_known=0
        for known in "${OPTIONAL_KNOWN_FIELDS[@]}"; do
            if [ "${key}" = "${known}" ]; then
                is_known=1
                break
            fi
        done
        if [ "${is_known}" -eq 0 ]; then
            log_warn "optional 中檢測到未知欄位: ${key}（將被忽略）"
        fi
    done
}

# 驗證 URL 格式（簡單檢查）
validate_url() {
    local field_name="$1"
    local url="$2"

    case "${url}" in
        http://*|https://*|ftp://*)
            # URL 格式基本正確
            ;;
        /*)
            # 本地路徑也接受
            ;;
        *)
            log_warn "${field_name} 的值看起來不像有效的 URL 或路徑: ${url}"
            ;;
    esac
}

# 驗證欄位值
validate_field_values() {
    local json_file="$1"

    # 驗證 appimage_url（如果提供）
    local appimage_url
    appimage_url=$(jq -r '.main.appimage_url // empty' "${json_file}")
    if [ -n "${appimage_url}" ]; then
        validate_url "appimage_url" "${appimage_url}"
    fi

    # 驗證 appimage_file（如果提供）
    local appimage_file
    appimage_file=$(jq -r '.main.appimage_file // empty' "${json_file}")
    if [ -n "${appimage_file}" ]; then
        if [ ! -f "${appimage_file}" ]; then
            log_warn "appimage_file 指定的文件不存在: ${appimage_file}（將在構建時驗證）"
        fi
    fi

    # 驗證 icon_url
    local icon_url
    icon_url=$(jq -r '.main.icon_url // empty' "${json_file}")
    if [ -n "${icon_url}" ]; then
        validate_url "icon_url" "${icon_url}"
    fi

    # 驗證 app_name（不允許為空字串或純空白）
    local app_name
    app_name=$(jq -r '.main.app_name' "${json_file}")
    if [[ "${app_name}" =~ ^[[:space:]]*$ ]]; then
        log_error "app_name 不能為空或純空白"
        exit 1
    fi

    # 驗證 description（不允許為空字串或純空白）
    local description
    description=$(jq -r '.main.description' "${json_file}")
    if [[ "${description}" =~ ^[[:space:]]*$ ]]; then
        log_error "description 不能為空或純空白"
        exit 1
    fi
}

# 輸出解析結果（扁平 key=value 格式，去掉分組前綴）
output_results() {
    local json_file="$1"

    # 輸出 main 欄位（必填）
    for field in "${REQUIRED_FIELDS[@]}"; do
        local value
        value=$(jq -r ".main.${field}" "${json_file}")
        echo "${field}=${value}"
    done

    # 輸出 appimage_file 和 appimage_url（如果提供）
    local appimage_file
    appimage_file=$(jq -r '.main.appimage_file // empty' "${json_file}")
    if [ -n "${appimage_file}" ]; then
        echo "appimage_file=${appimage_file}"
    fi

    local appimage_url
    appimage_url=$(jq -r '.main.appimage_url // empty' "${json_file}")
    if [ -n "${appimage_url}" ]; then
        echo "appimage_url=${appimage_url}"
    fi

    # 輸出 exec_command（如果提供）
    local exec_command
    exec_command=$(jq -r '.main.exec_command // empty' "${json_file}")
    if [ -n "${exec_command}" ]; then
        echo "exec_command=${exec_command}"
    fi

    # 輸出 icon_url（如果提供）
    local icon_url
    icon_url=$(jq -r '.main.icon_url // empty' "${json_file}")
    if [ -n "${icon_url}" ]; then
        echo "icon_url=${icon_url}"
    fi

    # 輸出 optional 欄位（JSON 中有值則使用，否則使用默認值）
    for field in "${!OPTIONAL_FIELDS[@]}"; do
        # 跳過已在 main 中處理的欄位
        case "${field}" in
            appimage_file|appimage_url|exec_command|icon_url)
                continue
                ;;
        esac

        local value
        value=$(jq -r ".optional.${field}" "${json_file}")

        if [ "${value}" = "null" ] || [ -z "${value}" ]; then
            value="${OPTIONAL_FIELDS[${field}]}"
        fi

        # 只輸出有值的欄位
        if [ -n "${value}" ]; then
            echo "${field}=${value}"
        fi
    done
}

#=============================================================================
# 主流程
#=============================================================================

main() {
    # 處理幫助參數
    if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
        usage
    fi

    local config_file="$1"

    log_info "解析配置文件: ${config_file}"

    # 1. 檢查依賴
    check_dependencies

    # 2. 驗證 JSON 格式
    validate_json_format "${config_file}"

    # 3. 驗證頂層結構（main + optional）
    validate_top_structure "${config_file}"

    # 4. 檢測未知欄位
    check_unknown_fields "${config_file}"

    # 5. 驗證必填欄位（main 分組）
    validate_required_fields "${config_file}"

    # 6. 驗證欄位值
    validate_field_values "${config_file}"

    log_info "配置驗證通過"

    # 7. 輸出解析結果
    output_results "${config_file}"
}

main "$@"
