---
name: project-structure-validator
description: >
  验证玲珑打包项目目录结构和必要文件的完整性。支持通过JSON配置文件自定义检查规则，
  包括目录存在性、文件存在性、通配符匹配数量、脚本可执行权限等。
user-invocable: false
---

# 项目结构验证器

## 功能说明

验证玲珑打包项目目录结构和必要文件的完整性，确保项目符合打包要求。

## 触发场景

- `linglong-project-gen` 生成工程后验证
- `linglong-fix` 修复后验证
- 批量处理前的项目预检
- CI/CD 流水线中的自动化验证

## 工作流程

### 1. 加载配置

```bash
# 使用默认配置
validate_project_structure.sh <project_dir>

# 使用自定义配置
validate_project_structure.sh <project_dir> --config custom.json
```

### 2. 执行检查

按照 JSON 配置文件中的 `checks` 数组逐项检查：

| type | 检查方式 |
|------|----------|
| `directory` | `[ -d "$path" ]` |
| `file` | `[ -f "$path" ]` |
| `file` + `min` | glob 匹配数量 >= min |

### 3. 权限验证

检查 `executable` 字段中定义的文件是否有可执行权限。

### 4. 输出结果

- 默认输出人类可读格式
- `--json` 输出 JSON 格式
- `--fix` 自动修复权限问题

## 配置文件格式

```json
{
  "checks": [
    {"pattern": "scripts/", "type": "directory"},
    {"pattern": "templates/", "type": "directory"},
    {"pattern": "pak_linyaps.sh", "type": "file"},
    {"pattern": "templates/files_res/share/applications/*.desktop", "type": "file", "min": 1}
  ],
  "executable": ["pak_linyaps.sh", "scripts/*.sh"]
}
```

## 使用示例

### 基本用法

```bash
# 验证项目
./scripts/validate_project_structure.sh /path/to/CI_ll_xxx

# 使用自定义配置
./scripts/validate_project_structure.sh /path/to/CI_ll_xxx --config my_rules.json

# 输出 JSON 格式
./scripts/validate_project_structure.sh /path/to/CI_ll_xxx --json

# 自动修复权限
./scripts/validate_project_structure.sh /path/to/CI_ll_xxx --fix
```

### 在 Agent 中调用

```bash
# 在 deb-linglong-packer agent 中
skill_root="skills/project-structure-validator"

# 验证生成的项目
"${skill_root}/scripts/validate_project_structure.sh" "${project_dir}" --json

# 如果验证失败，调用 linglong-fix
if [ $? -ne 0 ]; then
    echo "验证失败，需要修复"
    # 调用 linglong-fix skill
fi
```

## 输出格式

### 人类可读格式

```
[INFO] 验证项目: CI_ll_com.opera.browser
[PASS] scripts/ 目录存在
[PASS] templates/ 目录存在
[PASS] pak_linyaps.sh 文件存在
[PASS] templates/files_res/share/applications/*.desktop (2 个文件)
[ERROR] 缺少可执行权限: scripts/dedup_desktop_files.sh

验证结果: 失败 (1 个错误)
```

### JSON 格式

```json
{
  "project": "CI_ll_com.opera.browser",
  "passed": false,
  "errors": [
    {
      "type": "executable",
      "pattern": "scripts/dedup_desktop_files.sh",
      "message": "缺少可执行权限"
    }
  ],
  "warnings": [],
  "summary": {
    "total_checks": 15,
    "passed": 14,
    "failed": 1
  }
}
```

## 与其他 Skill 的关系

```
linglong-project-gen (生成工程)
        ↓
project-structure-validator (验证结构)
        ↓ (失败)
linglong-fix (修复问题)
        ↓
project-structure-validator (再次验证)
        ↓ (成功)
compat-testing (兼容性测试)
```

## 测试

```bash
cd skills/project-structure-validator/tests
./test_validate_project_structure.sh
```

## 文件结构

```
skills/project-structure-validator/
├── SKILL.md
├── scripts/
│   ├── validate_project_structure.sh
│   └── default_check_config.json
└── tests/
    └── test_validate_project_structure.sh
```
