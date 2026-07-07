# appimage-linyaps 技能

## 概述

`appimage-linyaps` 是一个技能，用于将 AppImage 应用程序转换为玲珑（Linyaps）包格式。该技能基于 `tar-linyaps` 技能架构，专门针对 AppImage 的特性进行优化。

## 功能特性

### 核心功能
1. **AppImage 解压**：使用 `--appimage-extract` 安全解压 AppImage 文件
2. **元数据提取**：从 desktop 文件和文件名中智能提取应用信息
3. **Exec 命令解析**：准确提取 Exec 命令，支持多种 AppImage 变体
4. **Wrapper 机制**：保留 AppImage 原始目录结构，通过 wrapper 脚本执行

### 支持的 AppImage 变体
- 标准 AppImage（包含 AppRun）
- AppRun.wrapped 变体
- 直接二进制执行
- 带 ${HERE} 变量的路径
- 带引号的 Exec 命令

## 目录结构

```
appimage-linyaps/
├── scripts/                    # 脚本文件
│   ├── extract_appimage.sh     # AppImage 解压脚本
│   ├── resolve_exec_command.sh # Exec 命令解析脚本
│   ├── parse_appimage_metadata.sh # 元数据提取脚本
│   └── parse_build_config.sh   # 配置解析脚本
├── templates/                  # 模板文件
│   ├── linglong.yaml           # 玲珑包模板
│   ├── pak_linyaps.sh          # 主构建脚本（待创建）
│   └── files_res/              # 资源文件目录
├── examples/                   # 示例文件
│   └── build_config.example.json # 配置示例
├── config/                     # 配置文件
│   └── base_runtime_whitelist.conf # 白名单配置（待复制）
├── SKILL.md                    # 技能定义（待创建）
├── README.md                   # 本文档
├── IMPLEMENTATION.md           # 实现方案文档
├── IMPLEMENTATION_SUMMARY.md   # 实现流程摘要
└── IMPLEMENTATION_FLOW.md      # 实现流程详细文档
```

## 快速开始

### 1. 查看设计文档
```bash
# 查看详细设计
cat IMPLEMENTATION.md

# 查看实现流程
cat IMPLEMENTATION_FLOW.md
```

### 2. 查看待办事项
```bash
# 查看待办事项
cat ../appimage-linyaps-todo.md

# 查看进度跟踪
cat ../appimage-linyaps-progress.md
```

### 3. 查看使用指南
```bash
# 查看使用指南
cat ../docs/appimage-linyaps.README.md
```

## 脚本说明

### 1. extract_appimage.sh
**功能**：解压 AppImage 文件

**用法**：
```bash
./scripts/extract_appimage.sh <appimage_path> <output_dir>
```

**参数**：
- `appimage_path`：AppImage 文件路径
- `output_dir`：输出目录

**输出**：在 `output_dir` 下生成 `squashfs-root/` 目录

### 2. resolve_exec_command.sh
**功能**：从 desktop 文件中提取 Exec 命令

**用法**：
```bash
./scripts/resolve_exec_command.sh <squashfs_root_dir>
```

**参数**：
- `squashfs_root_dir`：squashfs-root 目录路径

**输出**：解析后的 binary name

### 3. parse_appimage_metadata.sh
**功能**：提取 AppImage 元数据

**用法**：
```bash
source ./scripts/parse_appimage_metadata.sh <appimage_file> <squashfs_root_dir>
```

**参数**：
- `appimage_file`：AppImage 文件路径
- `squashfs_root_dir`：squashfs-root 目录路径

**输出**：key=value 格式的元数据

### 4. parse_build_config.sh
**功能**：解析构建配置 JSON

**用法**：
```bash
source ./scripts/parse_build_config.sh <config.json>
```

**参数**：
- `config.json`：配置文件路径

**输出**：扁平化的 key=value 格式

## 配置说明

### 配置文件格式
```json
{
  "main": {
    "appimage_file": "/path/to/application.AppImage",
    "appimage_url": "",
    "app_name": "My Application",
    "package_id": "com.example.myapp",
    "description": "A sample application converted from AppImage",
    "exec_command": "",
    "icon_url": ""
  },
  "optional": {
    "app_version": "",
    "base_id": "org.deepin.base",
    "base_version": "25.2.2",
    "runtime_id": "org.deepin.runtime.dtk",
    "runtime_version": "25.2.2",
    "linyaps_arch": "x86_64",
    "output_dir": "./output"
  }
}
```

### 必填参数
- `appimage_file` 或 `appimage_url`（二选一）
- `app_name`：应用名称
- `package_id`：玲珑包 ID（反向域名格式）
- `description`：应用描述

### 可选参数
- `exec_command`：显式指定 Exec 命令
- `icon_url`：图标下载 URL
- `app_version`：版本号
- `base_id`/`base_version`：base 层配置
- `runtime_id`/`runtime_version`：runtime 层配置
- `linyaps_arch`：目标架构
- `output_dir`：输出目录

## 工作流程

### 阶段 1：输入验证
1. 验证 AppImage 文件存在且格式正确
2. 验证必填参数完整性
3. 验证 package_id 格式

