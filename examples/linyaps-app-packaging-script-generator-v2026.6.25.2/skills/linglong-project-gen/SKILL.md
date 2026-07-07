---
name: linglong-project-gen
description: >
  根据deb包信息和CSV配置，生成完整的玲珑打包工程，包括 linglong.yaml 配置文件和 pak_linyaps.sh 打包脚本。
user-invocable: false
---

# 玲珑工程生成

## 功能说明

根据deb包信息和CSV配置，生成完整的玲珑打包工程，包括 `linglong.yaml` 配置文件和 `pak_linyaps.sh` 打包脚本。

## 触发场景

- 需要为deb包创建玲珑打包工程
- 需要生成linglong.yaml配置文件
- 需要生成自动化打包脚本
- 批量创建多个应用的打包工程

## 批量初始化

使用 `batch_init.sh` 脚本可以批量创建多个应用的打包工程：

```bash
# CSV 格式批量初始化
./scripts/batch_init.sh tasks.csv --projects_root=./projects

# JSON 格式批量初始化
./scripts/batch_init.sh task.json --projects_root=./projects

# 仅生成项目结构，不执行打包
./scripts/batch_init.sh tasks.csv --dry-run
```

**CSV 格式示例**：
```csv
包名,架构,版本,下载地址
com.example.app,x86_64,1.0.0,https://example.com/app.deb
```

**JSON 格式示例**：
```json
{
  "global": {
    "projects_root": "./projects"
  },
  "tasks": [
    {
      "pkgName": "com.example.app",
      "arch": "x86_64",
      "orig_version": "1.0.0",
      "src_url": "https://example.com/app.deb"
    }
  ]
}
```

批量初始化会为每个任务创建 `CI_ll_<pkgName>` 目录，包含：
- `linglong.yaml` - 玲珑打包配置文件
- `pak_linyaps.sh` - 自动化打包脚本
- `scripts/` - 辅助脚本目录
- `config/` - 配置文件目录（含白名单配置）
- `templates/files_res/` - 资源文件目录

## 工作流程

### 1. 准备工程目录

工程目录命名规范：`CI_ll_<package_id>`

```bash
# 例如: com.visualstudio.code -> CI_ll_com.visualstudio.code
project_dir="CI_ll_${package_id}"
mkdir -p "${project_dir}/templates/files_res"
mkdir -p "${project_dir}/scripts"
mkdir -p "${project_dir}/config"

# 拷贝辅助脚本
cp "scripts/handle_special_paths.sh" "${project_dir}/scripts/"
chmod +x "${project_dir}/scripts/handle_special_paths.sh"

# 拷贝白名单配置文件（优先使用全局白名单）
if [ -f "${skill_root}/../config/base_runtime_whitelist.conf" ]; then
  cp "${skill_root}/../config/base_runtime_whitelist.conf" "${project_dir}/config/"
  echo "已拷貝全局白名單配置到工程目錄"
else
  cp "${skill_root}/config/base_runtime_whitelist.conf" "${project_dir}/config/"
  echo "已拷貝 skill 級別白名單配置到工程目錄（全局白名單不存在，使用本地副本）"
fi
# 注意：不创建 src/ 目录，deb文件路径由用户执行脚本时指定
```

**重要：验证 package_id**

在创建工程目录后，应验证 package_id 格式和一致性：

```bash
# 验证工程目录命名和 package_id 格式
"${skill_root}/../linglong-fix/scripts/validate_package_id.sh" "${project_dir}"

# 如果验证失败，使用修复脚本
"${skill_root}/../linglong-fix/scripts/fix_package_id.sh" "${project_dir}" --new-id "${package_id}"
```

**package_id 格式规范：**
- 格式：反向域名格式（如 `com.example.app`）
- 字符：小写字母、数字、下划线、点
- 结构：至少两个点分隔的部分
- 长度：最大255字符

**deb 文件存储路径：**
- 正确格式：`<package_id>/xxx.deb`
- 示例：`com.visualstudio.code/code_1.85.0_amd64.deb`

### 2. 生成 linglong.yaml

基于 `scripts/templates/` 目录下的模板生成，使用变量替换：

```bash
# 模板目录结构
# scripts/templates/
#   ├── linglong.yaml
#   └── files_res/
#       ├── share/applications/
#       ├── share/icons/
#       └── ...
```

```yaml
# templates/linglong.yaml
version: "${ll_version}"

package:
  id: ${package_id}
  name: "${app_name}"
  version: ${ll_version}
  kind: app
  architecture: ${ll_architecture}
  description: |
    ${description}

base: ""
runtime: ""

buildext:
  apt:
    depends:
      - ${depends}

command:
  - "${command}"

build: |
  # files/ 映射到 /usr/ 目录
  # binary/ 的内容直接对应 $prefix/ (files/)
  # pak_linyaps.sh 已处理路径转换和软链
  cp -rf /project/binary/* ${prefix}/

  # 复制桌面文件、图标等资源
  cp -rf /project/files_res/* ${prefix}/

  # 創建玲瓏構建標識文件
  touch ${prefix}/.linyaps_genius
```

### 2.5. 驗證 base/runtime 白名單（重要）

**在生成 pak_linyaps.sh 之前，必須驗證 base/runtime 組合是否在白名單中。如果組合不在白名單中，應阻止任務並提示用戶。**

**白名單配置文件查找優先級（本地優先全局）：**
1. CLI 參數 `--whitelist` 指定的路徑
2. 環境變量 `LINGLONG_WHITELIST_FILE` 指定的路徑
3. 工程目錄下 `config/base_runtime_whitelist.conf`
4. 腳本所在目錄的 `config/base_runtime_whitelist.conf`（skill 級別）
5. **skills 全局目錄** `config/base_runtime_whitelist.conf`（全局聲明，推薦維護）⭐

