#!/bin/bash
# 批量初始化玲珑打包工程
# 用法: ./batch_init.sh <task.csv|task.json> [options]
#
# 支持格式:
#   CSV: 包名,架构,版本,下载地址,...
#   JSON: { "tasks": [{ "pkgName": "...", "arch": "...", "orig_version": "...", "src_url": "..." }] }
#
# 选项:
#   --projects_root=<path>   项目根目录 (默认: ./projects)
#   --template-dir=<path>    模板目录 (默认: skills/linglong-project-gen/templates)
#   --config=<config.json>   JSON 配置文件 (仅含 global 部分)
#   --output=<file.json>     输出 JSON 文件 (默认: /tmp/linyaps_tasks_<timestamp>.json)
#   --dry-run                仅生成项目结构，不执行打包
#   --help                   显示说明

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================
# 颜色定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_err()   { echo -e "${RED}[ERROR]${NC} $*"; }

# ============================================================
# 默认配置
# ============================================================
DEFAULT_PROJECTS_ROOT="./projects"
DEFAULT_TEMPLATE_DIR="${WORKSPACE_ROOT}/skills/linglong-project-gen/templates"

# ============================================================
# 使用说明
# ============================================================
show_help() {
    cat <<'HELP'
批量初始化玲珑打包工程

用法:
  ./batch_init.sh <task.csv|task.json> [options]

CSV 字段映射:
  包名        → pkgName
  架构        → arch
  版本        → orig_version (可选，为空时从 URL 自动提取)
  下载地址    → src_url

选项:
  --projects_root=<path>   项目根目录 (默认: ./projects)
  --template-dir=<path>    模板目录 (默认: skills/linglong-project-gen/templates)
  --config=<config.json>   JSON 配置文件 (仅含 global 部分)
  --output=<file.json>     输出 JSON 文件 (默认: /tmp/linyaps_tasks_<timestamp>.json)
  --dry-run                仅生成项目结构，不执行打包
  --help                   显示此说明

示例:
  # 使用 CSV 批量初始化
  ./batch_init.sh tasks.csv

  # 指定项目根目录
  ./batch_init.sh tasks.csv --projects_root=/path/to/projects

  # 使用 JSON 任务文件
  ./batch_init.sh task.json

  # 仅生成项目结构，不执行打包
  ./batch_init.sh tasks.csv --dry-run
HELP
}

# ============================================================
# 解析命令行参数
# ============================================================
INPUT_FILE=""
PROJECTS_ROOT="$DEFAULT_PROJECTS_ROOT"
TEMPLATE_DIR="$DEFAULT_TEMPLATE_DIR"
CONFIG_FILE=""
OUTPUT_JSON=""
DRY_RUN=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --help|-h)
                show_help
                exit 0
                ;;
            --projects_root=*)
                PROJECTS_ROOT="${1#*=}"
                ;;
            --template-dir=*)
                TEMPLATE_DIR="${1#*=}"
                ;;
            --config=*)
                CONFIG_FILE="${1#*=}"
                ;;
            --output=*)
                OUTPUT_JSON="${1#*=}"
                ;;
            --dry-run)
                DRY_RUN=true
                ;;
            -*)
                log_err "未知选项: $1"
                show_help
                exit 1
                ;;
            *)
                if [[ -z "$INPUT_FILE" ]]; then
                    INPUT_FILE="$1"
                else
                    log_err "过多参数: $1"
                    show_help
                    exit 1
                fi
                ;;
        esac
        shift
    done

    if [[ -z "$INPUT_FILE" ]]; then
        log_err "缺少输入文件"
        show_help
        exit 1
    fi

    if [[ ! -f "$INPUT_FILE" ]]; then
        log_err "文件不存在: $INPUT_FILE"
        exit 1
    fi
}

# ============================================================
# 检测文件类型
# ============================================================
detect_file_type() {
    local file="$1"
    local ext="${file##*.}"
    case "${ext,,}" in
        csv)  echo "csv" ;;
        json) echo "json" ;;
        *)
            # 尝试从内容检测
            local first_line
            first_line=$(head -1 "$file" | tr -d '[:space:]')
            if [[ "$first_line" == "{"* ]]; then
                echo "json"
            else
                echo "csv"
            fi
            ;;
    esac
}

# ============================================================
# 从 JSON 配置文件读取 global 设定
# ============================================================
load_config() {
    local config_file="$1"
    if [[ ! -f "$config_file" ]]; then
        log_err "配置文件不存在: $config_file"
        exit 1
    fi

    local result
    result=$(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
g = data.get('global', {})
print('PROJECTS_ROOT=' + json.dumps(g.get('projects_root', '')))
" "$config_file" 2>/dev/null) || {
        log_err "配置文件格式错误: $config_file"
        exit 1
    }

    eval "$result"

    # 仅在配置文件有值时覆盖默认值
    [[ -n "$PROJECTS_ROOT" && "$PROJECTS_ROOT" != '""' ]] || PROJECTS_ROOT="$DEFAULT_PROJECTS_ROOT"
}

