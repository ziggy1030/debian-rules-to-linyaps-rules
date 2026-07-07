# linyaps-app-packaging-script-generator 使用指南

## 概述

本工具集用于将Debian软件包(.deb)批量转换为玲珑(Linglong)便捷打包脚本，实现自动化打包适配。
\* 此文档是项目文档， 直接使用示例见`NewToHere.md`

## 目录结构

```
common-data-verify/
├── .agents/                          # Agent和Skills定义
│   ├── agents/
│   │   └── deb-linglong-packer.agent.md  # 主Agent
│   └── skills/
│       ├── deb-analysis/SKILL.md         # Deb包分析
│       ├── linglong-project-gen/SKILL.md # 工程生成
│       ├── resource-collector/SKILL.md   # 资源收集
│       ├── compat-testing/SKILL.md       # 兼容性测试
│       ├── linglong-fix/SKILL.md         # 问题修复
│       ├── tar-linyaps/SKILL.md          # Tar包转换
│       └── appimage-linyaps/SKILL.md     # AppImage转换
├── config/
│   └── packages.csv                      # 批量配置文件
├── deb_to_linglong.py                    # Deb解析工具
├── common-data-verify.py                 # 目录结构验证
├── validate_linglong_yaml.py             # YAML格式验证
└── demos/
│   └── compat_checker.py                 # 兼容性检测
├── for-multica/                          # Multica 平台整合
│   ├── agent-config.json                 # 獨立全局配置
│   └── agent.md                          # Agent 定義（含執行期合約）
└── docs/
    └── deb-linglong-packer.README.md     # 多客户端安装说明
```

## 快速开始

### 1. 使用Agent批量处理

在VS Code Chat中输入：

```
@deb-linglong-packer /path/to/deb/directory
```

或使用CSV配置：

```
@deb-linglong-packer config/packages.csv
```

### 2. 单独使用Skills

#### Deb包分析
```
/deb-analysis /path/to/package.deb
```

#### 工程生成
```
/linglong-project-gen com.example.app
```

#### 资源收集
```
/resource-collector /tmp/extracted CI_ll_com.example.app
```

#### 兼容性测试
```
/compat-testing CI_ll_com.example.app
```

#### 问题修复
```
/linglong-fix CI_ll_com.example.app
```

#### Tar包转换
```
/tar-linyaps /path/to/package.tar.gz
```

#### AppImage转换
```
/appimage-linyaps /path/to/application.AppImage
```

## CSV配置格式

```csv
package_name,deb_path,architecture,base,runtime,push
com.visualstudio.code,/path/to/code.deb,x86_64,org.deepin.base/23.1.0,org.deepin.runtime.dtk/23.1.0,true
```

| 列名 | 说明 | 示例 |
|-----|------|------|
| package_name | 玲珑包ID | com.visualstudio.code |
| deb_path | deb文件路径 | /path/to/code.deb |
| architecture | 目标架构 | x86_64 或 aarch64 |
| base | 基础运行时 | org.deepin.base/23.1.0 |
| runtime | 应用运行时 | org.deepin.runtime.dtk/23.1.0 |
| push | 是否自动推送 | true 或 false |

### 多架构支持

同一包名可指定多行：

```csv
package_name,deb_path,architecture,base,runtime,push
com.visualstudio.code,/path/to/code_amd64.deb,x86_64,org.deepin.base/23.1.0,org.deepin.runtime.dtk/23.1.0,true
com.visualstudio.code,/path/to/code_arm64.deb,aarch64,org.deepin.base/23.1.0,org.deepin.runtime.dtk/23.1.0,true
```

## AppImage转换

`appimage-linyaps` 技能用于将 AppImage 应用程序转换为玲珑包格式。

### 功能特性
- **AppImage 解压**：使用 `--appimage-extract` 安全解压 AppImage 文件
- **元数据提取**：从 desktop 文件和文件名中智能提取应用信息
- **Exec 命令解析**：准确提取 Exec 命令，支持多种 AppImage 变体
- **Wrapper 机制**：保留 AppImage 原始目录结构，通过 wrapper 脚本执行

### 使用示例

#### 基本使用
```
/appimage-linyaps /path/to/application.AppImage
```

#### 使用配置文件
```json
{
  "main": {
    "appimage_file": "/path/to/application.AppImage",
    "app_name": "My Application",
    "package_id": "com.example.myapp",
    "description": "A sample application converted from AppImage"
  },
  "optional": {
    "app_version": "1.0.0.0",
    "base_id": "org.deepin.base",
    "base_version": "25.2.2",
    "runtime_id": "org.deepin.runtime.dtk",
    "runtime_version": "25.2.2",
    "linyaps_arch": "x86_64",
    "output_dir": "./output"
  }
}
```

