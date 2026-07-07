---
name: tar-linyaps
description: >
  將 Linux binary release tar 歸檔包轉換為玲瓏（Linglong）應用便捷打包腳本。
user-invocable: false
---

# tar-linyaps Skill

## 功能說明

將 Linux binary release tar 歸檔包轉換為玲瓏（ Linglong）應用便捷打包腳本。

## 觸發詞

```
convert tar, tar binary, tar package, 轉換 tar, tar 打包
```

## 輸入方式

支持兩種參數傳遞方式（優先級：JSON 配置文件 > 交互式傳參）：

### 方式一：JSON 配置文件（推薦）

通過 JSON 文件一次性提供所有構建參數，由 `parse_build_config.sh` 腳本解析。

```bash
# 解析配置文件，輸出 key=value 格式
eval "$(bash "${skill_root}/scripts/parse_build_config.sh" config.json)"
```

JSON 結構分為 `main`（必填）和 `optional`（可選）兩個分組：

```json
{
  "main": {
    "src_url": "https://example.com/app-1.0.0.tar.zst",
    "app_name": "My Application",
    "package_id": "com.example.myapp",
    "description": "應用描述",
    "icon_url": "https://example.com/icon.png"
  },
  "optional": {
    "binary_name": "myapp",
    "app_version": "1.0.0",
    "base_id": "org.deepin.base",
    "base_version": "25.2.2",
    "runtime_id": "org.deepin.runtime.dtk",
    "runtime_version": "25.2.2",
    "linyaps_arch": "x86_64",
    "output_dir": "./output"
  }
}
```

範例文件：`examples/build_config.example.json`

### 方式二：交互式傳參

直接向 Agent 提供以下參數，Agent 交互式收集：

| 參數 | 說明 | 必填 | 範例 |
|------|------|------|------|
| `src_url` | tar 歸檔下載 URL 或本地路徑 | ✅ | `https://example.com/app.tar.zst` |
| `app_name` | 應用名稱 | ✅ | `My Application` |
| `package_id` | 玲瓏包 ID（反向域名格式） | ✅ | `com.example.myapp` |
| `description` | 應用描述 | ✅ | `A sample application` |
| `icon_url` | icon 下載 URL | ✅ | `https://example.com/icon.png` |
| `binary_name` | 可執行檔案名 | ❌ | `app.bin` |
| `app_version` | 版本號 | ❌ | `1.0.0` |
| `base_id` | base 層 ID | ❌ | `org.deepin.base` |
| `base_version` | base 層版本 | ❌ | `25.2.2` |
| `runtime_id` | runtime 層 ID | ❌ | `org.deepin.runtime.dtk` |
| `runtime_version` | runtime 層版本 | ❌ | `25.2.2` |
| `linyaps_arch` | 目標架構 | ❌ | `x86_64` |
| `output_dir` | 輸出目錄 | ❌ | `./output` |

## 批量初始化

使用 `batch_init.sh` 腳本可以批量創建多個 tar 應用的打包工程：

```bash
# CSV 格式批量初始化
./scripts/batch_init.sh tasks.csv --projects_root=./projects

# JSON 格式批量初始化
./scripts/batch_init.sh task.json --projects_root=./projects

# 僅生成項目結構，不執行打包
./scripts/batch_init.sh tasks.csv --dry-run
```

**CSV 格式示例**：
```csv
包名,架構,版本,下載地址
com.example.app,x86_64,1.0.0,https://example.com/app.tar.zst
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
      "src_url": "https://example.com/app.tar.zst"
    }
  ]
}
```

批量初始化會為每個任務創建 `CI_ll_<pkgName>` 目錄，包含：
- `linglong.yaml` - 玲瓏打包配置文件
- `pak_linyaps.sh` - 自動化打包腳本
- `scripts/` - 輔助腳本目錄
- `config/` - 配置文件目錄（含白名單配置）
- `templates/files_res/` - 資源文件目錄

## 工作流程

### Step 1: 驗證並解壓 tar 歸檔

```bash
# 驗證 tar 文件格式
file "${tar_path}"

# 在臨時目錄解壓
extract_dir=$(mktemp -d)
tar -xf "${tar_path}" -C "${extract_dir}"
```

### Step 2: 檢測源碼包

解壓後立即檢查是否存在以下文件，判斷是否為源碼包：

