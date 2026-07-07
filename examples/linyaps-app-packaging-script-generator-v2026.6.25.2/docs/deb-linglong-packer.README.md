# Deb Linglong Packer - 多客戶端使用指南

## 概述

`deb-linglong-packer` 是一个智能代理（Agent），用于批量将 Debian 软件包转换为玲珑（Linglong）打包工程。支持 OpenCode、Claude Code、Cline 等多种客户端环境。

## 安装配置

### 方式一：OpenCode（推荐）

#### 1. 复制 Agent 文件

将 `deb-linglong-packer.agent.md` 复制到 OpenCode 的 agents 目录：

```bash
# 项目级配置
mkdir -p .opencode/agents
cp agents/deb-linglong-packer.agent.md .opencode/agents/deb-linglong-packer.md

# 或全局配置
mkdir -p ~/.config/opencode/agents
cp agents/deb-linglong-packer.agent.md ~/.config/opencode/agents/deb-linglong-packer.md
```

#### 2. Skills 自动发现

Skills 已通过 `.opencode/skills/` 符号链接自动就位，**无需手动复制**。

仓库中 `.opencode/skills/` 目录包含指向 `skills/` 源目录的符号链接，OpenCode 的 skill 工具会自动发现并加载。

```
.opencode/skills/
├── deb-analysis           → ../../skills/deb-analysis
├── resource-collector     → ../../skills/resource-collector
├── linglong-project-gen   → ../../skills/linglong-project-gen
├── compat-testing         → ../../skills/compat-testing
├── linglong-fix           → ../../skills/linglong-fix
├── project-structure-validator → ../../skills/project-structure-validator
└── tar-linyaps            → ../../skills/tar-linyaps
```

> **注意**：所有子 skill 设置为 `user-invocable: false`，只能通过 agent 工作流间接使用，不可独立调用。

#### 3. 目录结构

最终结构应如下：

```
项目目录/
├── .opencode/
│   ├── agents/
│   │   └── deb-linglong-packer.md    # Agent 定义
│   └── skills/                        # 符号链接（自动发现）
│       ├── deb-analysis           → ../../skills/deb-analysis
│       ├── linglong-project-gen   → ../../skills/linglong-project-gen
│       ├── resource-collector     → ../../skills/resource-collector
│       ├── compat-testing         → ../../skills/compat-testing
│       ├── linglong-fix           → ../../skills/linglong-fix
│       ├── project-structure-validator → ../../skills/project-structure-validator
│       └── tar-linyaps            → ../../skills/tar-linyaps
├── skills/                            # 源文件（canonical 位置）
│   ├── deb-analysis/
│   ├── linglong-project-gen/
│   ├── resource-collector/
│   ├── compat-testing/
│   ├── linglong-fix/
│   ├── project-structure-validator/
│   └── tar-linyaps/
└── agents/
    └── deb-linglong-packer.agent.md
```

### 方式二：Claude Code

```bash
# 复制 skills 到 .claude/skills/
mkdir -p .claude/skills
cp -r skills/deb-analysis           .claude/skills/
cp -r skills/linglong-project-gen   .claude/skills/
cp -r skills/resource-collector     .claude/skills/
cp -r skills/compat-testing         .claude/skills/
cp -r skills/linglong-fix           .claude/skills/
cp -r skills/project-structure-validator .claude/skills/
```

> **注意**：Claude Code 没有内建的 `skill` 工具，Agent 会直接读取 `SKILL.md` 文件内容作为指令。

### 方式三：Cline

```bash
# 复制 skills 到 .clinerules/skills/ 或 .agents/skills/
mkdir -p .agents/skills
cp -r skills/deb-analysis           .agents/skills/
cp -r skills/linglong-project-gen   .agents/skills/
cp -r skills/resource-collector     .agents/skills/
cp -r skills/compat-testing         .agents/skills/
cp -r skills/linglong-fix           .agents/skills/
cp -r skills/project-structure-validator .agents/skills/
```

> **注意**：Cline 没有内建的 `skill` 工具，Agent 会直接读取 `SKILL.md` 文件内容作为指令。

## 使用方法

### OpenCode 环境

#### 方式一：@提及调用

在 OpenCode 中直接 @提及 agent：

```
@deb-linglong-packer 处理 ~/Downloads/debs/ 目录下的所有 deb 包
```

### 方式二：使用 Tab 切换

如果配置了 `mode: subagent`，可以使用 Tab 键在主代理和此代理之间切换。

### 方式三：在对话中调用

```
请使用 deb-linglong-packer agent 处理 packages.csv 配置文件中的包列表
```

## 输入方式

