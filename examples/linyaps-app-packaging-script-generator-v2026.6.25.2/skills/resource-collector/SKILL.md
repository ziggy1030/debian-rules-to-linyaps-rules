---
name: resource-collector
description: >
  从deb包解压后的目录中提取应用资源文件（desktop文件、图标、appdata、补全脚本等），
  按照玲珑打包规范整理到 files_res/ 目录结构中。
user-invocable: false
---

# 资源收集器

## 功能说明

从deb包解压后的目录中提取应用资源文件（desktop文件、图标、appdata、补全脚本等），按照玲珑打包规范整理到 `files_res/` 目录结构中。

## 触发场景

- 需要从deb中提取desktop文件
- 需要收集应用图标
- 需要整理资源文件到规范目录结构
- 需要验证资源文件合规性

## 工作流程

### 1. 扫描资源文件

从deb解压目录扫描各类资源：

```python
import os
from pathlib import Path

def scan_resources(data_path: str) -> dict:
    """扫描deb解压目录中的资源文件"""
    resources = {
        'desktop_files': [],
        'icons': [],
        'appdata': [],
        'mime': [],
        'bash_completion': [],
        'zsh_completion': [],
        'pixmaps': [],
        'binaries': []
    }
    
    data_dir = Path(data_path)
    
    # 扫描desktop文件
    for f in data_dir.rglob('*.desktop'):
        if 'applications' in str(f):
            resources['desktop_files'].append(str(f))
    
    # 扫描图标（分开收集 icons 和 pixmaps，便于后续处理）
    for ext in ['*.png', '*.svg', '*.svgz', '*.jpg', '*.xpm']:
        for f in data_dir.rglob(ext):
            if 'icons' in str(f):
                resources['icons'].append(str(f))
            elif 'pixmaps' in str(f):
                resources['pixmaps'].append(str(f))
    
    # 扫描appdata/metainfo
    for f in data_dir.rglob('*.appdata.xml'):
        resources['appdata'].append(str(f))
    for f in data_dir.rglob('*.metainfo.xml'):
        resources['appdata'].append(str(f))
    
    # 扫描MIME类型定义
    for f in data_dir.rglob('*.xml'):
        if 'mime' in str(f):
            resources['mime'].append(str(f))
    
    # 扫描补全脚本
    for f in data_dir.rglob('*'):
        if 'bash-completion' in str(f):
            resources['bash_completion'].append(str(f))
        if 'zsh' in str(f) and 'vendor-completions' in str(f):
            resources['zsh_completion'].append(str(f))
    
    return resources
```

### 2. 整理到 files_res 目录

按照FHS规范整理资源：

```bash
# 目标目录结构
files_res/
└── share/
    ├── applications/           # desktop文件
    │   └── com.example.app.desktop
    ├── icons/                  # 图标（lycaps 只接受此目录）
    │   └── hicolor/
    │       ├── 48x48/apps/     # ← 来自 pixmaps 的 xpm 图标
    │       ├── 128x128/apps/   # ← 来自 pixmaps 的 png 图标（默认尺寸）
    │       ├── 256x256/apps/   # ← 来自 pixmaps 的 png 图标
    │       ├── scalable/apps/  # ← 来自 pixmaps 的 svg 图标
    │       └── ...
    ├── appdata/                # 应用数据
    │   └── com.example.app.appdata.xml
    ├── mime/                   # MIME类型
    │   └── packages/
    ├── bash-completion/        # Bash补全
    │   └── completions/
    ├── zsh/                    # Zsh补全
    │   └── vendor-completions/
    └── pixmaps/                # 像素图（向后兼容保留，图标已同步到 icons/hicolor）
```

### 3. 复制资源文件

