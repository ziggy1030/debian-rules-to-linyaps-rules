# linglong-fix 脚本工具

本目录包含用于修复玲珑构建项目问题的脚本工具。

## 脚本列表

### validate_package_id.sh

验证玲珑包ID格式和一致性。

**功能：**
- 验证工程目录命名格式（`CI_ll_<package_id>`）
- 验证 package_id 格式（反向域名格式）
- 验证 linglong.yaml 中的 `package.id` 与目录名一致性
- 验证 deb 文件存储路径（`<package_id>/xxx.deb`）

**用法：**
```bash
./validate_package_id.sh <project_dir> [选项]

参数：
  project_dir       工程目录路径（如 CI_ll_com.visualstudio.code）

选项：
  --deb-path <path> deb 文件路径，用于验证存储路径
  --verbose, -v     显示详细输出
  --help, -h        显示帮助信息
```

**示例：**
```bash
# 基本验证
./validate_package_id.sh CI_ll_com.visualstudio.code

# 验证 deb 文件路径
./validate_package_id.sh CI_ll_com.visualstudio.code \
  --deb-path com.visualstudio.code/code_1.85.0_amd64.deb

# 详细输出
./validate_package_id.sh CI_ll_com.visualstudio.code --verbose
```

**返回值：**
- `0` - 验证通过
- `1` - 验证失败

**输出格式：**
```json
{
  "status": "passed|failed|warning",
  "package_id": "com.visualstudio.code",
  "project_dir": "CI_ll_com.visualstudio.code",
  "errors": ["错误信息列表"],
  "warnings": ["警告信息列表"]
}
```

---

### fix_package_id.sh

修复玲珑包ID相关问题。

**功能：**
- 修复 linglong.yaml 中的 `package.id` 字段
- 修复 desktop 文件中的相关引用
- 重命名工程目录（可选）

**用法：**
```bash
./fix_package_id.sh <project_dir> [选项]

参数：
  project_dir       工程目录路径

选项：
  --new-id <id>     指定新的 package_id（如不指定则从 linglong.yaml 提取）
  --dry-run         仅模拟执行，不实际修改文件
  --rename-dir      允许重命名工程目录
  --verbose, -v     显示详细输出
  --help, -h        显示帮助信息
```

**示例：**
```bash
# 模拟执行（查看将要进行的修改）
./fix_package_id.sh CI_ll_com.visualstudio.code --dry-run

# 修复 linglong.yaml 中的 package.id
./fix_package_id.sh CI_ll_com.visualstudio.code --new-id com.visualstudio.code

# 修复并重命名工程目录
./fix_package_id.sh CI_ll_wrong.name --new-id com.visualstudio.code --rename-dir

# 详细输出
./fix_package_id.sh CI_ll_com.visualstudio.code --verbose
```

**返回值：**
- `0` - 修复成功
- `1` - 修复失败或部分失败

---

## package_id 格式规范

玲珑包ID必须符合以下规范：

| 规则 | 说明 | 示例 |
|------|------|------|
| 格式 | 反向域名格式 | `com.example.app` |
| 字符 | 小写字母、数字、下划线、点 | `org.deepin.music` |
| 结构 | 至少两个点分隔的部分 | `cn.wps.wps-office` |
| 长度 | 最大255字符 | - |

**正确示例：**
- ✅ `com.visualstudio.code`
- ✅ `org.deepin.music`
- ✅ `cn.wps.wps-office`

**错误示例：**
- ❌ `VisualStudio.Code` - 包含大写字母
- ❌ `code` - 缺少域名前缀
- ❌ `com..example` - 连续的点
- ❌ `com.example.` - 以点结尾

---

## 典型工作流程

### 1. 验证工程

```bash
# 验证工程目录
./validate_package_id.sh CI_ll_com.visualstudio.code

# 如果验证失败，查看详细错误
./validate_package_id.sh CI_ll_com.visualstudio.code --verbose
```

### 2. 修复问题

```bash
# 先模拟执行，查看将要进行的修改
./fix_package_id.sh CI_ll_com.visualstudio.code --dry-run

# 确认无误后，执行修复
./fix_package_id.sh CI_ll_com.visualstudio.code --new-id com.visualstudio.code

# 如果需要重命名目录
./fix_package_id.sh CI_ll_wrong.name --new-id com.visualstudio.code --rename-dir
```

### 3. 验证修复结果

```bash
# 再次验证确认问题已解决
./validate_package_id.sh CI_ll_com.visualstudio.code
```

---

## 与 linglong-project-gen 的集成

这些脚本用于强化 `linglong-project-gen` skill 的流程，确保：

1. **工程目录命名正确**：`CI_ll_<package_id>`
2. **deb 文件存储路径正确**：`<package_id>/xxx.deb`
3. **linglong.yaml 配置正确**：`package.id` 与目录名一致

### 在 SKILL 中调用

```bash
# 在 linglong-project-gen 的 SKILL.md 中添加验证步骤
# 1. 准备工程目录后，验证 package_id
"${skill_root}/../linglong-fix/scripts/validate_package_id.sh" "${project_dir}"

# 2. 如果验证失败，调用修复脚本
"${skill_root}/../linglong-fix/scripts/fix_package_id.sh" "${project_dir}" --new-id "${package_id}"
```

---

## 错误处理

### 常见错误及解决方案

| 错误信息 | 原因 | 解决方案 |
|---------|------|---------|
| `工程目录命名不符合规范` | 目录名不是 `CI_ll_` 开头 | 使用 `--rename-dir` 重命名 |
| `package_id 格式不正确` | 不符合反向域名格式 | 使用 `--new-id` 指定正确的 ID |
| `linglong.yaml 中的 package.id 与工程目录不匹配` | YAML 配置与目录名不一致 | 运行修复脚本 |
| `deb 文件存储路径不正确` | deb 文件不在正确的目录下 | 移动 deb 文件到正确位置 |

---

## 注意事项

1. **备份**：修复脚本会自动备份原文件（`.bak` 后缀）
2. **模拟执行**：建议先使用 `--dry-run` 查看将要进行的修改
3. **目录重命名**：需要显式启用 `--rename-dir` 选项
4. **权限**：确保脚本有可执行权限（`chmod +x *.sh`）