```bash
# 白名單配置文件路徑（按優先級查找）
whitelist_file=""

# 1. CLI 參數
if [ -n "${whitelist_file}" ] && [ -f "${whitelist_file}" ]; then
  : # 已指定
# 2. 環境變量
elif [ -n "${LINGLONG_WHITELIST_FILE}" ] && [ -f "${LINGLONG_WHITELIST_FILE}" ]; then
  whitelist_file="${LINGLONG_WHITELIST_FILE}"
# 3. 工程目錄
elif [ -f "${project_dir}/config/base_runtime_whitelist.conf" ]; then
  whitelist_file="${project_dir}/config/base_runtime_whitelist.conf"
# 4. skill 級別
elif [ -f "${skill_root}/config/base_runtime_whitelist.conf" ]; then
  whitelist_file="${skill_root}/config/base_runtime_whitelist.conf"
# 5. 全局目錄（推薦）
elif [ -f "${skill_root}/../config/base_runtime_whitelist.conf" ]; then
  whitelist_file="${skill_root}/../config/base_runtime_whitelist.conf"
fi

if [ -z "${whitelist_file}" ]; then
  echo "警告: 未找到白名單配置文件，跳過白名單驗證" >&2
  echo "  可在以下位置放置白名單：" >&2
  echo "    - ${project_dir}/config/base_runtime_whitelist.conf（工程級別）" >&2
  echo "    - ${skill_root}/config/base_runtime_whitelist.conf（skill 級別）" >&2
  echo "    - ${skill_root}/../config/base_runtime_whitelist.conf（全局）" >&2
else
  # 在白名單中查找
  found=0
  while IFS= read -r line; do
    # 跳過注釋和空行
    [[ "${line}" =~ ^[[:space:]]*# ]] && continue
    [[ "${line}" =~ ^[[:space:]]*$ ]] && continue
    
    # 提取前兩個字段
    read -r wl_base wl_runtime _ <<<"${line}"
    
    # 精確匹配
    if [ "${wl_base}" = "${base_id}/${base_version}" ] && \
       [ "${wl_runtime}" = "${runtime_id}/${runtime_version}" ]; then
      found=1
      break
    fi
  done < "${whitelist_file}"

  if [ "${found}" -eq 0 ]; then
    echo "錯誤: base/runtime 組合不在白名單中，任務被阻止！" >&2
    echo "  當前組合: ${base_id}/${base_version} + ${runtime_id}/${runtime_version}" >&2
    echo "  白名單文件: ${whitelist_file}" >&2
    echo "  如需使用此組合，請先在白名單中添加（推薦修改全局白名單：skills/config/base_runtime_whitelist.conf）" >&2
    exit 1
  fi

  echo "白名單驗證通過: ${base_id}/${base_version} + ${runtime_id}/${runtime_version}"
fi
```

**白名單配置文件格式 (`config/base_runtime_whitelist.conf`)：**

```
# 格式：<base_id>/<base_version> <runtime_id>/<runtime_version> <描述>
# runtime_id 可為 "-" 表示無需 runtime

# Qt6/DTK6 應用（推薦）
org.deepin.base/25.2.2	org.deepin.runtime.dtk/25.2.2	Qt6/DTK6 應用（推薦默認）

# Qt6 WebEngine 應用
org.deepin.base/25.2.2	org.deepin.runtime.webengine/25.2.2	Qt6 WebEngine 應用

# 純 base 應用（無 runtime）
org.deepin.base/25.2.2	-	純 base 應用
```

**重要：**
- 白名單驗證是**強制性的**，不在白名單中的組合會阻止任務
- 這確保了生成的 pak_linyaps.sh 使用經過驗證的 base/runtime 組合
- **推薦維護全局白名單**（`skills/config/base_runtime_whitelist.conf`），所有 skill 和工程共享
- 如需添加新組合，請優先在全局白名單中添加，生成工程時會自動同步到工程目錄

### 3. 生成 pak_linyaps.sh

参考 `CI_ll_com.visualstudio.code/pak_linyaps.sh` 模板：

