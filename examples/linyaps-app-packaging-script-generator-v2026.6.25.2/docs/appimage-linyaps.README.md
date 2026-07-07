# AppImage Linyaps - 使用指南

## 概述

`appimage-linyaps` 是一个技能（Skill），用于将 AppImage 应用程序转换为玲珑（Linyaps）包格式。该技能基于 `tar-linyaps` 技能架构，专门针对 AppImage 的特性进行优化。

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

### 版本号提取
支持多种版本号格式：
- `-v1.2.3` 或 `-V1.2.3`
- `-1.2.3-` 或 `_1.2.3_`
- `1.2.3` 在文件名开头
- 任何位置的 `1.2.3.4` 格式

## 安装配置

### 方式一：OpenCode（推荐）

#### 1. 复制 Agent 文件

将 `appimage-linyaps` 技能复制到 OpenCode 的 skills 目录：

```bash
# 项目级配置
mkdir -p .opencode/skills
cp -r skills/appimage-linyaps .opencode/skills/

# 或全局配置
mkdir -p ~/.config/opencode/skills
cp -r skills/appimage-linyaps ~/.config/opencode/skills/
```

#### 2. Skills 自动发现

Skills 已通过 `.opencode/skills/` 符号链接自动就位，**无需手动复制**。

仓库中 `.opencode/skills/` 目录包含指向 `skills/` 源目录的符号链接，OpenCode 的 skill 工具会自动发现并加载。

```
.opencode/skills/
├── appimage-linyaps       → ../../skills/appimage-linyaps
├── deb-analysis           → ../../skills/deb-analysis
├── resource-collector     → ../../skills/resource-collector
├── linglong-project-gen   → ../../skills/linglong-project-gen
├── compat-testing         → ../../skills/compat-testing
├── linglong-fix           → ../../skills/linglong-fix
├── project-structure-validator → ../../skills/project-structure-validator
└── tar-linyaps            → ../../skills/tar-linyaps
```

#### 3. 目录结构

最终结构应如下：

```
项目目录/
├── .opencode/
│   └── skills/
│       └── appimage-linyaps → ../../skills/appimage-linyaps
├── skills/
│   └── appimage-linyaps/
│       ├── SKILL.md
│       ├── scripts/
│       ├── templates/
│       ├── examples/
│       └── config/
└── ...
```

### 方式二：Claude Code / Cline

#### 1. 复制 Skill 文件

将 `skills/appimage-linyaps` 目录复制到项目的 `.claude/skills/` 或 `.cline/skills/` 目录：

```bash
# Claude Code
mkdir -p .claude/skills
cp -r skills/appimage-linyaps .claude/skills/

# Cline
mkdir -p .cline/skills
cp -r skills/appimage-linyaps .cline/skills/
```

#### 2. 验证安装

确保目录结构正确：

```bash
ls -la .claude/skills/appimage-linyaps/
# 或
ls -la .cline/skills/appimage-linyaps/
```

## 使用方法

### 1. 准备 AppImage 文件

确保 AppImage 文件存在且可执行：

```bash
# 检查文件格式
file /path/to/application.AppImage

# 设置可执行权限
chmod +x /path/to/application.AppImage
```

### 2. 创建配置文件

使用示例配置文件作为模板：

```bash
cp skills/appimage-linyaps/examples/build_config.example.json my_app.json
```

编辑配置文件：

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

### 3. 运行转换

在 OpenCode 中：

```
使用 appimage-linyaps 技能转换 AppImage 文件
```

或直接运行脚本：

```bash
# 解析配置
source skills/appimage-linyaps/scripts/parse_build_config.sh my_app.json

# 解压 AppImage
skills/appimage-linyaps/scripts/extract_appimage.sh /path/to/application.AppImage ./temp

# 提取元数据
source skills/appimage-linyaps/scripts/parse_appimage_metadata.sh /path/to/application.AppImage ./temp/squashfs-root

# 解析 Exec 命令
exec_cmd=$(skills/appimage-linyaps/scripts/resolve_exec_command.sh ./temp/squashfs-root)
```

## 配置参数说明

### 必填参数（main 分组）

| 参数 | 说明 | 示例 |
|------|------|------|
| `appimage_file` | AppImage 本地文件路径 | `/path/to/app.AppImage` |
| `appimage_url` | AppImage 下载 URL | `https://example.com/app.AppImage` |
| `app_name` | 应用名称 | `My Application` |
| `package_id` | 玲珑包 ID（反向域名格式） | `com.example.myapp` |
| `description` | 应用描述 | `A sample application` |

**注意**：`appimage_file` 和 `appimage_url` 至少需要提供一个。

### 可选参数（main 分组）

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `exec_command` | 显式指定 Exec 命令 | 自动提取 |
| `icon_url` | 图标下载 URL | 从 AppImage 提取 |

