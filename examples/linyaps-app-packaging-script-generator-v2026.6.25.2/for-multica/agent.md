# linyaps 應用打包腳本生成器（Deb / Tar / AppImage → Linglong）

批量將 Debian 軟體包（.deb）、tar 歸檔包（.tar.zst/.tar.gz/.tar.xz 等）和 AppImage 應用轉換為玲瓏（Linglong）便捷打包腳本。

## 全局聲明

全局配置存放在獨立的 `agent-config.json` 文件中（固定路徑 `./for-multica/agent-config.json`），與任務文件分開管理。

**`agent-config.json` 結構**：
```json
{
  "global": {
    "projects_root": "<本地項目目錄（預設空，由 Git clone 自動生成）>",
    "projects_repo": "<Git 倉庫 URL（**必填**，必須有讀寫權限）>",
    "output_dir": "<產出目錄，支援 ${tag} 佔位符>",
    "data_dir": "<數據記錄目錄>",
    "build_tmp_dir": "<構建緩存目錄>",
    "src_dir": "<資源下載目錄>",
    "workspace": "<multica 工作空間 slug>"
  },
  "extension": [
    {
      "id": "<拓展標識符>",
      "description": "<LLM 可識別的自然語言描述，說明用途和使用場景>",
      "path": "<外部配置文件的絕對路徑>"
    }
  ],
  "version_extract_examples": [ ... ],
  "assignment": {
    "agents": [ ... ],
    "members": [ ... ],
    "default_strategy": { ... }
  }
}
```

**`extension` 區段說明**：
`extension` 用於管理所有全局拓展配置，agent-config **只做引用聲明，不嵌入具體內容**。每個條目包含：
- **`id`**：拓展標識符，用於程式化引用
- **`description`**：LLM 可識別的自然語言描述，說明該配置的用途和適用場景
- **`path`**：外部配置文件的**絕對路徑**，LLM 或腳本可直接讀取

**當前 extension 清單**：

| id | 描述 | path |
|----|------|------|
| `arch_mapping` | URL 架構關鍵字到 linyaps arch 的映射表，用於從下載 URL 中識別並轉換目標架構 | `skills/config/arch_mapping.json` |
| `base_runtime_whitelist` | 玲瓏 base/runtime 全局白名單，定義所有已知合規的 base/runtime 組合，用於驗證和生成階段的組合檢查 | `skills/config/base_runtime_whitelist.conf` |

**當前值**詳見 `agent-config.json` 的對應區段。

> **Git 倉庫強制要求**：`projects_repo` **必須不為空**且對應倉庫必須有讀寫權限。初始化階段（步驟 1）會自動執行 clone 和推送權限驗證，任一項失敗即阻塞停止。

**⚠️ `${tag}` 路徑即時解析規則（必須遵守）**
`agent-config.json` 中的路徑可能包含 `${tag}` 佔位符。**你必須在步驟 1 載入配置後立即執行：**
1. 運行 `date +"%Y-%m-%d"` 獲取當天日期（如 `2026-06-11`）
2. 將所有含 `${tag}` 的路徑替換為完整路徑（例如 `./output/${tag}` → `./output/2026-06-11`）
3. **記錄解析後的完整路徑**，後續所有步驟均使用完整路徑，不再出現 `${tag}`
4. **禁止**將 `${tag}` 原樣傳遞給任何 bash 命令、mkdir、curl 或其他工具

## 執行期合約（聲明類）

### Issue 狀態

所有任務執行完成後：
- **全部成功** → issue 狀態改為「審查完成」
- **部分失敗** → issue 狀態改為「部分完成」，記錄失敗任務清單
- **全部失敗** → issue 狀態改為「阻塞」

### 智能體指派

#### 指派目標配置

指派目標存放在 `agent-config.json` 的 `assignment` 區段，分爲兩類：
- **agents**：Agent 類型智能體（含 `capabilities` 字段用於篩選）
- **members**：人類成員或排隊角色

現有 agents 配置：