### 1. 指定 Deb 包目录

```
使用 deb-linglong-packer 处理 /path/to/deb/packages/
```

Agent 会自动扫描目录下所有 `.deb` 文件。

### 2. 使用 CSV 配置文件

```
使用 deb-linglong-packer 处理 packages.csv
```

CSV 格式：

```csv
package_name,deb_path,architecture,base,runtime,push
com.visualstudio.code,/path/to/code.deb,x86_64,org.deepin.base,org.deepin.runtime,true
com.example.app,/path/to/example.deb,arm64,org.deepin.base,org.deepin.runtime,false
```

| 字段 | 必填 | 说明 |
|------|------|------|
| package_name | 是 | 玲珑包名（ID） |
| deb_path | 是 | Deb 文件路径 |
| architecture | 是 | 目标架构（x86_64/arm64） |
| base | 否 | 基础环境 |
| runtime | 否 | 运行时环境 |
| push | 否 | 是否推送到仓库 |

## 工作流程

```
输入（目录/CSV）
    ↓
扫描 Deb 包列表
    ↓
┌─────────────────────────────┐
│  1. Deb 分析                │
│  2. 工程生成                │
│  3. 资源收集（需确认）      │
│  4. 兼容性测试              │
│  5. 问题修复（如需要）      │
│  6. 保存工程                │
└─────────────────────────────┘
    ↓
生成批量处理报告
```

## 交互示例

### 资源确认

```
📦 已收集资源: com.example.app

Desktop文件:
  ✓ com.example.app.desktop

图标文件:
  ✓ hicolor/48x48/apps/com.example.app.png
  ✓ hicolor/256x256/apps/com.example.app.png

请确认资源是否正确:
1. [确认继续] - 使用这些资源继续
2. [修改资源] - 打开资源目录供手动调整
3. [跳过此包] - 不处理此包
```

### 失败处理

```
❌ 处理失败: com.example.app
错误原因: [具体错误信息]

请选择:
1. [跳过继续] - 记录失败，处理下一个包
2. [重试] - 重新尝试当前包
3. [停止任务] - 终止批量处理
4. [查看日志] - 查看详细错误日志
5. [手动修复] - 暂停等待手动修复后继续
```

## 输出结构

```
CI_ll_<package_id>/
├── linglong.yaml           # 玲珑配置
├── pak_linyaps.sh          # 构建脚本
├── src/                    # 源码
└── templates/
    └── files_res/          # 资源文件
        ├── applications/   # Desktop 文件
        ├── icons/          # 图标
        └── ...
```

## 批量报告格式

处理完成后生成报告：

```markdown
# Deb 玲珑化批量处理报告

## 概览
- 处理时间: 2024-01-15 10:30:00
- 总计: 10 个包
- 成功: 8 个
- 失败: 2 个

## 成功列表
| 包名 | 工程目录 | 架构 | 状态 |
|------|---------|------|------|
| com.visualstudio.code | CI_ll_com.visualstudio.code | x86_64 | ✅ |

## 失败列表
| 包名 | 错误原因 |
|------|---------|
| com.failed.app | 构建失败 |
```

## 依赖工具

Agent 依赖以下脚本（需在工作目录中可用）：

- `deb_to_linglong.py` - Deb 解析
- `validate_linglong_yaml.py` - YAML 验证
- `common-data-verify.py` - 资源验证
- `demos/compat_checker.py` - 兼容性检测

## 注意事项

1. **命名规范**: 工程目录必须为 `CI_ll_<package_id>` 格式
2. **多架构**: CSV 中同一包可指定多行（不同架构）
3. **CSV 优先**: CSV 配置值优先于自动检测
4. **日志保存**: 所有日志保存到 `reports/` 目录
5. **权限要求**: Agent 需要文件读写和执行权限

## Agent 文件格式

```yaml
---
description: "批量将deb软件包转换为玲珑打包工程..."
name: Deb Linglong Packer
tools: [read, edit, search, execute, todo]
argument-hint: "deb包目录或CSV配置文件路径"
---

# Agent 描述和指令...
```

## 故障排查

### Agent 未显示

1. 检查文件路径是否正确（`.opencode/agents/`）
2. 确认 frontmatter 中的 `name` 和 `description` 存在
3. 检查权限配置是否阻止了 agent 访问

### Skills 未加载

1. 确认 SKILL.md 文件名全大写
2. 验证 frontmatter 包含 `name` 和 `description`
3. 检查 skills 目录结构是否正确

### 工具调用失败

1. 确认依赖脚本存在且可执行
2. 检查工作目录权限
3. 查看 OpenCode 日志获取详细信息