### 详细文档
- [使用指南](docs/appimage-linyaps.README.md)
- [设计文档](appimage-linyaps.design.md)
- [实现方案](skills/appimage-linyaps/IMPLEMENTATION.md)
- [实现流程](skills/appimage-linyaps/IMPLEMENTATION_FLOW.md)

## 批量初始化

使用 `batch_init.sh` 脚本可以批量创建多个应用的打包工程：

### 使用方法

```bash
# CSV 格式批量初始化
./scripts/batch_init.sh tasks.csv --projects_root=./projects

# JSON 格式批量初始化
./scripts/batch_init.sh task.json --projects_root=./projects

# 仅生成项目结构，不执行打包
./scripts/batch_init.sh tasks.csv --dry-run
```

### CSV 格式示例

```csv
包名,架构,版本,下载地址
com.visualstudio.code,x86_64,1.85.0,https://update.code.visualstudio.com/1.85.0/linux-deb-x64/stable
org.mozilla.firefox,x86_64,151.0.2,https://ftp.mozilla.org/pub/firefox/releases/151.0.2/linux-x86_64/en-US/firefox-151.0.2.tar.bz2
```

### JSON 格式示例

```json
{
  "global": {
    "projects_root": "./projects"
  },
  "tasks": [
    {
      "pkgName": "com.visualstudio.code",
      "arch": "x86_64",
      "orig_version": "1.85.0",
      "src_url": "https://update.code.visualstudio.com/1.85.0/linux-deb-x64/stable"
    },
    {
      "pkgName": "org.mozilla.firefox",
      "arch": "x86_64",
      "orig_version": "151.0.2",
      "src_url": "https://ftp.mozilla.org/pub/firefox/releases/151.0.2/linux-x86_64/en-US/firefox-151.0.2.tar.bz2"
    }
  ]
}
```

### 输出目录结构

批量初始化会为每个任务创建 `CI_ll_<pkgName>` 目录，包含：

```
projects/
├── CI_ll_com.visualstudio.code/
│   ├── linglong.yaml          # 玲珑打包配置文件
│   ├── pak_linyaps.sh         # 自动化打包脚本
│   ├── scripts/               # 辅助脚本目录
│   ├── config/                # 配置文件目录
│   │   └── base_runtime_whitelist.conf
│   └── templates/
│       └── files_res/         # 资源文件目录
└── CI_ll_org.mozilla.firefox/
    └── ...
```

### 示例文件

- `examples/batch_init_example.csv` - CSV 格式示例
- `examples/batch_init_example.json` - JSON 格式示例

## 工作流程

```
┌─────────────────────────────────────────────────────────────┐
│                    Deb玲珑化批量打包流程                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. Deb分析 (deb-analysis)                                    │
│    - 解析deb元数据                                           │
│    - 解压deb文件                                             │
│    - 提取文件结构                                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. 工程生成 (linglong-project-gen)                           │
│    - 创建 CI_ll_<package_id> 目录                            │
│    - 生成 linglong.yaml                                      │
│    - 生成 pak_linyaps.sh                                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. 资源收集 (resource-collector)                             │
│    - 提取desktop、icons、appdata                             │
│    - 整理到 files_res/                                       │
│    - 验证资源合规性                                           │
│    ⏸️  等待用户确认                                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. 兼容性测试 (compat-testing)                               │
│    - 验证linglong.yaml格式                                   │
│    - 验证资源目录结构                                         │
│    - 执行打包测试                                             │
│    - 运行兼容性检测                                           │
└─────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    │                   │
              测试通过 ▼             测试失败 ▼
┌───────────────────────────┐  ┌───────────────────────────┐
│ 5. 完成                    │  │ 5. 问题修复 (linglong-fix) │
│    - 保存工程              │  │    - 修复YAML格式          │
│    - 清理临时文件          │  │    - 修复desktop文件       │
│    - 更新任务状态          │  │    - 修复图标目录          │
└───────────────────────────┘  │    - 重新测试              │
                                └───────────────────────────┘
```

## 输出工程结构

```
CI_ll_com.example.app/
├── pak_linyaps.sh              # 打包脚本
├── src/                        # 源文件目录
│   └── app_1.0.0_amd64.deb     # 放置deb包
├── templates/
│   ├── linglong.yaml           # 玲珑配置模板
│   └── files_res/              # 资源文件
│       └── share/
│           ├── applications/
│           │   └── com.example.app.desktop
│           ├── icons/
│           │   └── hicolor/
│           │       ├── 48x48/apps/
│           │       └── scalable/apps/
│           ├── appdata/
│           │   └── com.example.app.appdata.xml
│           └── ...
├── bins/                       # 构建输出
│   └── *binary.layer
└── reports/                    # 测试报告
    ├── yaml_validation.json
    ├── structure_validation.json
    └── build.log
```

## 命令行工具使用

### deb_to_linglong.py