### 可选参数（optional 分组）

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `app_version` | 版本号 | 从文件名提取 |
| `base_id` | base 层 ID | `org.deepin.base` |
| `base_version` | base 层版本 | `25.2.2` |
| `runtime_id` | runtime 层 ID | `org.deepin.runtime.dtk` |
| `runtime_version` | runtime 层版本 | `25.2.2` |
| `linyaps_arch` | 目标架构 | `x86_64` |
| `output_dir` | 输出目录 | `./output` |

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

## 目录结构说明

### 构建目录结构
```
build_dir/
├── binary/                    # 对应 $prefix/ (files/)
│   ├── lib/
│   │   └── ${APP_PREFIX}/
│   │       └── squashfs-root/ # 保留原始结构
│   └── usr/
│       └── bin/
│           └── ${binary_name} # wrapper 脚本
├── files_res/                 # 资源文件
│   ├── share/
│   │   ├── applications/      # desktop 文件
│   │   └── icons/             # 图标文件
│   └── ...
└── linglong.yaml              # 玲珑包配置
```

### 输出目录结构
```
output/
├── ${package_id}_${version}_${arch}.layer  # 玲珑包 layer 文件
└── ...
```

## 技术细节

### Wrapper 机制
```bash
#!/bin/bash
# wrapper 脚本内容
cd "$(dirname "$0")/lib/${APP_PREFIX}"
exec ./AppRun "$@"
```

### Exec 命令解析
支持多种 Exec 模式：
1. `Exec=AppRun %U` → 直接使用 AppRun
2. `Exec=AppRun.wrapped` → 使用 AppRun.wrapped
3. `Exec=myapp --gui` → 直接二进制执行
4. `Exec=${HERE}/usr/bin/myapp` → 替换 ${HERE} 为相对路径
5. `Exec="/path/to/AppRun" %U` → 移除引号和参数

### 版本号标准化
确保版本号为 `X.Y.Z.W` 格式：
- `1.2.3` → `1.2.3.0`
- `1.2` → `1.2.0.0`
- `1` → `1.0.0.0`

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

### 5. 构建失败
**错误**：`ll-builder build 失败`
**解决**：
- 检查 linglong.yaml 配置
- 验证 base 和 runtime 配置
- 查看详细错误日志

## 最佳实践

### 1. 文件命名
- 使用包含版本号的文件名：`MyApp-1.2.3.AppImage`
- 使用标准 AppImage 命名规范

### 2. 配置管理
- 使用配置文件而非命令行参数
- 版本控制配置文件
- 为不同环境使用不同配置

### 3. 测试验证
- 先在测试环境验证
- 检查生成的玲珑包功能
- 验证桌面集成（图标、菜单项）

### 4. 错误处理
- 查看详细日志
- 检查中间文件
- 使用调试模式

## 示例

### 示例 1：基本转换
```json
{
  "main": {
    "appimage_file": "/path/to/MyApp-1.2.3.AppImage",
    "app_name": "My Application",
    "package_id": "com.example.myapp",
    "description": "My awesome application"
  }
}
```

### 示例 2：完整配置
```json
{
  "main": {
    "appimage_file": "/path/to/MyApp-1.2.3.AppImage",
    "app_name": "My Application",
    "package_id": "com.example.myapp",
    "description": "My awesome application",
    "exec_command": "myapp --gui",
    "icon_url": "https://example.com/icon.png"
  },
  "optional": {
    "app_version": "1.2.3.0",
    "base_id": "org.deepin.base",
    "base_version": "25.2.2",
    "runtime_id": "org.deepin.runtime.dtk",
    "runtime_version": "25.2.2",
    "linyaps_arch": "x86_64",
    "output_dir": "./output"
  }
}
```

### 示例 3：使用 URL
```json
{
  "main": {
    "appimage_url": "https://example.com/MyApp-1.2.3.AppImage",
    "app_name": "My Application",
    "package_id": "com.example.myapp",
    "description": "My awesome application"
  }
}
```

## 相关链接

- [玲珑官方文档](https://linglong.dev/)
- [AppImage 官网](https://appimage.org/)
- [ll-builder 文档](https://linglong.dev/docs/developer/ll-builder)
- [tar-linyaps 技能](../skills/tar-linyaps/)

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

本项目采用 MIT 许可证，详见 [LICENSE](../LICENSE) 文件。

## 联系方式

- 问题反馈：[GitHub Issues](https://github.com/your-repo/issues)
- 邮件联系：your-email@example.com
- 社区论坛：[玲珑社区](https://forum.linglong.dev/)

## 致谢

感谢以下项目和贡献者：
- [AppImage 项目](https://appimage.org/)
- [玲珑项目](https://linglong.dev/)
- [ll-pica 工具](https://github.com/nicman23/ll-pica)
- [tar-linyaps 技能](../skills/tar-linyaps/)
- 所有贡献者和用户