```bash
#!/bin/bash
set -x

ll_id="${package_id}"

# Options
auto_clean=""
auto_push="${push}"  # 从CSV配置读取

repo_name="nightly"
repo_url="https://repo-dev.cicd.getdeepin.org"
push_account_user=""
push_account_passwd=""

init_global_data() {
  ARCH=$(uname -m)
  origin_version=""
  ll_version=""
  binary_arch=""
  linyaps_arch=""
  src_path=""
  output_dir=""
  build_tmp_dir=""

  project_root="$(dirname "$(readlink -f "$0")")"
  default_output_dir="${project_root}/bins"

  # 解析命令行参数
  COMMANDLINE="$@"
  for COMMAND in $COMMANDLINE; do
      key=$(echo $COMMAND | awk -F"=" '{print $1}')
      val=$(echo $COMMAND | awk -F"=" '{print $2}')
      case $key in
          --linyaps_arch) linyaps_arch="$val" ;;
          --origin_version) origin_version="$val" ;;
          --ll_version) ll_version="$val" ;;
          --src_path) src_path="$val" ;;
          --output_dir) output_dir="$val" ;;
          --build_tmp_dir) build_tmp_dir="$val" ;;
      esac
  done
  
  # 初始化构建缓存目录
  if [ -z "${build_tmp_dir}" ]; then
    # 未指定时使用临时目录
    build_tmp_dir=$(mktemp -d)
  else
    # 用户指定了目录，转换为绝对路径并创建（如不存在）
    build_tmp_dir=$(readlink -f "${build_tmp_dir}")
    if [ ! -d "${build_tmp_dir}" ]; then
      mkdir -p "${build_tmp_dir}" || {
        echo "错误: 无法创建构建缓存目录: ${build_tmp_dir}" >&2
        exit 1
      }
    fi
  fi

  # 架构映射
  case "${linyaps_arch}" in
    "x86_64")
      binary_arch="amd64"
      base_id="${base_id}"
      base_version="${base_version}"
      runtime_id="${runtime_id}"
      runtime_version="${runtime_version}"
      ;;
    "arm64")
      binary_arch="arm64"
      base_id="${base_id}"
      base_version="${base_version}"
      runtime_id="${runtime_id}"
      runtime_version="${runtime_version}"
      ;;
    *)
      echo "Unsupported architecture: ${linyaps_arch}"
      exit 1
      ;;
  esac
}

# ... 其他函数 (validate_version_format, generate_version_from_origin, etc.)

build_dir_init() {
  mkdir -p "${build_tmp_dir}/binary"
  cd "${build_tmp_dir}"
  cp -rf "${project_root}/templates/files_res" "${build_tmp_dir}"

  export prefix="\$PREFIX"
  export ll_version=${ll_version}
  # base/runtime 由 build_pak() 透過 sed 延遲注入
  export linyaps_arch=${linyaps_arch}

  cat "${project_root}/templates/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"
}

build_pak() {
  binary_tmp_dir="${build_tmp_dir}/tmp"
  binary_dir="${build_tmp_dir}/binary/"

  # 解压deb包
  dpkg -x "${src_path}" "${binary_tmp_dir}/"
  
  # 创建binary目录结构
  # binary/ 目录的内容会复制到 files/ 根目录
  # files/ 映射到 /usr/，所以 files/bin/ -> /usr/bin/
  mkdir -p "${binary_dir}"
  
  # 调用特殊路径处理脚本
  # 处理 deb 中的文件路径转换，包括：
  # 1. /usr/ 下的内容直接复制到 binary/ (对应 files/)
  # 2. 非 /usr 标准路径（如 /opt/uTools/）直接放到 binary/ 下作为未归类目录
  #    例如：/opt/uTools/ -> binary/uTools/ (去掉 opt/ 层级)
  # 3. 支持包含空格、括号、中文、&、@、#、$ 等特殊字符的路径
  # 注意：此操作必须在所有软链动作之前完成，否则软链关系将被破坏
  "${project_root}/scripts/handle_special_paths.sh" "${binary_tmp_dir}" "${binary_dir}"
  
  # 创建 bin/ 目录用于存放可执行文件软链
  # 注意：此操作必须在特殊路径处理完成之后进行
  mkdir -p "${binary_dir}/bin"
  
  # 处理二进制文件软链
  # 在 files/bin/ 创建软链，指向实际二进制文件
  # 注意：此操作必须在所有文件复制和路径处理完成之后进行
  if [ -n "${binary_name}" ]; then
    # 在 binary/ 目录下查找二进制文件
    actual_binary=$(find "${binary_dir}" -type f -name "${binary_name}" -executable 2>/dev/null | head -n 1)
    
    if [ -n "${actual_binary}" ]; then
      rel_binary="${actual_binary#${binary_dir}}"
      
      cd "${binary_dir}/bin"
      ln -sf "../${rel_binary}" "${binary_name}"
      cd "${build_tmp_dir}"
    fi
  fi

  # 創建玲瓏構建標識文件
  # binary/ 目錄對應 linglong.yaml 中的 ${prefix}
  # 此文件用於標識由 linyaps 系統生成的構建產物
  touch "${binary_dir}/.linyaps_genius"
  echo "Created identity file: ${binary_dir}/.linyaps_genius"

  ll-builder build --skip-output-check
  building_status=$?
  if [ "${building_status}" = "0" ]; then
    echo "Building success!"
  else
    echo "Building failed!"
    exit 1
  fi
  ll-builder export --no-develop --layer

  binary_layer=$(find "${build_tmp_dir}" -type f -name "*binary.layer")
  if [ -z ${binary_layer} ]; then
    echo "Failed to build paks!"
    exit 1
  else
    mv "${binary_layer}" "${output_dir}"
  fi
}

main() {
    init_global_data "$@"
    data_regroup_check
    build_dir_init
    build_pak

    if [[ -n "${auto_push}" && ("${auto_push}" =~ ^[Tt][Rr][Uu][Ee]$) ]]; then
      push_dev
    fi

    if [ -z "${auto_clean}" ] || [ "${auto_clean}" = "TRUE" ]; then
      rm -rf "${build_tmp_dir}"
    fi
}

main "$@"
exit 0
```

### 4. CSV配置填充

从CSV读取配置并填充到模板：

```python
import csv

with open('config/packages.csv', 'r') as f:
    reader = csv.DictReader(f)
    for row in reader:
        config = {
            'package_name': row['package_name'],
            'deb_path': row['deb_path'],
            'architecture': row['architecture'],
            'base': row['base'],
            'runtime': row['runtime'],
            'push': row['push']
        }
        # 使用config填充模板
```

## 模板变量说明

| 变量 | 来源 | 说明 |
|-----|------|------|
| `${package_id}` | deb包名转换 | 玲珑包ID，如 com.visualstudio.code |
| `${app_name}` | deb Description | 应用名称 |
| `${ll_version}` | 版本转换 | 玲珑格式版本 (x.x.x.x) |
| `${ll_architecture}` | 架构映射 | x86_64/aarch64 |
| `${base}` | — | 已廢棄，模板使用空佔位符，由 build_pak() 透過 sed 延遲注入 |
| `${runtime}` | — | 已廢棄，模板使用空佔位符，由 build_pak() 透過 sed 延遲注入 |
| `${push}` | CSV配置 | 是否自动推送 |
| `${command}` | desktop Exec | 启动命令（⚠️ 占位符，由 pak_linyaps.sh 动态设置） |
| `${depends}` | deb Depends | 运行时依赖 |
| `${binary_name}` | CSV配置 | 二进制文件名（如 `utools`），用于创建 wrapper 脚本 |

**binary_path 最佳实践：**
- `binary_path` 已废弃，新版本自动保持 deb 原有目录结构
- deb 中的 `/opt/uTools/` → `files/opt/uTools/`
- deb 中的 `/usr/share/code/` → `files/usr/share/code/`
- 二进制软链自动创建在 `files/bin/`，指向实际二进制文件

## 命令行参数说明