### 阶段 2：AppImage 处理
1. 解压 AppImage 文件
2. 提取元数据（app_name, description, version 等）
3. 解析 Exec 命令

### 阶段 3：构建准备
1. 创建构建目录结构
2. 复制 AppImage 内容到 `lib/${APP_PREFIX}/`
3. 生成 wrapper 脚本

### 阶段 4：资源处理
1. 复制 desktop 文件和图标
2. 修复 Icon 路径为相对路径
3. 去重 desktop 文件

### 阶段 5：玲珑包生成
1. 生成 linglong.yaml 配置
2. 执行 ll-builder build
3. 导出 .layer 文件

## 设计决策

### 1. Wrapper 机制
- **选择**：保留 AppImage 原始目录结构
- **理由**：避免路径修改导致应用无法运行
- **实现**：wrapper 脚本 `cd lib/${APP_PREFIX} && ./AppRun $@`

### 2. Exec 命令处理
- **策略**：智能提取 + 显式覆盖
- **优先级**：用户指定 > 自动提取 > 扫描备用
- **约束**：不修改 desktop 文件的 Exec 字段

### 3. 版本号处理
- **策略**：多模式正则提取 + 格式标准化
- **格式**：确保 `X.Y.Z.W` 格式（ll-builder 要求）

### 4. 目录结构
- `binary/` 对应 `$prefix/`（files/）
- `squashfs-root` 安装到 `lib/${APP_PREFIX}/`
- `files_res/` 存放资源文件

## 测试

### 单元测试
```bash
# 测试 extract_appimage.sh
./scripts/extract_appimage.sh /path/to/app.AppImage ./test_output

# 测试 resolve_exec_command.sh
./scripts/resolve_exec_command.sh ./test_squashfs_root

# 测试 parse_appimage_metadata.sh
source ./scripts/parse_appimage_metadata.sh /path/to/app.AppImage ./test_squashfs_root
```

### 集成测试
```bash
# 测试完整流程
./scripts/extract_appimage.sh /path/to/app.AppImage ./temp
source ./scripts/parse_appimage_metadata.sh /path/to/app.AppImage ./temp/squashfs-root
exec_cmd=$(./scripts/resolve_exec_command.sh ./temp/squashfs_root)
```

### 端到端测试
```bash
# 使用真实 AppImage 文件测试
./templates/pak_linyaps.sh \
  --src_path /path/to/app.AppImage \
  --package_id com.example.myapp \
  --app_name "My Application" \
  --description "Test application" \
  --output_dir ./output
```

## 故障排除

### 1. AppImage 解压失败
**错误**：`文件不是有效的 AppImage`
**解决**：
- 检查文件格式：`file /path/to/app.AppImage`
- 确保文件可执行：`chmod +x /path/to/app.AppImage`
- 验证文件完整性

### 2. 未找到 desktop 文件
**错误**：`未找到 desktop 文件`
**解决**：
- 检查 AppImage 内容：`./app.AppImage --appimage-extract`
- 查看 `squashfs-root/` 目录内容
- 某些 AppImage 可能没有 desktop 文件

### 3. Exec 命令提取失败
**错误**：`无法从 Exec= 中提取命令`
**解决**：
- 使用 `exec_command` 参数显式指定
- 检查 desktop 文件格式
- 查看支持的 Exec 模式

### 4. 版本号提取失败
**错误**：`无法从文件名提取版本号`
**解决**：
- 使用 `app_version` 参数显式指定
- 重命名文件包含版本号
- 使用默认版本号 `1.0.0.0`

## 相关链接

- [玲珑官方文档](https://linglong.dev/)
- [AppImage 官网](https://appimage.org/)
- [ll-builder 文档](https://linglong.dev/docs/developer/ll-builder)
- [tar-linyaps 技能](../tar-linyaps/)
- [ll-pica 工具](../../examples-dev/linglong-pica/)

## 贡献指南

### 报告问题
1. 提供详细的错误信息
2. 包含 AppImage 文件信息
3. 提供配置文件内容
4. 附上日志输出

### 提交改进
1. Fork 项目
2. 创建功能分支
3. 提交 Pull Request
4. 添加测试用例

### 代码规范
- 遵循现有代码风格
- 添加必要的注释
- 更新相关文档
- 保持向后兼容

## 版本历史

### v1.0.0（当前版本）
- 初始版本发布
- 支持基本 AppImage 转换
- 实现 wrapper 机制
- 支持多种 Exec 模式
- 智能版本号提取

## 许可证

本项目采用 MIT 许可证，详见 [LICENSE](../../LICENSE) 文件。

## 联系方式

- 问题反馈：[GitHub Issues](https://github.com/your-repo/issues)
- 邮件联系：your-email@example.com
- 社区论坛：[玲珑社区](https://forum.linglong.dev/)

## 致谢

感谢以下项目和贡献者：
- [AppImage 项目](https://appimage.org/)
- [玲珑项目](https://linglong.dev/)
- [ll-pica 工具](https://github.com/nicman23/ll-pica)
- [tar-linyaps 技能](../tar-linyaps/)
- 所有贡献者和用户