```bash
# 基本用法
python3 deb_to_linglong.py package.deb --base org.deepin.base/23.1.0

# 完整参数
python3 deb_to_linglong.py package.deb \
  --base org.deepin.base/23.1.0 \
  --runtime org.deepin.runtime.dtk/23.1.0 \
  --extract-dir /tmp/extracted \
  --output-dir ./output \
  --arch-map "amd64=x86_64,arm64=aarch64"
```

### common-data-verify.py

```bash
# 验证目录结构
python3 common-data-verify.py ./files_res

# 输出JSON报告
python3 common-data-verify.py ./files_res --json --output report.json
```

### validate_linglong_yaml.py

```bash
# 验证YAML格式
python3 validate_linglong_yaml.py \
  --input linglong.yaml \
  --exec-name "app %U"

# 带版本检查
python3 validate_linglong_yaml.py \
  --input linglong.yaml \
  --exec-name "app %U" \
  --last-ver "1.0.0.0" \
  --json
```

### compat_checker.py

```python
from demos.compat_checker import CompatChecker
from pathlib import Path

checker = CompatChecker(
    build_dir=Path("/path/to/build"),
    enable_compat_check=True,
    timeout=30
)

success, message = checker.check()
print(f"Status: {checker.get_status()}")
```

## 打包脚本使用

```bash
cd CI_ll_com.example.app

# 准备源文件
cp /path/to/package.deb src/

# 执行打包
./pak_linyaps.sh \
  --linyaps_arch=x86_64 \
  --origin_version=1.0.0 \
  --src_path=src/package.deb \
  --output_dir=bins

# 查看结果
ls bins/
```

## 常见问题

### Q: desktop文件Icon路径错误？

A: 使用 `linglong-fix` skill 自动修复，或手动修改desktop文件：
```
Icon=/usr/share/icons/app.png  →  Icon=app
```

### Q: 构建失败提示缺少依赖？

A: 在 `linglong.yaml` 的 `buildext.apt.depends` 中添加缺失依赖。

### Q: 兼容性检测超时？

A: 超时(exit code 124)视为成功，表示应用正常启动并持续运行。

### Q: 多架构如何处理？

A: 在CSV中为同一包名指定多行，每行一个架构。

## 注意事项

1. **工程目录命名**: 必须遵循 `CI_ll_<package_id>` 格式
2. **CSV配置优先**: CSV值优先于自动检测值
3. **资源确认**: 资源收集后会暂停等待确认
4. **失败处理**: 遇到失败会暂停询问用户选择
5. **日志保存**: 所有测试日志保存在 `reports/` 目录

## 白名单配置

本工具支持 base/runtime 组合的白名单验证，确保只使用经过验证的合规组合。

### 白名单配置文件位置

| 级别 | 路径 | 说明 |
|-----|------|------|
| 全局（推荐） | `skills/config/base_runtime_whitelist.conf` | 所有 skill 和工程共享的权威来源 |
| Skill 级别 | `skills/linglong-project-gen/config/base_runtime_whitelist.conf` | 本地副本，生成工程时同步 |
| 工程级别 | `CI_ll_<package_id>/config/base_runtime_whitelist.conf` | 工程私有配置 |

### 白名单查找优先级

1. CLI 参数 `--whitelist` 指定的路径
2. 环境变量 `LINGLONG_WHITELIST_FILE` 指定的路径
3. 工程目录下 `config/base_runtime_whitelist.conf`
4. 脚本所在目录的 `config/base_runtime_whitelist.conf`（skill 级别）
5. `skills/config/base_runtime_whitelist.conf`（全局）⭐

### 白名单配置文件格式

```
# 格式：<base_id>/<base_version> <runtime_id>/<runtime_version> <描述>
org.deepin.base/25.2.2	org.deepin.runtime.dtk/25.2.2	Qt6/DTK6 应用（推荐默认）
org.deepin.base/25.2.2	org.deepin.runtime.webengine/25.2.2	Qt6 WebEngine 应用
org.deepin.base/25.2.2	-	纯 base 应用（无 runtime）
```

### 验证脚本

```bash
# 验证工程的 base/runtime 配置
./skills/linglong-project-gen/scripts/validate_base_runtime.sh CI_ll_com.example.app

# 自动修复模式
./skills/linglong-project-gen/scripts/validate_base_runtime.sh CI_ll_com.example.app --fix
```

## 相关文档

- [deb_to_linglong 工具说明](../docs/deb_to_linglong.README.md)
- [common-data-verify 工具说明](../docs/common-data-verify.README.md)
- [validate_linglong_yaml 工具说明](../docs/validate_linglong_yaml.README.md)
- [白名单配置文件](../skills/config/base_runtime_whitelist.conf)
- [Base/Runtime 验证脚本](../skills/linglong-project-gen/scripts/validate_base_runtime.sh)