| 参数 | 必填 | 说明 |
|-----|------|------|
| `--src_path` | 是 | deb包完整路径 |
| `--output_dir` | 是 | 输出目录 |
| `--ll_version` | 二选一 | 玲珑格式版本 (x.x.x.x) |
| `--origin_version` | 二选一 | 原始版本号（自动转换为玲珑格式） |
| `--linyaps_arch` | 否 | 目标架构 (x86_64/arm64)，默认当前系统架构 |
| `--build_tmp_dir` | 否 | 构建缓存目录，未指定时使用临时目录 |
| `--base_id` | 否 | 基础运行时ID（如 org.deepin.base），默认使用白名单中推荐的组合 |
| `--base_version` | 否 | 基础运行时版本（如 25.2.2） |
| `--runtime_id` | 否 | 应用运行时ID（如 org.deepin.runtime.dtk） |
| `--runtime_version` | 否 | 应用运行时版本（如 25.2.2） |
| `--whitelist` | 否 | 白名单配置文件路径，未指定时按优先级自动查找（工程→skill→全局） |

**注意：**
- `${command}` 在模板中为占位符，实际值由 `pak_linyaps.sh` 在构建时通过 wrapper 机制动态设置
- 二进制文件由 `pak_linyaps.sh` 在构建时创建 wrapper 脚本到 `${prefix}/bin/`
- **禁止手动修改 linglong.yaml 的 command 字段**，由 wrapper 机制自动处理

## Wrapper 机制说明

`pak_linyaps.sh` 在构建时会自动创建 wrapper 脚本，确保应用正确启动：

### Wrapper 工作流程

1. **自动提取 binary_name**：从 desktop 文件的 Exec 字段提取二进制名称
2. **查找实际二进制**：在 `binary/` 目录下查找实际的可执行文件
3. **创建 wrapper 脚本**：在 `bin/` 目录创建 `${binary_name}.wrapper` 脚本
4. **更新 linglong.yaml**：自动将 `command` 字段设置为 wrapper 路径
5. **更新 desktop 文件**：自动将 `Exec=` 字段更新为 wrapper 路径

### Wrapper 脚本示例

```bash
#!/bin/bash
# Wrapper script generated by pak_linyaps.sh
# This wrapper ensures scripts using 'dirname $0' work correctly
script_dir="$(cd "$(dirname "$0")" && pwd)"
exec "${script_dir}/../uTools/utools" "$@"
```

### 为什么需要 Wrapper

1. **路径解析问题**：许多应用使用 `dirname $0` 来定位资源文件，软链会导致路径解析错误
2. **相对路径支持**：wrapper 通过 `cd + pwd` 解析绝对路径，确保 `$PATH` 执行时也能正确工作
3. **自动化处理**：无需手动修改 desktop 文件和 linglong.yaml，减少错误

### ⚠️ Agent 注意事项

**LLM Agent 在生成工程时必须遵守以下规则：**

1. **禁止手动设置 command 字段**：linglong.yaml 模板中的 `${command}` 为占位符
2. **禁止手动设置 base/runtime 字段**：模板中 `base: ""`, `runtime: ""` 为空占位符，由 `build_pak()` 透過 sed 延遲注入
3. **禁止修改 desktop 文件的 Exec 字段**：由 wrapper 机制在构建时自动处理
4. **禁止手动替换 version 字段**：模板中 `version: "${ll_version}"` 和 `package.version: ${ll_version}` **必须保持为变量**，**不能**替换为 `"1.0"`、`"0.0.1"` 等绝对值。version 只能由 `pak_linyaps.sh` 在构建时通过 `envsubst` 自动替换
5. **不要提前优化**：wrapper 机制需要原始的 Exec 路径来正确提取 binary_name
6. **信任 pak_linyaps.sh**：构建脚本会自动处理所有路径转换和 wrapper 创建

## 输出目录结构

```
CI_ll_<package_id>/
├── pak_linyaps.sh              # 打包脚本
├── config/                     # 配置文件目录
│   └── base_runtime_whitelist.conf  # base/runtime 白名单配置（优先从全局 skills/config/ 拷贝）
├── scripts/                    # 辅助脚本目录
│   └── handle_special_paths.sh # 特殊路径处理脚本
└── templates/
    ├── linglong.yaml           # 玲珑配置模板
    └── files_res/              # 资源文件目录
        └── share/
            ├── applications/
            ├── icons/
            ├── appdata/
            └── ...
```

**注意：**
- 工程初始化时不包含任何源文件（deb包），deb路径由用户执行脚本时通过 `--src_path` 参数指定
- `config/base_runtime_whitelist.conf` 用於驗證 base/runtime 組合的合法性，優先從全局 `skills/config/` 拷貝，全局不存在時使用 skill 級別副本

## 二进制软链处理

`pak_linyaps.sh` 在构建时需要处理二进制软链，**使用相对路径**。

**目录结构说明：**
- `files/` 映射到玲瓏容器内的 `/usr/` 目录
- `files/bin/` → `/usr/bin/` (存放可执行文件软链)
- `files/share/` → `/usr/share/` (存放桌面文件、图标等)
- `files/lib/` → `/usr/lib/` (存放库文件)
- deb 中的非标准路径（如 `/opt/uTools/`）直接放到 `files/` 下作为未归类目录

**路径转换示例：**
```
deb 结构                    binary/ 结构              files/ 结构 (容器内 /usr/)
/opt/uTools/utools    →    uTools/utools       →    /usr/uTools/utools
/opt/uTools/resources →    uTools/resources    →    /usr/uTools/resources
/usr/bin/code         →    bin/code            →    /usr/bin/code
/usr/share/code/      →    share/code/         →    /usr/share/code/
```

**最终目录结构：**
```
files/
├── bin/
│   └── utools -> ../uTools/utools  # 软链指向实际二进制
├── share/
│   ├── applications/
│   └── icons/
├── lib/
└── uTools/          # 原 /opt/uTools/ 直接放到 files/ 下
    ├── utools       # 实际二进制文件
    └── resources/
```