- `CMakeLists.txt`
- `Makefile`
- `configure.ac`
- `*.spec`（RPM spec）
- `meson.build`
- `setup.py`

**若為源碼包**：終止並提示用戶這是源碼包，不適用此工具。

**若為二進制包**：繼續 Step 3。

### Step 3: 收集用戶參數

#### 3a. JSON 配置文件解析（優先）

若用戶提供了 JSON 配置文件（`build_config.json`），調用解析腳本載入所有參數：

```bash
# 解析 JSON 配置，輸出 key=value 格式並載入為 shell 變量
eval "$(bash "${skill_root}/scripts/parse_build_config.sh" build_config.json)"

# 載入後可直接使用以下變量：
# 必填（來自 main）：src_url, app_name, package_id, description, icon_url
# 可選（來自 optional）：binary_name, app_version, base_id, base_version,
#                       runtime_id, runtime_version, linyaps_arch, output_dir
```

**解析腳本行為**：
- 驗證 JSON 格式和頂層結構（`main` + `optional`）
- 檢查 `main` 中所有必填欄位是否存在且非空
- 檢測未知欄位並輸出警告
- 驗證 URL 格式（`src_url`、`icon_url`）
- `optional` 中未填寫的欄位自動使用默認值
- 輸出扁平 `key=value` 格式，可直接 `eval` 載入

**解析成功後**：根據 `binary_name` 是否有值決定後續流程：
- `binary_name` 有值 → 直接進入 Step 6
- `binary_name` 為空 → 進入 Step 4 掃描 desktop

#### 3b. 交互式參數收集（備選）

若用戶未提供 JSON 配置文件，Agent 交互式收集參數：
- 確認 `src_url`、`app_name`、`package_id`、`description`、`icon_url` 等必填項
- 詢問可選參數（使用默認值）
- 收集完成後根據 `binary_name` 決定後續流程

### Step 4: 掃描 desktop 文件

```bash
desktop_files=$(find "${extract_dir}" -name "*.desktop" -type f 2>/dev/null)
```

- **有 desktop 文件且 `Exec=` 有值**：
  - 提取 `Exec=` 中的 binary name（**優先級高於自動掃描**）
  - 提取 `Icon=` 欄位中的 icon 路徑
  - 複製 desktop 到 `files_res/share/applications/`
  - 直接進入 Step 6（跳過 Step 5 自動掃描）
- **有 desktop 文件但 `Exec=` 無值**：
  - 提取 `Icon=` 欄位中的 icon 路徑
  - 複製 desktop 到 `files_res/share/applications/`
  - 進入 Step 5 自動掃描 binary name
- **無 desktop 文件**：
  - 進入 Step 5 自動掃描 binary name
  - 後續根據 `app_name`、`binary_name`、`app_version` 生成 desktop 文件
  - 驗證 `binary_name` 是否存在並可執行
  - 調用 `desktop-file-validate` 驗證合規性

### Step 5: 掃描可執行檔（當無 desktop Exec 時）

```bash
"${skill_root}/scripts/scan_executables.sh" "${extract_dir}"
```

- 掃描解压根目所有可執行非 `*.so` 文件
- 通過 `file` 命令檢測 ELF 二進制架構，與 `uname -m` 比較，架構不匹配的自動跳過
- 每個 binary timeout 15s 運行測試
- 能長期運行者判定為候選 binary name
- 輸出候選列表，讓用戶確認

### Step 6: Icon 處理（XDG 規範）

參考 `linglong-fix` 技能的 `fix_icon_directory_structure` 和 `fix_desktop_icon` 邏輯，
確保圖標目錄結構和 desktop `Icon=` 欄位符合 XDG 圖標主題規範。

#### 6a. 定位圖標文件

**優先級**：

1. **從 desktop `Icon=` 欄位提取**：解析 Icon 值，在 tar 解壓目錄中查找對應文件
2. **在 tar 包整個解壓目錄中查找**：`find "${extract_dir}" -type f \( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \)`
3. **用戶提供 `--icon-url`**：下載圖標文件

**失敗處理**：以上均未找到有效 icon → **任務終止並報錯**

#### 6b. 按 XDG 規範放置圖標

將找到的圖標文件放置到符合 XDG 圖標主題規範的目錄結構中：

```
files_res/share/icons/hicolor/
├── scalable/apps/        ← SVG 圖標
├── 128x128/apps/         ← PNG 圖標（默認尺寸）
├── 256x256/apps/
└── ...
```

