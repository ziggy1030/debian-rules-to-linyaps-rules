---
name: linyaps-git-workflow
description: >
  【debian-rules-to-linyaps / Multica 平台】Git 工作流 SKILL。
  负责 Git 仓库初始化（clone + 推送验证）和提交推送（commit + push）。
  由 debian-rules-to-linyaps agent 在打包流程中调用。
argument-hint: '<action> <params>'
user-invocable: false
---

# linyaps-git-workflow — Git 工作流 SKILL

由 `debian-rules-to-linyaps` agent 在处理流程中调用，负责 Git 仓库的初始化和提交推送操作。

## 目录约定

- 入口脚本：`scripts/git-workflow.sh`（统一入口）
- 配置来源：`for-multica/agent-config.json` 的 `global` 区段
- 本 skill 脚本：`skills/linyaps-git-workflow/scripts/`

## 两种 Action 接口

### Action 1: `init_repo`

Git 仓库克隆 + 推送权限验证。

**调用时机**：步骤 1（配置载入后立即执行）

**输入**：
```json
{
  "action": "init_repo",
  "projects_repo": "https://git.example.com/projects.git",
  "projects_root": "./projects"
}
```

**输出**：
```json
{
  "status": "ready",
  "error": ""
}
```
- `status`：`"ready"`（成功）、`"blocked"`（失败）

**执行逻辑**：
1. 检查 `projects_repo` 是否为空 → 空则返回 `status: "blocked"`，记录 `git_repo_not_configured`
2. 若 `projects_root` 为空 → 设定 `projects_root=./projects`
3. 执行 `git clone <projects_repo> <projects_root> 2>&1` → 失败则返回 `status: "blocked"`，记录 `git_clone_failed`
4. 切换到 `projects_root`，执行 `git push --dry-run 2>&1` → 失败则返回 `status: "blocked"`，记录 `git_permission_denied`
5. 全部通过 → 返回 `status: "ready"`，记录 `git_ready`

### Action 2: `commit_and_push`

清理工程目录、Git 暂存、动态生成 commit message、推送。

**调用时机**：Step A6/B4（工程校验通过后）

**输入**：
```json
{
  "action": "commit_and_push",
  "projects_root": "./projects",
  "data_dir": "./data/2026-07-09.log"
}
```

**输出**：
```json
{
  "committed": true,
  "commit_sha": "abc123...",
  "packages": ["kate", "kwrite"]
}
```
- `committed`：`true`（成功）、`false`（失败或无变更）

**执行逻辑**：
1. **切换目录**：切换到 `projects_root`
2. **清理暂存**：只保留工程最小必要文件（`linglong.yaml`、`config/`）
3. **`git add .`** + `git diff --cached --name-only` 列出暂存文件
4. **动态生成 commit message**：
   - 仅新增包 → `feat: add debian-rules analysis for <package_id>`
   - 仅修改包 → `fix: update debian-rules analysis for <package_id>`
   - 多个包 → `feat: add/update multiple packages`
   - 无 CI_ll_ 变更 → `chore: update analysis scripts`
5. **`git commit`**：若无变更，记录已存在，不中断
6. **`git push`**：失败则记录 `git_push_failed`
7. **记录结果**到 `data_dir`：`git_commit_success, <commit_sha>` 或 `git_push_failed, <error>`

## 约束

1. **仅 debian-rules-to-linyaps agent 调用**
2. **与 agent-config.json 的 global.projects_repo 绑定**
3. push 失败视为阻塞性错误，与初始化失败同等处理