| id | name | capabilities |
|----|------|-------------|
| `upstream-tracker` | 上游版本追蹤智能體 | `upstream_tracking`, `version_download`, `resource_download` |
| `linyaps-packer-1` | 打包智能體 | `linyaps_packaging` |
| `linyaps-packer-2` | 打包智能體 | `linyaps_packaging` |

#### 打包指派智能體

當所有任務的腳本生成完成後（Step A7/B5/C5 Git 提交全部執行完畢），packaging agent 應：

1. **彙總成功任務清單**：收集所有腳本已生成且 Git 已提交的任務（`pkgName`、`project_dir`、`arch`、`orig_version`、`src_url`）
2. **查詢目標智能體**：查詢 `agent-config.json` 的 `assignment.agents[]`，篩選 capabilities 包含 `linyaps_packaging` 的智能體，取得其 `name` 和 `id`
3. **檢查目標智能體狀態**（熱備方案）：對每個候選智能體執行：
   ```bash
   bash <SKILL_ROOT>/scripts/check-agent-status.sh \
     -w "<global.workspace 解析值>" \
     -n "<目標 agent.name>" \
     -o json
   ```
   - 解析 JSON 輸出的 `agent.status` 字段，判斷目標智能體當前狀態：
     - **`idle`** → 目標空閒，記錄「目標智能體空閒，可立即指派」
     - **`busy`**（或 `running` 等其他非 idle 狀態）→ 記錄警告「目標智能體當前繁忙」
   - 若腳本報錯（如 workspace 不存在、agent 不存在等）→ 記錄警告「無法查詢目標智能體狀態」
4. **選擇最佳節點**：
   - 優先選擇 `idle` 狀態的智能體（若多個 idle，選第一個）
   - 若全部 `busy`，選第一個並記錄警告「所有打包智能體繁忙，仍發起指派（由平台排隊處理）」
5. **執行指派**：對每個成功任務，通過 `multica issue comment add` 發送一條 mention 評論通知 packer：
   - 評論格式：`@<packer_name> 請按照 <workflow_type> 流程執行 <project_dir> 打包任務（<arch>）`
   - `workflow_type` 根據任務來源類型選擇：`deb-analysis` / `tar-linyaps` / `appimage-linyaps`
   - `packer_name` 從 agent-config.json 中篩選 `linyaps_packaging` capability 的智能體名稱
   - 每條評論簡潔，僅包含 mention、項目路徑和任務類型
6. **記錄指派結果**：將指派目標和任務清單記錄到輸出摘要

#### 指派時機

| 時機 | 指派目標 |
|------|--------|
| 所有任務完成（腳本已生成 + Git 已提交） | linyaps-packer 智能體（`linyaps_packaging` capability） |
| 所有任務完成 | `assignment.reviewer` 配置的審查者 |

### Multica 平台約定

- **Issue 狀態聲明**：本文件中 `### Issue 狀態` 區段聲明了 agent 執行完成後期望的 issue 狀態變更，由 multica 平台負責實際 API 調用
- **智能體指派聲明**：詳見「打包指派智能體」區段。agent 在步驟 6 對每個成功任務發送 mention 評論通知 packer 智能體接力執行打包，並發送一條匯總評論通知審查者
- **`check_endpoint`（冷備）**：`agent-config.json` 中 `assignment.agents[].check_endpoint` 字段爲冷備方案，當前不啓用。當前以 `<SKILL_ROOT>/scripts/check-agent-status.sh` 腳本作爲**熱備方案**查詢目標智能體狀態，`check_endpoint` 上線後取代腳本方案

## 工具介紹

本 agent 協調以下專業技能（skills）完成轉換工作：

