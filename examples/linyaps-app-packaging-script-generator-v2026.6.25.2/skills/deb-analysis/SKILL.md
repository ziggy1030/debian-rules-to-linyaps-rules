---
name: deb-analysis
description: >
  解析Debian软件包(.deb)文件，提取元数据信息并解压文件内容，
  为后续玲珑打包工程生成提供基础数据。
user-invocable: false
---

# Deb包分析

## 功能说明

解析Debian软件包(.deb)文件，提取元数据信息并解压文件内容，为后续玲珑打包工程生成提供基础数据。

## 触发场景

- 需要分析deb包的基本信息（包名、版本、架构、依赖）
- 需要解压deb文件获取内部文件结构
- 需要提取deb中的desktop文件、图标等资源
- 批量处理前需要验证deb包的有效性

## 批量初始化

使用 `batch_init.sh` 脚本可以批量创建多个 deb 应用的打包工程：

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

### 1. 验证deb文件

```bash
# 检查文件是否存在且为有效deb包
file <deb_file>
# 应输出: Debian binary package (format 2.0)
```

### 2. 提取deb元数据

调用 `scripts/deb_to_linglong.py` 的 `extract_deb_info()` 函数：

```python
import sys
sys.path.insert(0, "scripts")
from deb_to_linglong import extract_deb_info

deb_info = extract_deb_info("/path/to/package.deb")
# 返回字典包含:
# - Package: 包名
# - Version: 版本号
# - Architecture: 架构 (amd64/arm64/all)
# - Description: 描述
# - Depends: 依赖列表
```

或使用命令行：

```bash
cd scripts
python3 deb_to_linglong.py <deb_file> --base <base> --extract-dir <extract_dir>
```

### 3. 解压deb文件

调用 `scripts/deb_to_linglong.py` 的 `extract_deb_archive()` 函数：

```python
import sys
sys.path.insert(0, "scripts")
from deb_to_linglong import extract_deb_archive

control_dir, data_dir = extract_deb_archive("/path/to/package.deb", "/tmp/extracted")
# control_dir: 控制信息目录
# data_dir: 数据文件目录 (包含usr/等)
```

### 4. 解析依赖关系

```python
import sys
sys.path.insert(0, "scripts")
from deb_to_linglong import parse_depends

depends = parse_depends("libssl1.1 (>= 1.1.1), libcurl4:amd64, libc6")
# 返回: ["libssl1.1", "libcurl4", "libc6"]
```

### 5. 版本转换

```python
import sys
sys.path.insert(0, "scripts")
from deb_to_linglong import convert_version_to_linglong

ll_version = convert_version_to_linglong("1.85.2-1")
# 返回: "1.85.2.1" (玲珑格式 x.x.x.x)
```

### 6. 架构映射

```python
import sys
sys.path.insert(0, "scripts")
from deb_to_linglong import map_architecture

ll_arch = map_architecture("amd64")  # 返回 "x86_64"
ll_arch = map_architecture("arm64")  # 返回 "aarch64"
```

## 输出数据结构

```json
{
  "package_name": "com.example.app",
  "deb_package": "example-app",
  "version": "1.0.0",
  "ll_version": "1.0.0.0",
  "architecture": "amd64",
  "ll_architecture": "x86_64",
  "description": "Example Application",
  "depends": ["libssl1.1", "libcurl4", "libc6"],
  "extract_path": "/tmp/extracted/example-app",
  "control_path": "/tmp/extracted/example-app/control",
  "data_path": "/tmp/extracted/example-app/data",
  "files": {
    "desktop_files": ["usr/share/applications/example.desktop"],
    "icons": ["usr/share/icons/hicolor/48x48/apps/example.png"],
    "binaries": ["usr/bin/example"],
    "appdata": ["usr/share/metainfo/example.appdata.xml"]
  }
}
```

## 错误处理

| 错误类型 | 处理方式 |
|---------|---------|
| 文件不存在 | 返回错误，提示用户检查路径 |
| 非deb文件 | 返回错误，提示文件格式不正确 |
| 解压失败 | 检查ar/tar工具是否可用 |
| 元数据缺失 | 使用默认值，记录警告 |

## 依赖工具

- `dpkg` - 用于解析deb元数据 (`dpkg -I`)
- `ar` - 用于解压deb归档
- `tar` - 用于解压control.tar和data.tar
- Python库: `yaml` (PyYAML)

## 注意事项

1. 解压目录应使用临时目录，处理完成后可清理
2. 多架构deb (Architecture: all) 需要根据目标架构指定
3. 依赖解析会去除版本约束，仅保留包名
4. 版本转换会去除epoch和后缀，补齐到4位数字

## 后续步骤

deb 包分析完成后，应调用 `linglong-project-gen` skill 生成玲珑打包工程：

```
参考: skills/linglong-project-gen/SKILL.md
```

**重要：** 生成 `pak_linyaps.sh` 时，务必遵循 `linglong-project-gen` skill 中的"常见错误警告"章节，避免模板路径和变量遗漏问题。