**放置規則**（參考 `linglong-fix` 的 `fix_icon_directory_structure`）：

| 格式 | 目標目錄 | 說明 |
|------|---------|------|
| `.svg` | `hicolor/scalable/apps/` | 矢量圖標統一放入 scalable |
| `.png` | `hicolor/<size>/apps/` | 根據實際尺寸或文件名判斷 |
| `.xpm` | `hicolor/<size>/apps/` | 同 PNG 處理 |

**尺寸判斷**：
- 優先使用 `file` 命令讀取實際尺寸（如 `file icon.png` → `PNG image data, 256 x 256`）
- 其次用 `identify`（ImageMagick）讀取尺寸
- 無法判斷時默認放入 `128x128/apps/`

**XDG 標準尺寸**：`16x16`, `22x22`, `24x24`, `32x32`, `48x48`, `64x64`, `128x128`, `256x256`, `512x512`, `scalable`

#### 6c. 修正 desktop Icon= 欄位

參考 `linglong-fix` 的 `fix_desktop_icon`，將 desktop 文件的 `Icon=` 欄位統一改為 **XDG 規範名稱**：

- **去除路徑前綴**：無論是絕對路徑還是相對路徑
- **去除擴展名**：只保留圖標名稱（stem）

| 原始值 | 修正後 | 說明 |
|--------|--------|------|
| `Icon=/usr/share/icons/hicolor/256x256/apps/myapp.png` | `Icon=myapp` | 絕對路徑 → 名稱 |
| `Icon=./icons/myapp.svg` | `Icon=myapp` | 相對路徑 → 名稱 |
| `Icon=myapp` | `Icon=myapp` | 已符合規範，不變 |

**注意**：此步驟在 Step 4 複製 desktop 文件之後執行，確保 desktop 文件中的 Icon 欄位與實際圖標文件名一致。

### Step 7: 生成玲瓏工程

調用 `linglong-project-gen` 子技能創建工程：

```bash
# 工程目錄命名
project_dir="CI_ll_${package_id}"
mkdir -p "${project_dir}/templates/files_res"
mkdir -p "${project_dir}/scripts"
mkdir -p "${project_dir}/config"

# 拷貝模板
cp "${skill_root}/templates/pak_linyaps.sh" "${project_dir}/"
chmod +x "${project_dir}/pak_linyaps.sh"
cp "${skill_root}/templates/linglong.yaml" "${project_dir}/templates/"

# 預填充已知值到模板 YAML（Step 3 已收集的靜態信息，避免佔位符殘留）
sed -i "s|\${package_id}|${package_id}|g" "${project_dir}/templates/linglong.yaml"
sed -i "s|\${app_name}|${app_name}|g" "${project_dir}/templates/linglong.yaml"
sed -i "s|\${description}|${description}|g" "${project_dir}/templates/linglong.yaml"

# 拷貝掃描腳本
cp "${skill_root}/scripts/scan_executables.sh" "${project_dir}/scripts/"
chmod +x "${project_dir}/scripts/scan_executables.sh"

# 拷貝路徑處理腳本（與 deb 版共用，處理 /usr/、/opt/ 等路徑轉換 + 特殊字符標準化）
cp "${skill_root}/../linglong-project-gen/templates/scripts/handle_special_paths.sh" "${project_dir}/scripts/"
chmod +x "${project_dir}/scripts/handle_special_paths.sh"

# 拷貝白名單配置
cp "${skill_root}/../config/base_runtime_whitelist.conf" "${project_dir}/config/"

# 拷貝 desktop 文件
cp "${desktop_file}" "${project_dir}/templates/files_res/share/applications/"

# 拷貝 icon 文件
if [ -n "${icon_file}" ] && [ -f "${icon_file}" ]; then
  mkdir -p "${project_dir}/templates/files_res/share/icons/hicolor/"
  cp "${icon_file}" "${project_dir}/templates/files_res/share/icons/hicolor/"
fi
```

**注意**：
- `package_id` 從 `app_name` 推導（反向域名格式，如 `com.example.app`）
- `command` 欄位占位符由 `pak_linyaps.sh` 在構建時自動處理
- `base`/`runtime` 欄位為空佔位符 `""`，由 `build_pak()` 透過 `sed` 延遲注入
- **禁止**在資源收集階段手動修改 desktop 文件的 `Exec=` 欄位