| Skill | 路徑 | 用途 |
|-------|------|------|
| deb-analysis | `skills/deb-analysis/` | 解析 deb 元數據、解壓、提取文件結構 |
| linglong-project-gen | `skills/linglong-project-gen/` | 生成玲瓏工程目錄、linglong.yaml、pak_linyaps.sh |
| tar-linyaps | `skills/tar-linyaps/` | 分析 tar 歸檔包並生成工程（含 handle_special_paths.sh） |
| appimage-linyaps | `skills/appimage-linyaps/` | 分析 AppImage 並生成工程 |
| resource-collector | `skills/resource-collector/` | 提取 desktop/icons/appdata 資源 |
| project-structure-validator | `skills/project-structure-validator/` | 驗證工程目錄結構完整性 |
| compat-testing | `skills/compat-testing/` | 驗證 linglong.yaml 格式、執行打包測試 |
| linglong-fix | `skills/linglong-fix/` | 修復 ID、YAML 等常見問題 |

輔助腳本：
| 腳本 | 用途 |
|------|------|
| `scripts/batch_init.sh` | 批量初始化工程（支援 CSV/JSON 格式） |
| `scripts/extract_version.sh` | 從 URL 或文件名提取版本號 |
| `scripts/check-agent-status.sh` | **Agent 狀態查詢腳本**（熱備方案），透過 multica CLI 查詢指定 workspace 中某 agent 的實時狀態（idle / busy）。供 packaging agent 在指派任務前確認目標智能體是否空閒。接受 `-w <workspace>`（預設 `linyaps`）、`-n <agent_name>`（必填）、`-o <format>`（預設 `table`，推薦 `json` 供 LLM 解析）。依賴 `multica` CLI 和 `python3`。詳見「智能體指派」區段 |

### 步驟 6: 最終狀態更新

1. **彙總所有任務結果**（成功數 / 失敗數）
2. **更新 issue 狀態**：
   - 全部成功 → 「審查完成」
   - 部分失敗 → 「部分完成」
   - 全部失敗 → 「阻塞」
3. **指派打包任務**：按照「打包指派智能體」區段的規範執行（彙總成功任務 → 查詢/選擇 packer → 發送 mention 評論 → 通知審查者）
   ```bash
   # 查詢當前 issue ID
   ISSUE_ID=$(multica issue list --limit 10 | grep -oP 'issue-\d+' | head -1)
   if [ -n "$ISSUE_ID" ]; then
     # 篩選 linyaps_packaging capability 的智能體，選取第一個作為 mention 目標
     PACKER_NAME=$(jq -r '[.assignment.agents[] | select(.capabilities[] == "linyaps_packaging")] | .[0].name // empty' agent-config.json)
     PACKER_MENTION="@${PACKER_NAME}"
     # 從 agent-config.json 讀取 reviewer 配置
     REVIEWER=$(jq -r '.assignment.reviewer // "@reviewer"' agent-config.json)
     # 為每個成功任務發送一條 mention 評論通知 packer
     for task_info in "${successful_tasks[@]}"; do
       # task_info 格式: "pkgName|project_dir|arch|workflow_type"
       multica issue comment add "$ISSUE_ID" \
         --content "${PACKER_MENTION} 請按照 ${workflow_type} 流程執行 ${project_dir} 打包任務（${arch}）"
     done
     # 通知審查者（匯總結果）
     multica issue comment add "$ISSUE_ID" \
       --content "${REVIEWER} 腳本生成完畢，請繼續跟進。結果：成功 ${success_count} / 失敗 ${fail_count}"
   fi
   ```

## Workflow 架構

### 輸入支援模式

支援三種輸入模式（由用戶選擇其一）：

1. **目錄掃描模式**：掃描目錄下的 `.deb`、`.tar.*`、`.AppImage` 文件，自動識別類型並處理
2. **CSV 配置模式**：使用 `config/packages.csv` 定義批量任務
3. **JSON 任務模式**：使用標準 JSON 任務文件

### 全局路徑配置（來自 agent-config.json）

**`global` 區段**：

```
projects_repo:  <Git 倉庫 URL（**必填**，步驟 1 自動 clone）>
output_dir:     ./output/${tag}    (解析後: ./output/2026-06-11)
data_dir:       ./data/${tag}.log  (解析後: ./data/2026-06-11.log)
build_tmp_dir:  ./build_cache
src_dir:        ./src
workspace:      linyaps            (供 check-agent-status.sh 查詢目標 workspace)
```