```bash
build_pak() {
  binary_tmp_dir="${build_tmp_dir}/tmp"
  binary_dir="${build_tmp_dir}/binary/"

  # 解压deb包
  dpkg -x "${src_path}" "${binary_tmp_dir}/"
  
  # 创建binary目录结构
  # binary/ 目录的内容会复制到 files/ 根目录
  # files/ 映射到 /usr/，所以 files/bin/ -> /usr/bin/
  mkdir -p "${binary_dir}"
  
  # 调用特殊路径处理脚本
  # 处理 deb 中的文件路径转换，包括：
  # 1. /usr/ 下的内容直接复制到 binary/ (对应 files/)
  # 2. 非 /usr 标准路径（如 /opt/uTools/）直接放到 binary/ 下作为未归类目录
  #    例如：/opt/uTools/ -> binary/uTools/ (去掉 opt/ 层级)
  # 3. 支持包含空格、括号、中文、&、@、#、$ 等特殊字符的路径
  # 注意：此操作必须在所有软链动作之前完成，否则软链关系将被破坏
  "${project_root}/scripts/handle_special_paths.sh" "${binary_tmp_dir}" "${binary_dir}"
  
  # 创建 bin/ 目录用于存放可执行文件软链
  # 注意：此操作必须在特殊路径处理完成之后进行
  mkdir -p "${binary_dir}/bin"
  
  # 处理二进制文件软链
  # 在 files/bin/ 创建软链，指向实际二进制文件
  # 注意：此操作必须在所有文件复制和路径处理完成之后进行
  if [ -n "${binary_name}" ]; then
    # 在 binary/ 目录下查找二进制文件
    actual_binary=$(find "${binary_dir}" -type f -name "${binary_name}" -executable 2>/dev/null | head -n 1)
    
    if [ -n "${actual_binary}" ]; then
      rel_binary="${actual_binary#${binary_dir}}"
      
      cd "${binary_dir}/bin"
      ln -sf "../${rel_binary}" "${binary_name}"
      echo "Created symlink: bin/${binary_name} -> ../${rel_binary}"
      cd "${build_tmp_dir}"
    fi
  fi
}
```

**关键点：**
- `files/` 映射到 `/usr/`，不包含 `/opt`、`/var` 等目录
- 非 `/usr` 标准路径的内容直接放到 `files/` 根目录下
- `files/bin/` 只存放软链，实际应用文件存放在 `files/` 的其他子目录
- 软链使用相对路径（如 `../uTools/utools`），确保在玲瓏容器内正确解析
```

## 🚫 禁止事项（LLM Agent 必读）

**以下行为在生成 `pak_linyaps.sh` 时被严格禁止，违反将导致构建失败或运行时错误：**

### 1. 禁止简化 pak_linyaps.sh

生成 `pak_linyaps.sh` 时，**必须**完整复制模板内容，**禁止**以下行为：

#### 1.1 禁止删除脚本调用

以下脚本调用**必须保留**，不得删除或简化：

| 脚本 | 作用 | 删除后果 |
|------|------|---------|
| `dedup_desktop_files.sh` | desktop 文件去重 | 重复文件进入最终包，可能导致冲突 |
| `validate_bin_nesting.sh` | bin 目录嵌套验证 | 嵌套路径问题导致启动失败 |
| `handle_special_paths.sh` | 特殊路径处理 | 非 `/usr` 路径文件丢失 |

#### 1.2 禁止提前填充 command

**错误示例**：
```bash
# ❌ 错误：在 envsubst 阶段导出 command 变量
export command=${binary_name:-run.sh}
cat "${project_root}/templates/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"
```

**正确做法**：
```bash
# ✅ 正确：不导出 command，由 wrapper 机制在构建时动态设置
# （无 export command）
cat "${project_root}/templates/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"

# 在 build_pak() 中，wrapper 创建后通过 sed 更新 command
sed -i "s|^\s*command:.*|command:|" "${build_tmp_dir}/linglong.yaml"
sed -i '/^\s*command:/a\  - '"${binary_name}"'.wrapper' "${build_tmp_dir}/linglong.yaml"
```

**原因**：
- 模板 `linglong.yaml` 中 `command: ""` 是**正确的**（空占位符）
- `command` 由 `build_pak()` 中的 wrapper 机制通过 **sed 替换**，不是 envsubst
- 提前 `export command=...` 会导致 envsubst 替换为错误的值（不是 wrapper 路径）
- wrapper 脚本在构建时动态创建，生成阶段无法预知路径

#### 1.3 禁止使用错误的模板路径

**错误示例**：
```bash
# ❌ 错误：使用项目根目录（不存在）
cat "${project_root}/linglong.yaml" | envsubst
cp -rf "${project_root}/files_res" "${build_tmp_dir}"
```

**正确做法**：
```bash
# ✅ 正确：使用 templates/ 目录
cat "${project_root}/templates/linglong.yaml" | envsubst
cp -rf "${project_root}/templates/files_res" "${build_tmp_dir}"
```

**原因**：
- 工程目录结构设计中，`linglong.yaml` 和 `files_res` 位于 `templates/` 目录下
- 项目根目录不直接包含这些文件

### 2. 错误示例 vs 正确示例对比

#### ❌ 错误：简化版 pak_linyaps.sh（来自 error-demos/pak_linyaps.error.sh）

```bash
# 错误1：导出 command 变量
export command=${binary_name:-run.sh}

# 错误2：导出 base/runtime 变量（envsubst 提前固化）
export base_id=${base_id}
export base_version=${base_version}
export runtime_id=${runtime_id}
export runtime_version=${runtime_version}

# 错误3：跳过脚本调用
# （缺失 dedup_desktop_files.sh 调用）
# （缺失 validate_bin_nesting.sh 调用）