```python
import shutil
from pathlib import Path

def copy_resources(resources: dict, target_dir: str, package_id: str):
    """复制资源文件到目标目录"""
    share_dir = Path(target_dir) / 'share'
    
    # 复制desktop文件
    for src in resources['desktop_files']:
        dst = share_dir / 'applications' / Path(src).name
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        # 修改desktop文件中的Icon和Exec路径
        fix_desktop_file(dst, package_id)
    
    # 复制图标（来自 icons/ 目录，保持相对路径结构）
    for src in resources['icons']:
        # 保持相对路径结构
        rel_path = extract_icon_relative_path(src)
        dst = share_dir / 'icons' / rel_path
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    
    # 处理 pixmaps 图标：迁移到 icons/hicolor/
    # linyaps 只接受 icons/hicolor 作为图标目录
    # 当 icons/ 为空而 pixmaps/ 不为空时，pixmaps 是唯一的图标来源，必须迁移到 hicolor
    # 当 icons/ 不为空时，pixmaps 仍需迁移到 hicolor 作为补充（避免 desktop Icon= 引用找不到图标）
    if resources['pixmaps']:
        icons_hicolor = share_dir / 'icons' / 'hicolor'
        icons_hicolor.mkdir(parents=True, exist_ok=True)
        
        for src in resources['pixmaps']:
            src_path = Path(src)
            # 根据图标格式确定目标目录
            if src_path.suffix == '.svg':
                target_dir = icons_hicolor / 'scalable' / 'apps'
            elif src_path.suffix == '.xpm':
                target_dir = icons_hicolor / '48x48' / 'apps'  # xpm 默认 48x48
            else:
                # PNG/JPG：尝试从文件名推断尺寸，无法推断时默认 128x128
                size = detect_icon_size_from_filename(src_path.name)
                target_dir = icons_hicolor / size / 'apps'
            
            target_dir.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, target_dir / src_path.name)
        
        # 向后兼容：同时保留 pixmaps 目录
        pixmaps_dir = share_dir / 'pixmaps'
        pixmaps_dir.mkdir(parents=True, exist_ok=True)
        for src in resources['pixmaps']:
            shutil.copy2(src, pixmaps_dir / Path(src).name)
    
    # 复制appdata
    for src in resources['appdata']:
        dst = share_dir / 'appdata' / f'{package_id}.appdata.xml'
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    
    # 复制其他资源...
```

#### 3.1 辅助函数：从文件名推断图标尺寸

```python
import re

def detect_icon_size_from_filename(filename: str) -> str:
    """从文件名推断图标尺寸，用于 pixmaps→hicolor 迁移时确定目标目录。
    
    推断优先级：
    1. 匹配 NxN 格式（如 256x256、48x48）
    2. 匹配单独数字（如 48、128）
    3. 无法推断时返回默认值 128x128
    
    示例：
        "trae-cn-256x256.png" → "256x256"
        "app-icon-48.png"     → "48x48"
        "myapp.png"           → "128x128"（默认）
    """
    # 优先匹配 NxN 格式
    size_match = re.search(r'(\d{2,3})x(\d{2,3})', filename)
    if size_match:
        return f"{size_match.group(1)}x{size_match.group(2)}"
    # 其次匹配单独数字
    size_match = re.search(r'(\d{2,3})(?=\D|$)', filename)
    if size_match:
        s = size_match.group(1)
        return f"{s}x{s}"
    # 默认 128x128
    return "128x128"
```

### 4. 修复desktop文件

```python
def fix_desktop_file(desktop_path: str, package_id: str):
    """修复desktop文件中的Icon路径，使其符合玲珑规范
    
    ⚠️ 注意：此函数只修复 Icon 路径，不修改 Exec 路径！
    Exec 路径由 pak_linyaps.sh 在构建时通过 wrapper 机制自动处理。
    """
    with open(desktop_path, 'r') as f:
        content = f.read()
    
    # 修复Icon路径为相对路径
    # Icon=/usr/share/icons/xxx -> Icon=xxx
    content = re.sub(r'Icon=/.*?/([^/]+)\.(png|svg)', r'Icon=\1', content)
    
    # ⚠️ 不修改 Exec 路径！
    # Exec 路径由 pak_linyaps.sh 在构建时通过 wrapper 机制自动处理
    # 提前修改 Exec 会导致 wrapper 机制失效
    # 
    # wrapper 机制会：
    # 1. 从 desktop 文件自动提取 binary_name
    # 2. 创建 wrapper 脚本 (bin/${binary_name}.wrapper)
    # 3. 自动更新 linglong.yaml 的 command 字段
    # 4. 自动更新 desktop 文件的 Exec 字段
    
    with open(desktop_path, 'w') as f:
        f.write(content)
```