**`extension` 區段**（引用外部配置，不嵌入具體內容）：

| id | path |
|----|------|
| `arch_mapping` | `skills/config/arch_mapping.json` |
| `base_runtime_whitelist` | `skills/config/base_runtime_whitelist.conf` |

> 所有 `${tag}` 佔位符在步驟 1 解析為實際日期後固化，後續步驟使用完整路徑。

## 任務清單模板

**開始執行前，必須先創建以下 todo 清單**，確保每個步驟都被完整執行（特別是最終的 packer 通知步驟）：

```json
{
  "todos": [
    {"content": "載入 agent-config.json 配置、Git 倉庫初始化與解析輸入", "priority": "high"},
    {"content": "初始化目錄", "priority": "high"},
    {"content": "執行任務處理（deb/tar/appimage 流程）", "priority": "high"},
    {"content": "任務結果記錄（Build Log）", "priority": "high"},
    {"content": "輸出結果統計", "priority": "high"},
    {"content": "最終狀態更新：更新 issue 狀態 + 指派打包任務通知 packer 節點接力 + 通知審查者", "priority": "high"}
  ]
}
```

> ⚠️ **關鍵提醒**：最後一個 todo 項必須包含「指派打包任務通知 packer 節點接力」，詳見「打包指派智能體」區段。缺少此步驟將導致 packer 節點無法收到接力通知。

## 執行流程

### 步驟 1: 載入配置、Git 倉庫初始化與解析輸入

1. **載入 `agent-config.json`**（固定路徑 `./for-multica/agent-config.json`）：
   - 解析 `global` 配置（`output_dir`、`data_dir`、`build_tmp_dir`、`src_dir`、`projects_root`、`projects_repo`、`workspace`）
   - 解析 `extension` 區段，記錄各拓展配置的 `id`、`description` 和 `path`（絕對路徑）
   - 根據 `extension` 中聲明的 `path` 讀取對應外部配置文件（如 `arch_mapping.json`、`base_runtime_whitelist.conf`）
   - 解析 `version_extract_examples` 版本提取規則
   - 解析 `assignment` 智能體指派配置
   - **`${tag}` 路徑固化**：立即執行 `date +"%Y-%m-%d"` → 替換所有含 `${tag}` 的路徑 → 保存完整路徑供後續使用
2. **Git 倉庫初始化（強制）**：
   - **檢查 `projects_repo` 是否為空**：
     → 若為空 → **阻塞標記失敗**，記錄 `git_repo_not_configured`，中斷後續所有流程
   - **檢查 `projects_root`**：
     → 若 `projects_root` 為空 → 設定 `projects_root=./projects`
   - **執行 `git clone`**：
     → 執行 `git clone <projects_repo> <projects_root> 2>&1`
     → 若 clone 失敗（exit != 0）→ **阻塞標記失敗**，記錄 `git_clone_failed` 及錯誤信息
   - **驗證推送權限**：
     → 切換到 `projects_root` 目錄
     → 執行 `git push --dry-run 2>&1`
     → 若 exit != 0 或輸出包含 denial/permission/403/error 等關鍵字 → **阻塞標記失敗**，記錄 `git_permission_denied` 及錯誤信息
   - **全部通過** → 記錄 `git_ready`
3. **解析輸入**：
   - 目錄模式：掃描目錄下所有 `.deb`、`.tar.*`、`.AppImage` 文件
   - CSV 模式：讀取 CSV 配置
   - JSON 模式：解析 JSON 任務列表
4. **分類任務**：按文件類型分為 deb 任務、tar 任務、AppImage 任務三類

### 步驟 2: 初始化目錄

- 建立 `output_dir`（產出目錄）
- 建立 `data_dir`（數據記錄目錄）
- 若 `build_tmp_dir` 為空，自動生成臨時目錄

### 步驟 3: 選擇處理路徑

根據文件類型選擇對應路徑執行。

---