# 错误4：linglong.yaml command 被错误填充
# command: ""  被错误地替换为 ${binary_name:-run.sh}
```

#### ✅ 正确：完整版 pak_linyaps.sh（来自 templates/pak_linyaps.sh）

```bash
# 正确1：不导出 command，由 wrapper 机制设置
# （无 export command）

# 正确2：不导出 base/runtime，由 sed 延遲注入
# （无 export base_id / export base 等行）

# 正确3：保留所有脚本调用
"${project_root}/scripts/dedup_desktop_files.sh" "${build_tmp_dir}/binary" --reference-dir "${build_tmp_dir}/files_res"
"${project_root}/scripts/dedup_desktop_files.sh" "${build_tmp_dir}/files_res"
"${project_root}/scripts/validate_bin_nesting.sh" "${binary_dir}" --fix

# 正确4：使用 templates/ 路径（模板文件位于 templates/ 目录）
cat "${project_root}/templates/linglong.yaml" | envsubst
cp -rf "${project_root}/templates/files_res" "${build_tmp_dir}"

# 正确5：wrapper 创建后动态更新 command
sed -i '/^\s*command:/{n;/^\s*-\s*/d}' "${build_tmp_dir}/linglong.yaml"
sed -i "s|^\s*command:.*|command:|" "${build_tmp_dir}/linglong.yaml"
sed -i '/^\s*command:/a\  - '"${binary_name}"'.wrapper' "${build_tmp_dir}/linglong.yaml"

# 正确6：wrapper 创建后动态注入 base/runtime
sed -i "s|^\s*base:.*|base: ${base_id}/${base_version}|" "${build_tmp_dir}/linglong.yaml"
sed -i "s|^\s*runtime:.*|runtime: ${runtime_id}/${runtime_version}|" "${build_tmp_dir}/linglong.yaml"
```

### 3. 生成后自检清单

生成 `pak_linyaps.sh` 后，**必须**检查以下内容：

- [ ] **脚本调用完整性**：`dedup_desktop_files.sh`、`validate_bin_nesting.sh`、`handle_special_paths.sh` 调用存在
- [ ] **command 未提前填充**：`build_dir_init()` 中无 `export command=` 行
- [ ] **模板路径正确**：使用 `${project_root}/templates/linglong.yaml`（模板文件位于 templates/ 目录）
- [ ] **资源路径正确**：使用 `${project_root}/templates/files_res`（资源文件位于 templates/ 目录）
- [ ] **wrapper 机制完整**：`build_pak()` 中包含 wrapper 创建和 command 更新逻辑

## ⚠️ 常见错误警告（LLM Agent 必读）

**以下错误在 LLM 自动生成 `pak_linyaps.sh` 时经常出现，必须避免：**

### 1. 模板路径错误

❌ **错误写法：**
```bash
# 错误：使用项目根目录（不存在）
cp -rf "${project_root}/files_res" "${build_tmp_dir}"
cat "${project_root}/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"
```

✅ **正确写法：**
```bash
# 正确：使用 templates/ 目录
cp -rf "${project_root}/templates/files_res" "${build_tmp_dir}"
cat "${project_root}/templates/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"
```

**原因：** 
- 工程目录结构设计中，`linglong.yaml` 和 `files_res` 位于 `templates/` 目录下
- 项目根目录不直接包含这些文件

### 2. export command 变量错误

❌ **错误写法：**
```bash
# 错误：在 envsubst 阶段导出 command 变量
export command=${binary_name:-run.sh}
export linyaps_arch=${linyaps_arch}

cat "${project_root}/templates/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"
```

✅ **正确写法：**
```bash
# 正确：不导出 command，由 wrapper 机制在构建时动态设置
export linyaps_arch=${linyaps_arch}
# 注意：无 export command 行

cat "${project_root}/templates/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"

# 在 build_pak() 中，wrapper 创建后通过 sed 更新 command
sed -i '/^\s*command:/{n;/^\s*-\s*/d}' "${build_tmp_dir}/linglong.yaml"
sed -i "s|^\s*command:.*|command:|" "${build_tmp_dir}/linglong.yaml"
sed -i '/^\s*command:/a\  - '"${binary_name}"'.wrapper' "${build_tmp_dir}/linglong.yaml"
```

**原因：** 
- `linglong.yaml` 模板中 `command: ""` 是正确的，表示由 wrapper 机制动态设置
- `command` 必须指向 wrapper 脚本路径（如 `bin/app.wrapper`）
- 提前导出 `command` 会导致启动命令错误，wrapper 机制失效

### 2b. 禁止在 envsubst 阶段导出 base/runtime

❌ **错误写法（已廢棄）：**
```bash
# 错误：在 envsubst 阶段导出 base/runtime
export base_id=${base_id}
export base_version=${base_version}
export runtime_id=${runtime_id}
export runtime_version=${runtime_version}
# 或
export base="${base_id}/${base_version}"
export runtime="${runtime_id}/${runtime_version}"
```

✅ **正确写法：**
```bash
# 正确：不导出 base/runtime，由 build_pak() 透過 sed 延遲注入
# 注意：无 export base_id / export base 等行
export prefix="\$PREFIX"
export ll_version=${ll_version}
export linyaps_arch=${linyaps_arch}

cat "${project_root}/templates/linglong.yaml" | envsubst >"${build_tmp_dir}/linglong.yaml"

# 在 build_pak() 中，wrapper 创建后通过 sed 注入 base/runtime
sed -i "s|^\s*base:.*|base: ${base_id}/${base_version}|" "${build_tmp_dir}/linglong.yaml"
sed -i "s|^\s*runtime:.*|runtime: ${runtime_id}/${runtime_version}|" "${build_tmp_dir}/linglong.yaml"
```

**原因：**
- 模板 `linglong.yaml` 中 `base: ""`, `runtime: ""` 是空佔位符
- 提前 export 會導致 envsubst 將空佔位符替換為錯誤值（模板中已無 base/runtime 變量）
- base/runtime 由 `build_pak()` 的 `sed` 在構建時動態注入，支援 `--base_id`/`--runtime_id` CLI 參數覆蓋

### 3. 变量定义方式错误

❌ **错误写法（硬编码）：**
```bash
case "${linyaps_arch}" in
"x86_64")
  binary_arch="amd64"
  base_id="org.deepin.base"        # 硬编码
  base_version="25.2.2"            # 硬编码
  runtime_id="org.deepin.runtime.dtk"
  runtime_version="25.2.2"
  ;;