# ============================================================
# CSV 转 JSON
# ============================================================
csv_to_json() {
    local csv_file="$1"
    local projects_root="$2"

    python3 -c "
import csv, json, sys

csv_file = sys.argv[1]
projects_root = sys.argv[2]

# 读取 CSV
rows = []
with open(csv_file, 'r', encoding='utf-8') as f:
    reader = csv.DictReader(f)
    for row in reader:
        # 清理所有字段的空白和 tab
        cleaned = {}
        for k, v in row.items():
            if k is not None:
                cleaned[k.strip()] = v.strip() if v else ''
        rows.append(cleaned)

# 验证必要字段 (支持简体/繁体中文表头)
col_aliases = {
    '包名': ['包名'],
    '下载地址': ['下载地址', '下載地址', 'download_url', 'src_url'],
    '架构': ['架构', '架構', 'arch'],
    '版本': ['版本', 'version'],
}
def find_col(row_keys, aliases):
    for alias in aliases:
        if alias in row_keys:
            return alias
    return None

header = list(rows[0].keys()) if rows else []
download_col = find_col(header, col_aliases['下载地址'])
arch_col = find_col(header, col_aliases['架构'])
pkg_col = find_col(header, col_aliases['包名'])

missing = []
if not pkg_col: missing.append('包名')
if not download_col: missing.append('下载地址')
if not arch_col: missing.append('架构')
if missing:
    print(f'错误: CSV 缺少必要字段: {missing}', file=sys.stderr)
    print(f'实际字段: {header}', file=sys.stderr)
    sys.exit(1)

version_col = find_col(header, col_aliases['版本'])

# 映射字段
tasks = []
for row in rows:
    pkg_name = row.get(pkg_col, '').strip()
    src_url = row.get(download_col, '').strip()
    arch = row.get(arch_col, '').strip()
    orig_version = row.get(version_col, '').strip() if version_col else ''

    # 跳过空行或缺少必要字段的行
    if not pkg_name or not src_url:
        continue

    task = {
        'pkgName': pkg_name,
        'src_url': src_url,
        'arch': arch,
    }
    # 仅在有版本号时加入
    if orig_version:
        task['orig_version'] = orig_version
    else:
        task['orig_version'] = ''

    tasks.append(task)

# 组装完整 JSON
result = {
    'global': {
        'projects_root': projects_root,
    },
    'tasks': tasks
}

print(json.dumps(result, indent=2, ensure_ascii=False))
" "$csv_file" "$projects_root"
}

# ============================================================
# 直接传递 JSON 任务文件
# ============================================================
pass_through_json() {
    local json_file="$1"
    log_info "检测到 JSON 格式，直接读取任务"
    cat "$json_file"
}

# ============================================================
# 创建项目目录结构
# ============================================================
create_project_structure() {
    local pkg_name="$1"
    local arch="$2"
    local orig_version="$3"
    local src_url="$4"
    local projects_root="$5"
    local template_dir="$6"

    local project_dir="${projects_root}/CI_ll_${pkg_name}"

    log_info "创建项目目录: $project_dir"

    # 创建目录结构
    mkdir -p "${project_dir}/templates/files_res"
    mkdir -p "${project_dir}/scripts"
    mkdir -p "${project_dir}/config"

    # 拷贝辅助脚本
    if [[ -f "${WORKSPACE_ROOT}/skills/linglong-project-gen/scripts/handle_special_paths.sh" ]]; then
        cp "${WORKSPACE_ROOT}/skills/linglong-project-gen/scripts/handle_special_paths.sh" "${project_dir}/scripts/"
        chmod +x "${project_dir}/scripts/handle_special_paths.sh"
    fi

    # 拷贝白名单配置文件
    if [[ -f "${WORKSPACE_ROOT}/skills/config/base_runtime_whitelist.conf" ]]; then
        cp "${WORKSPACE_ROOT}/skills/config/base_runtime_whitelist.conf" "${project_dir}/config/"
        log_info "已拷贝全局白名单配置到工程目录"
    elif [[ -f "${WORKSPACE_ROOT}/skills/linglong-project-gen/config/base_runtime_whitelist.conf" ]]; then
        cp "${WORKSPACE_ROOT}/skills/linglong-project-gen/config/base_runtime_whitelist.conf" "${project_dir}/config/"
        log_info "已拷贝 skill 级别白名单配置到工程目录"
    fi

    # 生成 linglong.yaml
    generate_linglong_yaml "$pkg_name" "$arch" "$orig_version" "$project_dir" "$template_dir"

    # 生成 pak_linyaps.sh
    generate_pak_linyaps "$pkg_name" "$arch" "$orig_version" "$project_dir" "$template_dir"

    log_ok "项目创建完成: $project_dir"
}

