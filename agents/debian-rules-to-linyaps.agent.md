---
name: debian-rules-to-linyaps
description: >
  分析项目源代码对应的 debian 构建规则和构建资源，为玲珑构建项目生成构建、编译规则和通用资源。
tools:
  read: true; edit: true; search: true; execute: true; todo: true; skill: true
permission:
  skill: { "*": "allow" }
skills:
  - id: src2linyaps.debian.test-deps
    path: skills/src2linyaps.debian.test-deps/SKILL.md
    type: sub
  - id: src2linyaps.debian.analyze-control
    path: skills/src2linyaps.debian.analyze-control/SKILL.md
    type: sub
  - id: src2linyaps.debian.analyze-rules
    path: skills/src2linyaps.debian.analyze-rules/SKILL.md
    type: sub
  - id: src2linyaps.debian.build-res-generate
    path: skills/src2linyaps.debian.build-res-generate/SKILL.md
    type: sub
  - id: src2linyaps.source.detect-tool
    path: skills/src2linyaps.source.detect-tool/SKILL.md
    type: sub
  - id: src2linyaps.source.analyze-args
    path: skills/src2linyaps.source.analyze-args/SKILL.md
    type: sub
---

# debian-rules-to-linyaps — 主 Agent

## Phase 0: 全局声明

引用 `agent-config.json` 中的全局配置，`${tag}` 路径使用 `date +"%Y-%m-%d"` 实时解析。

```yaml
# 引用 agent-config.json:
#   output_dir: ./output/${tag}  →  ./output/2026-07-07
#   data_dir: ./data/${tag}.log  →  ./data/2026-07-07.log
#   build_tmp_dir: ./build_cache
```

## Phase 1: 初始化

1. 验证 workspace 根目录是否包含 `skills/` 和 `agents/` 目录
2. 创建输出目录 `output/${tag}/`
3. 记录开始时间和项目路径

## Phase 2: 路径选择

按以下优先级判断工作流路径：

1. **用户显式指定**：如果用户提示词中明确指定了构建规则所在目录，优先使用用户配置
2. **自动检测**：否则 Agent 自动扫描项目根目录：
   - 若存在 `debian/` 目录 → 走 **路径 A**（debian 规则分析）
   - 若不存在 `debian/` 目录 → 走 **路径 B**（源码直接分析，fallback）

## Phase 3A: 路径 A — debian 规则分析

### Step 1: 加载子 Skill — `src2linyaps.debian.test-deps`

```yaml
# 输入
project_path: <项目路径>
debian_path: <项目路径>/debian
```

**执行方式**：
- 优先通过 `skill()` 工具加载子 Skill，按 SKILL.md 指引执行
- 若 `skill()` 工具不可用，fallback 读取 `skills/src2linyaps.debian.test-deps/SKILL.md` 并执行 `scripts/test-build-deps.sh`
- 输出依赖检测结果 JSON

### Step 2: 加载子 Skill — `src2linyaps.debian.analyze-control`

```yaml
# 输入
control_content: <debian/control 文件内容>
project_path: <项目路径>
```

**执行方式**：
- 读取 `debian/control` 完整文本
- 执行 `scripts/parse-control.py <control_file>` → 输出 control YAML（含 buildDepends）
- 执行 `scripts/resolve-runtime-deps.py <control_yaml>` → 输出 runtime YAML（含 runtimeDepends）
- Agent 合并两者为完整的 control 信息
- 输出结构化信息 YAML

### Step 2.5: (内置在 analyze-control 中) 解析运行时依赖

运行时依赖解析已集成到 Step 2 中：
1. `parse-control.py` 先提取 Build-Depends 列表
2. `resolve-runtime-deps.py` 基于 apt 仓库查询每个构建依赖包的运行时 Depends + Recommends
3. 合并后输出完整的 control 信息（含 runtimeDepends）

### Step 3: 加载子 Skill — `src2linyaps.debian.analyze-rules`

```yaml
# 输入
project_path: <项目路径>
debian_path: <项目路径>/debian
control_info: <上一步输出的 control 信息>
```

**执行方式**：
- 读取 `debian/rules`, `debian/changelog`, `debian/*.install` 等文件
- 执行 `scripts/analyze-rules.py <project_path> <debian_path> [control_yaml]`
- 输出最终 YAML

### Step 4: 加载子 Skill — `src2linyaps.debian.build-res-generate`

```yaml
# 输入
control_info: <Step 2 输出的 control YAML 路径>
build_section: <Step 3 输出的 build_section 字符串>
package_version: <Step 3 输出的 baseline 版本号>
architecture: x86_64            # 默认值，用户可覆盖
base: org.deepin.base/25.2.2    # 默认值，用户可覆盖
runtime: org.deepin.runtime.dtk/25.2.2  # 默认值，用户可覆盖
command: ""                     # 默认值，用户可覆盖
```

**执行方式**：
- 通过 `skill()` 工具加载子 Skill `src2linyaps.debian.build-res-generate`
- 按 SKILL.md 指引，调用 `scripts/generate-linglong-yaml.py` 生成 `linglong.yaml`
- 脚本参数传递：
  ```
  python3 generate-linglong-yaml.py \
    --control-info <control_info.yaml> \
    --build-section "<build_section>" \
    --package-version <baseline> \
    --defaults skills/config/linglong-defaults.json \
    --output output/${tag}/linglong.yaml
  ```
- 使用 `--defaults` 中的值作为 Architecture/base/runtime/command 的默认值
- 用户可通过额外参数显式覆盖默认值

**输出**：`output/${tag}/linglong.yaml`（完整的玲珑构建配方）

## Phase 3B: 路径 B — fallback 源码分析

### Step 1: 加载子 Skill — `src2linyaps.source.detect-tool`

```yaml
# 输入
project_path: <项目路径>
```

**执行方式**：
- 执行 `scripts/detect-build-tool.sh <project_path>`
- 输出构建工具类型 YAML

### Step 2: 加载子 Skill — `src2linyaps.source.analyze-args`

```yaml
# 输入
project_path: <项目路径>
tool_type: <上一步输出的工具类型>
```

**执行方式**：
- 执行 `scripts/extract-build-args.py <project_path> <tool_type>`
- 输出最终 YAML

### Step 3: 输出路径 B 的最终结果

## Phase 4: 输出校验与写入

1. 校验 `linglong.yaml` 完整性：
   - `package.id` 字段必须存在且非空
   - `version` 字段必须存在且非空
   - `buildext.apt` 字段必须存在
   - `build` 字段必须存在且非空
2. 将最终 `linglong.yaml` 写入 `output/${tag}/linglong.yaml`
3. 输出 `output/${tag}/linglong.yaml` 路径给用户

## 失败处理

- **规则与源码不匹配**：若 `test-build-deps` 检测到 `debian/` 规则与源码明显不匹配（如构建依赖全不可用），终止任务并报告原因
- **子 Skill 执行失败**：暂停并询问用户是否继续或终止
- **配置缺失**：若 `agent-config.json` 不可读，使用合理的默认值

## 示例用法

```bash
# 路径 A：自动检测 debian/
debian-rules-to-linyaps /path/to/kate-cmake

# 路径 A：用户指定 debian 目录
debian-rules-to-linyaps /path/to/project --debian-dir /custom/path/debian

# 路径 B：自动检测构建工具
debian-rules-to-linyaps /path/to/mame-source
```