**⚠️ 重要警告：**
- **只修复 Icon 路径**，将绝对路径改为相对路径
- **禁止修改 Exec 路径**，Exec 字段由 `pak_linyaps.sh` 在构建时通过 wrapper 机制自动处理
- **提前修改 Exec 会导致 wrapper 机制失效**，导致应用无法正确启动
- `linglong.yaml` 的 `command` 字段也由 wrapper 机制自动设置，不要手动修改

### 5. 验证资源合规性

调用 `common-data-verify.py` 验证：

```bash
python3 common-data-verify.py <files_res_dir> --json --output report.json
```

验证项：
- desktop文件Icon/Exec使用相对路径
- 图标目录结构符合规范
- 图标格式一致性
- 二进制文件可执行

## 输出数据结构

```json
{
  "status": "success",
  "target_dir": "CI_ll_com.example.app/templates/files_res",
  "collected": {
    "desktop_files": 1,
    "icons": 12,
    "appdata": 1,
    "mime": 1,
    "bash_completion": 1,
    "zsh_completion": 1
  },
  "validation": {
    "passed": true,
    "checks": {
      "desktop_files": {"status": "passed", "details": []},
      "icons": {"status": "passed", "details": []},
      "binaries": {"status": "passed", "details": []}
    }
  }
}
```

## 资源映射规则

| deb路径 | files_res路径 | 说明 |
|--------|--------------|------|
| `usr/share/applications/*.desktop` | `share/applications/` | desktop文件 |
| `usr/share/icons/hicolor/*/apps/*` | `share/icons/hicolor/*/apps/` | 图标 |
| `usr/share/pixmaps/*` | `share/icons/hicolor/<size>/apps/` | 像素图（自动迁移到 hicolor） |
| `usr/share/metainfo/*.xml` | `share/appdata/` | 应用数据 |
| `usr/share/mime/packages/*` | `share/mime/packages/` | MIME定义 |
| `usr/share/bash-completion/completions/*` | `share/bash-completion/completions/` | Bash补全 |
| `usr/share/zsh/vendor-completions/*` | `share/zsh/vendor-completions/` | Zsh补全 |

## 注意事项

1. **desktop文件只修复Icon路径**，禁止修改 Exec 路径（由 wrapper 机制处理）
2. 图标目录结构必须符合hicolor规范
3. appdata文件重命名为 `{package_id}.appdata.xml`
4. 验证失败时记录问题，等待修复skill处理
5. 保留原始文件权限和符号链接
6. **pixmaps 图标自动迁移到 `icons/hicolor/`**：lycaps 只接受 `icons/hicolor` 作为图标目录。来自 `pixmaps/` 的图标会根据格式自动放置到 `hicolor/<size>/apps/`（SVG→`scalable`，XPM→`48x48`，PNG/JPG→从文件名推断尺寸，默认 `128x128`），同时保留 `pixmaps/` 目录向后兼容

## ⚠️ Agent 注意事项

**LLM Agent 在执行资源收集时必须遵守以下规则：**

1. **禁止修改 Exec 字段**：desktop 文件的 Exec 字段由 `pak_linyaps.sh` 在构建时通过 wrapper 机制自动处理
2. **禁止修改 command 字段**：linglong.yaml 的 command 字段由 `pak_linyaps.sh` 在构建时通过 wrapper 机制自动设置
3. **只修复 Icon 路径**：将 Icon 的绝对路径改为相对路径
4. **不要提前优化**：wrapper 机制需要原始的 Exec 路径来正确提取 binary_name

**wrapper 机制工作流程**（由 `pak_linyaps.sh` 在构建时执行）：
1. 从 desktop 文件自动提取 `binary_name`
2. 在 `binary/` 目录下查找实际二进制文件
3. 创建 wrapper 脚本（`bin/${binary_name}.wrapper`）
4. 自动更新 `linglong.yaml` 的 `command` 字段为 wrapper 路径
5. 自动更新 desktop 文件的 `Exec=` 字段为 wrapper 路径

**提前修改 Exec 的后果**：
- wrapper 机制无法正确提取 binary_name
- 导致 wrapper 脚本创建失败
- 应用无法正确启动