# ============================================================
# 生成 linglong.yaml
# ============================================================
generate_linglong_yaml() {
    local pkg_name="$1"
    local arch="$2"
    local orig_version="$3"
    local project_dir="$4"
    local template_dir="$5"

    local template_file="${template_dir}/linglong.yaml"
    local output_file="${project_dir}/linglong.yaml"

    if [[ ! -f "$template_file" ]]; then
        log_warn "模板文件不存在: $template_file，跳过 linglong.yaml 生成"
        return
    fi

    # 使用模板生成 linglong.yaml
    sed -e "s|\${package_id}|${pkg_name}|g" \
        -e "s|\${app_name}|${pkg_name}|g" \
        -e "s|\${ll_version}|${orig_version}|g" \
        -e "s|\${linyaps_arch}|${arch}|g" \
        -e "s|\${ll_architecture}|${arch}|g" \
        "$template_file" > "$output_file"

    log_info "已生成: $output_file"
}

# ============================================================
# 生成 pak_linyaps.sh
# ============================================================
generate_pak_linyaps() {
    local pkg_name="$1"
    local arch="$2"
    local orig_version="$3"
    local project_dir="$4"
    local template_dir="$5"

    local template_file="${template_dir}/pak_linyaps.sh"
    local output_file="${project_dir}/pak_linyaps.sh"

    if [[ ! -f "$template_file" ]]; then
        log_warn "模板文件不存在: $template_file，跳过 pak_linyaps.sh 生成"
        return
    fi

    # 拷贝模板脚本
    cp "$template_file" "$output_file"
    chmod +x "$output_file"

    log_info "已生成: $output_file"
}

# ============================================================
# 主流程
# ============================================================
main() {
    parse_args "$@"

    # 检测文件类型
    local file_type
    file_type=$(detect_file_type "$INPUT_FILE")
    log_info "文件类型: $file_type"
    log_info "输入文件: $INPUT_FILE"

    # 如果指定了配置文件，加载配置
    if [[ -n "$CONFIG_FILE" ]]; then
        log_info "加载配置文件: $CONFIG_FILE"
        load_config "$CONFIG_FILE"
    fi

    log_info "配置:"
    log_info "  projects_root: $PROJECTS_ROOT"
    log_info "  template_dir:  $TEMPLATE_DIR"

    # 检查模板目录
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        log_err "模板目录不存在: $TEMPLATE_DIR"
        exit 1
    fi

    # 解析输入文件
    local json_content
    if [[ "$file_type" == "json" ]]; then
        json_content=$(pass_through_json "$INPUT_FILE")
    else
        # CSV 转 JSON
        log_info "解析 CSV 文件..."
        json_content=$(csv_to_json "$INPUT_FILE" "$PROJECTS_ROOT") || {
            log_err "CSV 解析失败"
            exit 1
        }
    fi

    # 统计任务数
    local task_count
    task_count=$(echo "$json_content" | python3 -c "import json,sys; print(len(json.load(sys.stdin).get('tasks',[])))")
    log_ok "解析完成，共 $task_count 个任务"

    # 确定输出文件路径
    if [[ -z "$OUTPUT_JSON" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d%H%M%S)
        OUTPUT_JSON="/tmp/linyaps_tasks_${timestamp}.json"
    fi

    # 写入 JSON 文件
    echo "$json_content" > "$OUTPUT_JSON"
    log_ok "已生成 JSON 文件: $OUTPUT_JSON"

    # dry-run 模式：仅输出 JSON 内容
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "=== dry-run 模式：生成的 JSON 内容 ==="
        echo "$json_content"
        return
    fi

    # 创建项目目录
    log_info "开始创建项目目录..."

    local success_count=0
    local fail_count=0

    # 使用 python 解析 JSON 并创建项目
    python3 -c "
import json, sys

with open(sys.argv[1]) as f:
    data = json.load(f)

projects_root = data.get('global', {}).get('projects_root', './projects')
tasks = data.get('tasks', [])

for i, task in enumerate(tasks):
    pkg_name = task.get('pkgName', '')
    arch = task.get('arch', '')
    orig_version = task.get('orig_version', '')
    src_url = task.get('src_url', '')

    if not pkg_name:
        print(f'警告: 任务 {i+1} 缺少包名，跳过', file=sys.stderr)
        continue

    print(f'{pkg_name}|{arch}|{orig_version}|{src_url}')
" "$OUTPUT_JSON" | while IFS='|' read -r pkg_name arch orig_version src_url; do
        # 创建项目
        if create_project_structure "$pkg_name" "$arch" "$orig_version" "$src_url" "$PROJECTS_ROOT" "$TEMPLATE_DIR"; then
            success_count=$((success_count + 1))
        else
            fail_count=$((fail_count + 1))
        fi
    done

    # 输出结果统计
    echo ""
    log_info "=========================================="
    log_info "批量初始化完成"
    log_info "=========================================="
    log_ok "所有项目初始化完成！"
}

main "$@"