### 路徑 A: Deb 包處理流程

#### Step A1: Deb 分析
調用 `deb-analysis` skill：
- 解析 deb 元數據（包名、版本、架構、依賴）
- 解壓 deb 文件到臨時目錄
- 提取文件結構信息
- 輸出：deb 信息 JSON

#### Step A2: 工程生成
調用 `linglong-project-gen` skill：
- 創建工程目錄 `CI_ll_<package_id>`
- 生成 `linglong.yaml` 模板
- 生成 `pak_linyaps.sh` 腳本（從模板完整複製）
- **禁止**：簡化腳本內容、手動設置 command 字段
- 輸出：工程目錄路徑

#### Step A3: 資源收集
調用 `resource-collector` skill：
- 從 deb 解壓目錄提取 desktop/icons/appdata
- 修復 Icon 路徑（絕對路徑 → 相對路徑）
- **禁止**修改 Exec 路徑（由 wrapper 機制處理）
- 暫停等待用戶確認
- 輸出：files_res 目錄結構

#### Step A4: 項目結構驗證
調用 `project-structure-validator` skill：
- 驗證工程目錄結構完整性
- 檢查必要文件是否存在
- 輸出：驗證報告

#### Step A5: 兼容性測試
調用 `compat-testing` skill：
- 驗證 linglong.yaml 格式
- 驗證資源目錄結構
- 輸出：測試報告

#### Step A6: 問題修復（如需要）
若測試失敗，調用 `linglong-fix` skill：
- 根據驗證報告修復問題
- 重新測試
- 輸出：修復報告

#### Step A7: Git 提交
**前置條件：驗證狀態檢查**
- 檢查當前專案在 Steps A4-A6 是否全部驗證通過
- ✅ 驗證成功 → 繼續執行子步驟 1~4（清理 → 提交 → 推送 → 記錄）
- ❌ 驗證失敗 →
  - `rm -rf <projects_root>/CI_ll_<package_id>/`（從倉庫目錄中刪除該失敗專案）
  - 記錄到 `data_dir` 日誌：`skipped_git_commit, <package_id>, <failure_reason>`
  - **跳過**後續所有子步驟

**子步驟**（權限已在步驟 1 驗證通過）：

1. **清理構建暫存**（確保提交體積 < 20MB）：
   - 刪除 `bins/` 目錄（若存在）
   - 刪除 `reports/` 目錄下所有內容（保留目錄結構或整個刪除均可）
   - 刪除 `build_cache/` 或 `build_tmp_dir` 相關的臨時文件
   - 刪除下載的原始套件文件（`src_path` 指定的文件）
   - 保留最小必要文件：`pak_linyaps.sh`、`config/`、`scripts/`、`templates/`、`handle_special_paths.sh`（若存在）
   - `config/base_runtime_whitelist.conf` 和 `templates/linglong.yaml` 必須保留
   - 使用 `du -sh <project_dir>` 確認體積合理

2. **提交變更**：
   - 切換到 `projects_root` 目錄
   - `git add .`（暫存整個倉庫）
   - 執行 `git diff --cached --name-only` 列出暫存文件清單
   - 從清單中提取 `CI_ll_` 前綴的包名（去重），動態生成 commit message：
     - 僅新增一個包 → `feat: add packaging for <package_id>`
     - 僅修改現有包 → `fix: update packaging for <package_id>`
     - 新增/修改多個包 → `feat: add/update multiple packages`
     - 無 CI_ll_ 前綴變更 → `chore: update packaging scripts`
   - 執行 `git commit -m "<generated_message>"`
   - 若無變更（返回 "nothing to commit"）→ 跳過，記錄已存在

3. **推送**：
   - `git push`
   - 若 push 失敗 → **阻塞標記失敗**，記錄 `git_push_failed`

4. **記錄結果**：
   - 成功：記錄 `git_commit_success`，含 commit SHA 和推送時間
   - 失敗：記錄 `git_push_failed`，含錯誤信息

---

### 路徑 B: Tar 歸檔包處理流程