---

## 職責邊界

| 階段 | 負責方 | 操作 |
|------|--------|------|
| Step 2: 源碼包檢測 | tar-linyaps skill | 解壓後立即檢測，源碼包則終止 |
| Step 4: Desktop 掃描 | tar-linyaps skill | 提取 Exec= binary name（優先級高於自動掃描） |
| Step 5: 自動掃描 | tar-linyaps skill | 僅在無 desktop Exec 時掃描可執行檔 |
| Step 4/5: 資源收集 | tar-linyaps skill | 只修復 Icon 路徑，**不修改** Exec 欄位 |
| Step 7: 工程生成 | tar-linyaps skill | 準備 templates/、scripts/、config/ 目錄結構 |
| 構建時 | pak_linyaps.sh | 創建 wrapper 腳本（binary/bin/*.wrapper） |
| 構建時 | pak_linyaps.sh | 更新 linglong.yaml 的 command（sed 替換為數組格式） |
| 構建時 | pak_linyaps.sh | 更新 linglong.yaml 的 base/runtime（sed 延遲注入） |
| 構建時 | pak_linyaps.sh | 更新 desktop 的 Exec（替換為 wrapper 絕對路徑） |
| 構建時 | pak_linyaps.sh | Desktop 文件去重（dedup_desktop_files.sh 兩步去重） |
| 構建時 | pak_linyaps.sh | 嵌套 bin/ 路徑驗證（validate_bin_nesting.sh） |
| 構建時 | pak_linyaps.sh | **ll-builder build** — 實際構建玲瓏包 |
| 構建時 | pak_linyaps.sh | **ll-builder export** — 導出 .layer 文件到 output_dir |
| 構建時 | pak_linyaps.sh | 可選 ll-builder push（auto_push=true 時） |

---

## pak_linyaps.sh 構建流程

`pak_linyaps.sh` 是**完整構建腳本**（非僅工程目錄生成器），與 deb 版構建流程完全一致。

### 完整流程

```
main()
  ├─ init_global_data()        # 解析命令行參數
  ├─ data_regroup_check()      # 驗證 src_path、版本處理、輸出目錄
  ├─ build_dir_init()          # 準備構建環境
  │   ├─ 複製 files_res/ 到 build_tmp_dir
  │   ├─ 複製 scripts/*.sh 到 build_tmp_dir/scripts/
  │   └─ envsubst 生成 linglong.yaml
  ├─ build_pak()               # 核心構建
  │   ├─ tar -xf 解壓
  │   ├─ handle_special_paths.sh 路徑轉換
  │   ├─ 自動偵測 binary_name（desktop → scan_executables.sh）
  │   ├─ 創建 wrapper 腳本（binary/bin/*.wrapper）
  │   ├─ 更新 linglong.yaml command + base/runtime + desktop Exec
  │   ├─ dedup_desktop_files.sh 兩步去重
  │   ├─ validate_bin_nesting.sh 嵌套 bin/ 驗證
  │   ├─ 創建 .linyaps_genius 標識文件
  │   ├─ ll-builder build --skip-output-check
  │   ├─ ll-builder export --no-develop --layer
  │   └─ 移動 *.layer 到 output_dir
  ├─ push_dev() [可選]         # ll-builder push 到倉庫
  └─ 清理 build_tmp_dir
```

### 構建輸出

- **成功**：`output_dir/` 下生成 `*.binary.layer` 文件
- **失敗**：`ll-builder build` 返回非零退出碼，腳本終止

### linglong.yaml build 段

模板中的 `build:` 段負責將文件複製到玲瓏容器內：
```yaml
build: |
  cp -rf /project/binary/* ${prefix}/
  cp -rf /project/files_res/* ${prefix}/
  touch ${prefix}/.linyaps_genius
```

---

## 約束條件

1. **不要過度分析結構**：只需定位 binary name，pak_linyaps.sh 會處理路徑解析
2. **Icon 嚴格驗證**：從 desktop Icon 欄位提取，支持 URL 導入，無有效 icon 時終止
3. **Wrapper 機制**：Exec 和 command 由 pak_linyaps.sh 在構建時自動處理
4. **Base/Runtime 動態注入**：`linglong.yaml` 模板中 `base: ""`, `runtime: ""` 為空佔位符，由 `build_pak()` 透過 `sed` 延遲注入，支援 `--base_id`/`--runtime_id` CLI 參數動態覆蓋
5. **🚫 禁止手動修改 Exec（嚴格）**：
   - 資源收集階段（Step 4/6/7）**絕對禁止**修改 desktop 文件的 `Exec=` 欄位
   - **絕對禁止**手動創建 bash wrapper 腳本或將 Exec 替換為 bash 路徑
   - **絕對禁止**在工程目錄中手動生成任何 `.sh` wrapper 文件
   - Exec 的修改**只能**由 `pak_linyaps.sh` 的 wrapper 機制在構建時自動完成
   - 如果發現 Exec 需要修改，**不要動手**，讓 pak_linyaps.sh 處理
6. **🚫 禁止手動修改 Exec（嚴格）**：
   - 資源收集階段（Step 4/6/7）**絕對禁止**修改 desktop 文件的 `Exec=` 欄位
   - **絕對禁止**手動創建 bash wrapper 腳本或將 Exec 替換為 bash 路徑
   - **絕對禁止**在工程目錄中手動生成任何 `.sh` wrapper 文件
   - Exec 的修改**只能**由 `pak_linyaps.sh` 的 wrapper 機制在構建時自動完成
   - 如果發現 Exec 需要修改，**不要動手**，讓 pak_linyaps.sh 處理
7. **🚫 禁止手動設置 base/runtime**：
   - `linglong.yaml` 模板中 `base: ""`, `runtime: ""` 為空佔位符
   - **絕對禁止**在生成階段將 base/runtime 寫入模板
   - **絕對禁止**在 `build_dir_init()` 中 `export base=/runtime=` 變量
   - base/runtime **只能**由 `build_pak()` 在構建時透過 `sed` 延遲注入
   - 用戶通過 `--base_id`/`--runtime_id` CLI 參數動態指定
8. **🚫 禁止干預 ll-builder 構建**：SKILL 層面（Step 1-7）只負責資源收集和工程準備，不得在 SKILL 執行過程中調用 `ll-builder` 或修改構建流程
9. **pak_linyaps.sh 是完整構建腳本**：用戶執行 `bash pak_linyaps.sh --src_path ... --package_id ...` 後，腳本自動完成從解壓到 .layer 導出的全部流程，無需手動干預
10. **構建環境隔離**：`build_tmp_dir` 作為構建沙箱，所有中間產物在其中生成，構建完成後可自動清理
11. **🚫 禁止手動填入 version（新增）**：
    - `linglong.yaml` 模板中 `version: "${ll_version}"` 和 `package.version: ${ll_version}` **必須保持為變量**
    - **絕對禁止**在生成工程時將 version 替換為 `"1.0"`、`"0.0.1"` 等絕對值
    - version **只能**由 `pak_linyaps.sh` 在構建時透過 `envsubst` 自動替換
    - 若 LLM 錯誤地將 version 寫死，`validate_linglong_yaml.py` 將在兼容性測試中報錯

---

## 依賴

### 構建腳本（scripts/）
- `parse_build_config.sh`：JSON 配置解析腳本（解析 `build_config.json`，驗證必填欄位，輸出 `key=value` 格式）
- `scan_executables.sh`：可執行檔掃描腳本（tar 版特有，用於無 desktop 時的自動偵測）
- `handle_special_paths.sh`：路徑轉換腳本（處理 `/usr/`、`/opt/` 等路徑層級剝離 + 特殊字符標準化 + 軟鏈修復），與 deb 版共用
- `dedup_desktop_files.sh`：Desktop 文件去重腳本（兩步去重：binary vs files_res + files_res 內部），與 deb 版共用
- `validate_bin_nesting.sh`：嵌套 bin/ 路徑驗證腳本，與 deb 版共用

### 外部工具
- `jq`：JSON 解析工具（`parse_build_config.sh` 依賴）
- `ll-builder`：玲瓏構建工具（build + export + push）
- `desktop-file-validate`：desktop 文件驗證工具
- `envsubst`：環境變量替換工具（生成 linglong.yaml）

### 配置文件
- `examples/build_config.example.json`：JSON 配置範例文件（`main`/`optional` 分組結構）
- `base_runtime_whitelist.conf`：base/runtime 白名單配置
- `templates/linglong.yaml`：玲瓏工程模板（含 build 段）