```

✅ **正确写法（引用顶部变量）：**
```bash
# 在脚本顶部定义
package_id="com.opera.browser"
base_id="org.deepin.base"
base_version="25.2.2"
runtime_id="org.deepin.runtime.dtk"
runtime_version="25.2.2"

# 在 case 中引用
case "${linyaps_arch}" in
"x86_64")
  binary_arch="amd64"
  base_id="${base_id}"              # 引用顶部变量
  base_version="${base_version}"
  runtime_id="${runtime_id}"
  runtime_version="${runtime_version}"
  ;;
```

**原因：** 顶部变量定义便于维护和修改，避免多处硬编码不一致。

### 4. base/runtime 变量自引用（⚠️ LLM 高频错误）

❌ **错误写法（变量自引用，值为空！）：**
```bash
# 顶部未定义 base_id 等变量
ll_id="${package_id}"

# case 中自引用 — 此时 base_id 等变量为空！
case "${linyaps_arch}" in
"x86_64")
  binary_arch="amd64"
  base_id="${base_id}"              # ❌ 自引用空变量！
  base_version="${base_version}"    # ❌ 自引用空变量！
  runtime_id="${runtime_id}"        # ❌ 自引用空变量！
  runtime_version="${runtime_version}" # ❌ 自引用空变量！
  ;;
```

✅ **正确写法（使用默认值 + 命令行参数覆盖）：**
```bash
ll_id="${package_id}"

# 默认 base/runtime 配置（可通过命令行参数覆盖）
DEFAULT_BASE_ID="org.deepin.base"
DEFAULT_BASE_VERSION="25.2.2"
DEFAULT_RUNTIME_ID="org.deepin.runtime.dtk"
DEFAULT_RUNTIME_VERSION="25.2.2"

base_id="${DEFAULT_BASE_ID}"
base_version="${DEFAULT_BASE_VERSION}"
runtime_id="${DEFAULT_RUNTIME_ID}"
runtime_version="${DEFAULT_RUNTIME_VERSION}"

# case 中只需设置 binary_arch，不再重复赋值 base/runtime
case "${linyaps_arch}" in
"x86_64")
  binary_arch="amd64"
  ;;
"arm64")
  binary_arch="arm64"
  ;;
esac

# init_global_data 末尾调用验证
validate_base_runtime
```

**原因：** `base_id="${base_id}"` 是变量自引用，如果 `base_id` 未事先定义，其值为空。这是 LLM 生成时最常见的错误之一。正确做法是在脚本顶部定义默认值，并通过 `validate_base_runtime()` 函数在运行时验证。

### 5. 生成后自检清单

生成 `pak_linyaps.sh` 后，必须检查以下内容：

**脚本调用完整性：**
- [ ] `dedup_desktop_files.sh` 调用存在（desktop 文件去重）
- [ ] `validate_bin_nesting.sh` 调用存在（bin 目录嵌套验证）
- [ ] `handle_special_paths.sh` 调用存在（特殊路径处理）

**command/base/runtime 处理正确性：**
- [ ] `build_dir_init()` 中**无** `export command=` 行（command 由 wrapper 机制设置）
- [ ] `build_dir_init()` 中**无** `export base_id=`、`export base=` 等行（base/runtime 由 sed 延遲注入）
- [ ] `build_pak()` 中包含 wrapper 创建逻辑
- [ ] `build_pak()` 中包含 sed 更新 command 的逻辑
- [ ] `build_pak()` 中包含 sed 注入 base/runtime 的逻辑

**⚠️ command 处理说明：**
- 模板 `linglong.yaml` 中 `command: ""` 是**正确的**（空占位符）
- `command` 由 `build_pak()` 中的 wrapper 机制通过 **sed 替换**，不是 envsubst
- **禁止**在 `build_dir_init()` 中 `export command=...`，这会导致错误的启动命令

**模板路径正确性：**
- [ ] `build_dir_init` 函数中 `files_res` 路径为 `${project_root}/templates/files_res`
- [ ] `build_dir_init` 函数中 `linglong.yaml` 路径为 `${project_root}/templates/linglong.yaml`

**base/runtime 配置正确性：**
- [ ] `base_id`、`runtime_id` 等变量在脚本顶部定义，case 中引用
- [ ] `--binary_name` 参数在 `init_global_data` 的参数解析中存在
- [ ] **`base_id`、`base_version`、`runtime_id`、`runtime_version` 使用实际值，不是变量自引用**
- [ ] **`DEFAULT_BASE_ID` 等默认值定义存在**
- [ ] **`--base_id`、`--base_version`、`--runtime_id`、`--runtime_version` 命令行参数已支持**
- [ ] **`validate_base_runtime()` 函数已定义并在 `init_global_data()` 末尾调用**
- [ ] **case 语句中无 `base_id="${base_id}"` 等自引用赋值**
- [ ] **`validate_base_runtime_whitelist()` 白名单验证函数已定义**
- [ ] **白名单配置文件 `config/base_runtime_whitelist.conf` 已复制到工程目录**

### 6. 生成后验证步骤

生成工程后，必须运行以下验证：

```bash
# 验证 pak_linyaps.sh 脚本中的 base/runtime 配置
"${skill_root}/scripts/validate_pak_script.sh" "${project_dir}"

# 如发现问题，使用 --fix 自动修复
"${skill_root}/scripts/validate_pak_script.sh" "${project_dir}" --fix

# 验证 linglong.yaml 格式（含 base/runtime 格式验证）
"${skill_root}/../compat-testing/scripts/validate_linglong_yaml.py" \
  --input "${project_dir}/templates/linglong.yaml" \
  --exec-name "${binary_name}"