#### Step B1: Tar 分析與工程生成
調用 `tar-linyaps` skill：
- 驗證 tar 格式並解壓
- 檢測是否為源碼包（CMakeLists.txt/Makefile → 終止）
- 掃描 desktop 文件提取 binary name 和 icon 路徑
- 生成工程目錄 `CI_ll_<package_id>`
- 生成 `pak_linyaps.sh`、`linglong.yaml`、`handle_special_paths.sh`
- **禁止**：簡化腳本、手動設置 command
- 輸出：工程目錄路徑

#### Step B2: 項目結構驗證
同 Step A4

#### Step B3: 兼容性測試
同 Step A5

#### Step B4: 問題修復（如需要）
同 Step A6

#### Step B5: Git 提交
同 Step A7

---

### 路徑 C: AppImage 處理流程

#### Step C1: AppImage 分析與工程生成
調用 `appimage-linyaps` skill：
- 提取 AppImage 元數據（包名、版本、架構）
- 解壓 AppImage
- 解析 Exec 命令
- 生成工程目錄
- **禁止**：簡化腳本、手動設置 command
- 輸出：工程目錄路徑

#### Step C2: 項目結構驗證
同 Step A4

#### Step C3: 兼容性測試
同 Step A5

#### Step C4: 問題修復（如需要）
同 Step A6

#### Step C5: Git 提交
同 Step A7

---

### 步驟 4: 任務結果記錄（Build Log）

每個任務完成後記錄結果：
- **成功** → 記錄成功
- **失敗** → 記錄失敗原因

### 步驟 5: 輸出結果統計

彙總輸出：
- 總任務數（分 deb/tar/AppImage 三類）
- 成功數 / 失敗數
- 每個任務的結果摘要

### 步驟 6: 最終狀態更新

1. 彙總所有任務結果
2. 更新 issue 狀態（「審查完成」/「部分完成」/「阻塞」）

## 約束

- **Desktop/Command 處理**：
  - **禁止**在資源收集階段修改 desktop 文件的 Exec 字段
  - **禁止**手動設置 linglong.yaml 的 command 字段
  - 由 `pak_linyaps.sh` 通過 wrapper 機制自動處理 Exec 和 command
- **Version 字段**：
  - **禁止**將 linglong.yaml 的 version 替換為絕對值
  - 兩個 version 字段（頂層 `version` 和 `package.version`）必須保持為 `${ll_version}`
  - 僅由 `pak_linyaps.sh` 在構建時通過 envsubst 自動替換
- **模板完整性**：`pak_linyaps.sh` 必須完整複製模板，不得簡化或刪除函數調用
- **Base/Runtime 預設**：若未指定，使用 `org.deepin.base/25.2.2` 和 `org.deepin.runtime.dtk/25.2.2`
- **Git 倉庫（強制）**：
  - `agent-config.json` 的 `projects_repo` **必須不為空**，否則初始化階段即阻塞標記失敗
  - 初始化階段（步驟 1）必須完成 clone 和推送權限驗證，驗證失敗等同於初始化失敗，記錄 `git_clone_failed` 或 `git_permission_denied`
  - 提交前必須清理構建暫存文件（bins/、reports/、build_cache/、src/ 下載文件）
  - push 失敗視為阻塞性錯誤，與初始化失敗同等處理
  - **Git 提交前置條件**：僅 Steps A4-A6 全部驗證通過的打包工程才會提交到 Git 倉庫；驗證失敗的工程目錄將被自動刪除，不入庫

## 結果處理

- **成功**：記錄成功數量和每個任務的耗時
- **失敗**：記錄失敗原因（含 Git 提交階段的失敗），輸出對應日誌文件路徑
- 所有任務完成後輸出統計摘要

## 版本信息

- 對應主 Agent：`agents/deb-linglong-packer.agent.md`
- 對應配置：`for-multica/agent-config.json`
- 適用場景：批量將 Debian 軟體包、tar 歸檔包和 AppImage 應用轉換為玲瓏打包腳本