```

### 7. base/runtime 白名单验证

通过白名单配置文件 `config/base_runtime_whitelist.conf` 验证 base/runtime 组合是否为已知合规组合。

**白名单文件格式：**
```
# 注释行
<base_id>/<base_version>	<runtime_id>/<runtime_version>	描述
```

**当前白名单中的合规组合：**

| base | runtime | 适用场景 |
|------|---------|---------|
| `org.deepin.base/25.2.2` | `org.deepin.runtime.dtk/25.2.2` | Qt6/DTK6 应用（推荐默认） |
| `org.deepin.base/25.2.2` | `org.deepin.runtime.webengine/25.2.2` | Qt6 WebEngine 应用 |
| `org.deepin.base/23.1.0` | `org.deepin.runtime.dtk/23.1.0` | Qt5/DTK5 应用 |
| `org.deepin.base/25.2.2` | `-` | 纯 base 应用（无 runtime） |
| `org.deepin.base/23.1.0` | `-` | 纯 base 应用（无 runtime，23.1.0） |

**白名单查找优先级（本地优先全局）：**
1. CLI 參數 `--whitelist` 指定的路徑
2. 环境变量 `LINGLONG_WHITELIST_FILE` 指定的路径
3. 工程目录下的 `config/base_runtime_whitelist.conf`
4. 脚本所在目录的 `config/base_runtime_whitelist.conf`（skill 级别）
5. **skills 全局目录** `config/base_runtime_whitelist.conf`（全局声明，推荐维护）⭐

**验证行为：**
- 白名单验证为**阻止级别**，不在白名单中的组合会阻止构建（exit 1）
- 白名单文件不存在时，跳过白名单验证（不影响构建）
- 白名单文件不可读时，报错并阻止构建

**工程初始化时复制白名单（优先全局）：**
```bash
# 创建工程目录时，优先复制全局白名单配置文件
mkdir -p "${project_dir}/config"
if [ -f "${skill_root}/../config/base_runtime_whitelist.conf" ]; then
  cp "${skill_root}/../config/base_runtime_whitelist.conf" "${project_dir}/config/"
else
  cp "${skill_root}/config/base_runtime_whitelist.conf" "${project_dir}/config/"
fi
```

**自定义白名单：**
```bash
# 通过环境变量指定自定义白名单
export LINGLONG_WHITELIST_FILE=/path/to/custom_whitelist.conf

# 或在工程目录下放置自定义白名单（优先于全局）
if [ -f "${skill_root}/../config/base_runtime_whitelist.conf" ]; then
  cp "${skill_root}/../config/base_runtime_whitelist.conf" "${project_dir}/config/"
else
  cp "${skill_root}/config/base_runtime_whitelist.conf" "${project_dir}/config/"
fi
# 编辑 ${project_dir}/config/base_runtime_whitelist.conf 添加新组合
```

---

## 注意事项

1. 工程目录命名必须遵循 `CI_ll_<package_id>` 格式
2. `linglong.yaml` 中的变量使用 `${var}` 格式，由 `envsubst` 替换
3. `pak_linyaps.sh` 需要可执行权限 (`chmod +x`)
4. 多架构支持通过 `--linyaps_arch` 参数指定
5. base/runtime 从CSV配置读取，支持不同架构使用不同版本
6. **deb文件路径由用户执行时指定，不存储在工程目录内**
7. **二进制命令使用相对路径，由 `pak_linyaps.sh` 处理软链**
8. **特殊格式路径处理**：
   - 解压后可能目录命名方式不符合Linux规范，存在空格等需要额外转译的类型
   - `pak_linyaps.sh` 已使用 `find` + `IFS= read -r` 组合正确处理特殊字符路径
   - 支持的特殊字符包括：空格、括号、&、@、#、$、中文字符等
   - 可使用 `scripts/test_special_paths.sh` 验证特殊路径处理逻辑
9. **构建缓存目录可通过 `--build_tmp_dir` 参数指定，未指定时使用系统临时目录**
10. **自定义构建缓存目录时，目录不存在会自动创建；清理行为由 `auto_clean` 参数控制**
11. **files/ 映射到 /usr/**：`files/bin/` → `/usr/bin/`，非标准路径（如 `/opt/`）的内容直接放到 `files/` 根目录下

## 特殊格式路径处理

### 问题背景

deb 包解压后可能包含不符合 Linux 命名规范的路径，例如：
- 包含空格的目录名：`/opt/My App/`
- 包含特殊字符的目录名：`/opt/App (x86_64)/`
- 包含中文字符的目录名：`/opt/我的应用/`

### 解决方案

`pak_linyaps.sh` 使用以下技术正确处理特殊字符路径：

```bash
# 使用 find 命令遍历目录，避免 shell glob 的问题
find "${binary_tmp_dir}/${non_std_dir}" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r subdir; do
    if [ -d "${subdir}" ]; then
        subdir_name=$(basename "${subdir}")
        mkdir -p "${binary_dir}/${subdir_name}"
        cp -r "${subdir}/." "${binary_dir}/${subdir_name}/"
    fi
done
```

**关键技术点：**
1. 使用 `find` 命令而非 `for subdir in */` 遍历目录
2. 使用 `IFS= read -r` 防止 shell 对特殊字符进行解释
3. 所有路径变量使用双引号保护
4. 使用 `basename` 提取文件名，避免路径解析问题

### 验证测试

使用 `scripts/test_special_paths.sh` 验证特殊路径处理逻辑：

```bash
# 运行测试
./scripts/test_special_paths.sh

# 保留测试目录用于调试
./scripts/test_special_paths.sh /tmp/test --keep
```

测试覆盖以下场景：
- 空格字符（单空格、多空格）
- 特殊符号（括号、&、@、#、$）
- Unicode 字符（中文）
- 文件名和目录名中的特殊字符
- 软链创建的正确性

详细说明请参考 `scripts/README_test_special_paths.md`。