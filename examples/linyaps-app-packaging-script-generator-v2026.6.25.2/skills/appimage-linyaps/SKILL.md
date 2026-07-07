---
name: appimage-linyaps
description: >
  將 Linux AppImage 應用包轉換為玲瓏（Linglong）應用便捷打包腳本。
user-invocable: false
---

# appimage-linyaps Skill

## 功能說明

將 Linux AppImage 應用包轉換為玲瓏（Linglong）應用便捷打包腳本。

## 觸發詞

```
convert appimage, appimage package, 轉換 appimage, appimage 打包
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
    "src_url": "/path/to/application.AppImage",
    "app_name": "My Application",
    "package_id": "com.example.myapp",
    "description": "應用描述",
    "icon_url": "https://example.com/icon.png"
  },
  "optional": {
    "binary_name": "",
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
| `src_path` | AppImage 文件路徑或下載 URL | ✅ | `/path/to/app.AppImage` |
| `app_name` | 應用名稱 | ✅ | `My Application` |
| `package_id` | 玲瓏包 ID（反向域名格式） | ✅ | `com.example.myapp` |
| `description` | 應用描述 | ✅ | `A sample application` |
| `icon_path` | icon 下載 URL 或本地路徑 | ✅ | `https://example.com/icon.png` |
| `binary_name` | 顯式指定 Exec 命令 | ❌ | `AppRun` |
| `app_version` | 版本號 | ❌ | `1.0.0` |
| `base_id` | base 層 ID | ❌ | `org.deepin.base` |
| `base_version` | base 層版本 | ❌ | `25.2.2` |
| `runtime_id` | runtime 層 ID | ❌ | `org.deepin.runtime.dtk` |
| `runtime_version` | runtime 層版本 | ❌ | `25.2.2` |
| `linyaps_arch` | 目標架構 | ❌ | `x86_64` |
| `output_dir` | 輸出目錄 | ❌ | `./output` |

## 工作流程

### Step 1: 驗證並解壓 AppImage

```bash
# 驗證 AppImage 文件格式
file "${src_path}"

# 使用 extract_appimage.sh 解壓
"${skill_root}/scripts/extract_appimage.sh" "${src_path}" "${extract_dir}"

# 解壓後生成 squashfs-root/ 目錄
ls -la "${extract_dir}/squashfs-root"
```

### Step 2: 提取元數據

調用 `parse_appimage_metadata.sh` 從 AppImage 和 desktop 文件中提取元數據：

```bash
# 提取元數據，輸出 key=value 格式
eval "$("${skill_root}/scripts/parse_appimage_metadata.sh" "${src_path}" "${extract_dir}/squashfs-root")"

# 載入後可直接使用以下變量：
# app_name, package_id, description, binary_name, icon_name, version
```

**提取邏輯**：
- `app_name`：從 desktop `Name=` 提取，若為空則從文件名推導
- `package_id`：從 desktop 文件名推導（反向域名格式），若無法推導則從 `app_name` 生成
- `description`：從 desktop `Comment=` 提取，若為空則使用默認描述
- `binary_name`：從 desktop `Exec=` 提取，移除引號和參數佔位符
- `icon_name`：從 desktop `Icon=` 提取，移除路徑前綴和擴展名
- `version`：從文件名正則提取，確保 `X.Y.Z.W` 格式

### Step 3: 收集用戶參數

#### 3a. JSON 配置文件解析（優先）

若用戶提供了 JSON 配置文件（`build_config.json`），調用解析腳本載入所有參數：

```bash
# 解析 JSON 配置，輸出 key=value 格式並載入為 shell 變量
eval "$(bash "${skill_root}/scripts/parse_build_config.sh" build_config.json)"

# 載入後可直接使用以下變量：
# 必填（來自 main，已映射為 CLI 名稱）：src_path, app_name, package_id, description, icon_path
# 可選（來自 optional）：binary_name, app_version, base_id, base_version,
#                       runtime_id, runtime_version, linyaps_arch, output_dir
```

**解析腳本行為**：
- 驗證 JSON 格式和頂層結構（`main` + `optional`）
- 檢查 `main` 中所有必填欄位是否存在且非空
- 檢測未知欄位並輸出警告
- 驗證 `src_url` 必填（映射為 `src_path`）
- `optional` 中未填寫的欄位自動使用默認值
- 輸出扁平 `key=value` 格式，可直接 `eval` 載入

**解析成功後**：根據 `binary_name` 是否有值決定後續流程：
- `binary_name` 有值 → 直接進入 Step 5
- `binary_name` 為空 → 進入 Step 4 解析 Exec 命令

#### 3b. 交互式參數收集（備選）

若用戶未提供 JSON 配置文件，Agent 交互式收集參數：
- 確認 `src_path`、`app_name`、`package_id`、`description`、`icon_path` 等必填項
- 詢問可選參數（使用默認值）
- 收集完成後根據 `binary_name` 決定後續流程

### Step 4: 解析 Exec 命令（AppRun 優先策略）

**注意**：此步驟主要用於元數據提取。實際執行入口由 `pak_linyaps.sh` 在構建時根據 AppRun 優先策略決定。

**AppRun 優先策略**（借鑒 ll-pica 方案）：

| 優先級 | 檢測條件 | wrapper 目標 | 說明 |
|--------|---------|-------------|------|
| 1 | `AppRun` 存在 | `lib/${APP_PREFIX}/AppRun` | AppImage 標準入口，最可靠 |
| 2 | `AppRun.wrapped` 存在 | `lib/${APP_PREFIX}/AppRun.wrapped` | 部分 AppImage 使用 wrapped 入口 |
| 3 | Fallback | `lib/${APP_PREFIX}/${resolved_exec}` | 從 desktop Exec 解析 |

調用 `resolve_exec_command.sh` 從 desktop 文件中提取 Exec 命令（作為 fallback）：

```bash
# 從 squashfs-root 中的 desktop 文件提取 Exec 命令
binary_name=$("${skill_root}/scripts/resolve_exec_command.sh" "${extract_dir}/squashfs-root")
```

**支持的 Exec 模式**：
- AppRun 直接調用：`Exec=AppRun %U`
- AppRun.wrapped：`Exec=AppRun.wrapped`
- 直接二進制：`Exec=myapp --gui`
- 帶 `${HERE}` 變量：`Exec=${HERE}/usr/bin/myapp`
- 帶引號：`Exec="/path/to/AppRun" %U`

**解析邏輯**：
1. 查找 squashfs-root 中的 `.desktop` 文件
2. 提取 `Exec=` 字段
3. 移除引號和參數佔位符（`%U`, `%f`, `%u` 等）
4. 處理 `${HERE}` 變量（替換為相對路徑 `.`）
5. 提取第一個參數（binary name 或路徑）
6. 如果是路徑，提取文件名

**失敗處理**：若無法提取 Exec 命令，使用默認值 `AppRun`（與 AppRun 優先策略一致）

### Step 5: Icon 處理（XDG 規範）

參考 `linglong-fix` 技能的 `fix_icon_directory_structure` 和 `fix_desktop_icon` 邏輯，
確保圖標目錄結構和 desktop `Icon=` 欄位符合 XDG 圖標主題規範。

#### 5a. 定位圖標文件

**優先級**：

1. **從 desktop `Icon=` 欄位提取**：解析 Icon 值，在 squashfs-root 中查找對應文件
2. **在 squashfs-root 整個目錄中查找**：`find "${extract_dir}/squashfs-root" -type f \( -name "*.png" -o -name "*.svg" -o -name "*.xpm" \)`
3. **用戶提供 `--icon-url`**：下載圖標文件

**失敗處理**：以上均未找到有效 icon → **任務終止並報錯**

#### 5b. 按 XDG 規範放置圖標

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

#### 5c. 修正 desktop Icon= 欄位

參考 `linglong-fix` 的 `fix_desktop_icon`，將 desktop 文件的 `Icon=` 欄位統一改為 **XDG 規範名稱**：

- **去除路徑前綴**：無論是絕對路徑還是相對路徑
- **去除擴展名**：只保留圖標名稱（stem）

| 原始值 | 修正後 | 說明 |
|--------|--------|------|
| `Icon=/usr/share/icons/hicolor/256x256/apps/myapp.png` | `Icon=myapp` | 絕對路徑 → 名稱 |
| `Icon=./icons/myapp.svg` | `Icon=myapp` | 相對路徑 → 名稱 |
| `Icon=myapp` | `Icon=myapp` | 已符合規範，不變 |

**注意**：此步驟在 Step 2 提取元數據之後執行，確保 desktop 文件中的 Icon 欄位與實際圖標文件名一致。

### Step 6: 收集 desktop 文件和圖標

```bash
# 查找 desktop 文件
desktop_file=$(find "${extract_dir}/squashfs-root" -maxdepth 1 -name "*.desktop" -type f 2>/dev/null | head -1)

# 複製 desktop 文件到 files_res
if [ -n "${desktop_file}" ]; then
  cp "${desktop_file}" "${project_dir}/templates/files_res/share/applications/"
fi

# 複製 icon 文件
if [ -n "${icon_file}" ] && [ -f "${icon_file}" ]; then
  mkdir -p "${project_dir}/templates/files_res/share/icons/hicolor/"
  cp "${icon_file}" "${project_dir}/templates/files_res/share/icons/hicolor/"
fi
```

**注意**：
- **禁止**修改 desktop 文件的 `Exec=` 欄位（由 `pak_linyaps.sh` 在構建時自動處理）
- 只修復 `Icon=` 欄位（XDG 規範）

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

# 預填充已知值到模板 YAML（Step 2/3 已收集的靜態信息，避免佔位符殘留）
sed -i "s|\${package_id}|${package_id}|g" "${project_dir}/templates/linglong.yaml"
sed -i "s|\${app_name}|${app_name}|g" "${project_dir}/templates/linglong.yaml"
sed -i "s|\${description}|${description}|g" "${project_dir}/templates/linglong.yaml"

# 拷貝腳本
cp "${skill_root}/scripts/extract_appimage.sh" "${project_dir}/scripts/"
cp "${skill_root}/scripts/resolve_exec_command.sh" "${project_dir}/scripts/"
cp "${skill_root}/scripts/parse_appimage_metadata.sh" "${project_dir}/scripts/"
cp "${skill_root}/scripts/parse_build_config.sh" "${project_dir}/scripts/"
cp "${skill_root}/scripts/dedup_desktop_files.sh" "${project_dir}/scripts/"
cp "${skill_root}/scripts/validate_bin_nesting.sh" "${project_dir}/scripts/"
chmod +x "${project_dir}/scripts/"*.sh

# 拷貝白名單配置
cp "${skill_root}/config/base_runtime_whitelist.conf" "${project_dir}/config/"

# 拷貝 desktop 文件
if [ -n "${desktop_file}" ]; then
  cp "${desktop_file}" "${project_dir}/templates/files_res/share/applications/"
fi

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
| Step 1: AppImage 解壓 | appimage-linyaps skill | 使用 extract_appimage.sh 解壓 |
| Step 2: 元數據提取 | appimage-linyaps skill | 調用 parse_appimage_metadata.sh |
| Step 3: 參數收集 | appimage-linyaps skill | JSON 配置文件或交互式收集 |
| Step 4: Exec 解析 | appimage-linyaps skill | 調用 resolve_exec_command.sh |
| Step 5: Icon 處理 | appimage-linyaps skill | 只修復 Icon 路徑，**不修改** Exec 欄位 |
| Step 6: 資源收集 | appimage-linyaps skill | 複製 desktop 和 icon 到 files_res |
| Step 7: 工程生成 | appimage-linyaps skill | 準備 templates/、scripts/、config/ 目錄結構 |
| 構建時 | pak_linyaps.sh | 解壓 AppImage（extract_appimage.sh） |
| 構建時 | pak_linyaps.sh | 保持 squashfs-root 原始結構（lib/${APP_PREFIX}/） |
| 構建時 | pak_linyaps.sh | 創建 wrapper 腳本（AppRun 優先策略，bin/${APP_PREFIX}.wrapper） |
| 構建時 | pak_linyaps.sh | 更新 linglong.yaml 的 command（sed 替換為數組格式） |
| 構建時 | pak_linyaps.sh | 更新 linglong.yaml 的 base/runtime（sed 延遲注入） |
| 構建時 | pak_linyaps.sh | 更新 desktop 的 Exec（替換為 wrapper） |
| 構建時 | pak_linyaps.sh | Desktop 文件去重（dedup_desktop_files.sh 兩步去重） |
| 構建時 | pak_linyaps.sh | 嵌套 bin/ 路徑驗證（validate_bin_nesting.sh） |
| 構建時 | pak_linyaps.sh | **ll-builder build** — 實際構建玲瓏包 |
| 構建時 | pak_linyaps.sh | **ll-builder export** — 導出 .layer 文件到 output_dir |
| 構建時 | pak_linyaps.sh | 可選 ll-builder push（auto_push=true 時） |

---

## pak_linyaps.sh 構建流程

`pak_linyaps.sh` 是**完整構建腳本**（非僅工程目錄生成器），與 tar 版構建流程類似，但針對 AppImage 進行了優化。

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
  │   ├─ extract_appimage.sh 解壓 AppImage
  │   ├─ 保持 squashfs-root 原始結構（lib/${APP_PREFIX}/）
  │   ├─ AppRun 優先策略（借鑒 ll-pica）
  │   │   ├─ 檢測 AppRun 是否存在 → wrapper_target="AppRun"
  │   │   ├─ 檢測 AppRun.wrapped → wrapper_target="AppRun.wrapped"
  │   │   └─ Fallback: resolve_exec_command.sh 解析 desktop Exec
  │   ├─ 創建 wrapper 腳本（bin/${APP_PREFIX}.wrapper）
  │   │   └─ exec "${script_dir}/../lib/${APP_PREFIX}/${wrapper_target}" "$@"
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

### Wrapper 機制（AppRun 優先策略）

AppImage 版本使用特殊的 wrapper 機制，借鑒 ll-pica 的 AppRun 方案：

**執行入口優先級**：

| 優先級 | 檢測條件 | wrapper 目標 | 說明 |
|--------|---------|-------------|------|
| 1 | `AppRun` 存在 | `lib/${APP_PREFIX}/AppRun` | AppImage 標準入口，最可靠 |
| 2 | `AppRun.wrapped` 存在 | `lib/${APP_PREFIX}/AppRun.wrapped` | 部分 AppImage 使用 wrapped 入口 |
| 3 | Fallback | `lib/${APP_PREFIX}/${resolved_exec}` | 從 desktop Exec 解析 |

**設計原則**：
- 保持 AppImage 原始目錄結構（squashfs-root）
- 始終使用相對路徑 `exec`，不使用 `cd`（wrapper 設計原則）
- AppRun 優先：借鑒 ll-pica 方案，直接使用 AppImage 自帶的 AppRun
- Fallback 機制：當 AppRun 缺失時，從 desktop 文件解析 Exec 命令
- `resolve_exec_command.sh` 作為元數據提取工具，同時也是 AppRun 缺失時的 fallback

---

## 約束條件

1. **不要過度分析結構**：只需定位 Exec 命令，pak_linyaps.sh 會處理路徑解析
2. **Icon 嚴格驗證**：從 desktop Icon 欄位提取，支持 URL 導入，無有效 icon 時終止
3. **Wrapper 機制**：Exec 和 command 由 pak_linyaps.sh 在構建時自動處理
4. **Base/Runtime 動態注入**：`linglong.yaml` 模板中 `base: ""`, `runtime: ""` 為空佔位符，由 `build_pak()` 透過 `sed` 延遲注入，支援 `--base_id`/`--runtime_id` CLI 參數動態覆蓋
5. **🚫 禁止手動修改 Exec（嚴格）**：
   - 資源收集階段（Step 4/5/6/7）**絕對禁止**修改 desktop 文件的 `Exec=` 欄位
   - **絕對禁止**手動創建 bash wrapper 腳本或將 Exec 替換為 bash 路徑
   - **絕對禁止**在工程目錄中手動生成任何 `.sh` wrapper 文件
   - Exec 的修改**只能**由 `pak_linyaps.sh` 的 wrapper 機制在構建時自動完成
   - 如果發現 Exec 需要修改，**不要動手**，讓 pak_linyaps.sh 處理
6. **🚫 禁止手動設置 base/runtime**：
   - `linglong.yaml` 模板中 `base: ""`, `runtime: ""` 為空佔位符
   - **絕對禁止**在生成階段將 base/runtime 寫入模板
   - **絕對禁止**在 `build_dir_init()` 中 `export base=/runtime=` 變量
   - base/runtime **只能**由 `build_pak()` 在構建時透過 `sed` 延遲注入
   - 用戶通過 `--base_id`/`--runtime_id` CLI 參數動態指定
7. **🚫 禁止干預 ll-builder 構建**：SKILL 層面（Step 1-7）只負責資源收集和工程準備，不得在 SKILL 執行過程中調用 `ll-builder` 或修改構建流程
8. **pak_linyaps.sh 是完整構建腳本**：用戶執行 `bash pak_linyaps.sh --src_path ... --package_id ...` 後，腳本自動完成從解壓到 .layer 導出的全部流程，無需手動干預
9. **構建環境隔離**：`build_tmp_dir` 作為構建沙箱，所有中間產物在其中生成，構建完成後可自動清理
10. **AppImage 特殊處理**：
    - 使用 `extract_appimage.sh` 解壓（而非 tar -xf）
    - 保持 squashfs-root 原始目錄結構
    - 使用 `resolve_exec_command.sh` 解析 Exec 命令
    - 使用 `parse_appimage_metadata.sh` 提取元數據
11. **🚫 禁止手動填入 version（新增）**：
    - `linglong.yaml` 模板中 `version: "${ll_version}"` 和 `package.version: ${ll_version}` **必須保持為變量**
    - **絕對禁止**在生成工程時將 version 替換為 `"1.0"`、`"0.0.1"` 等絕對值
    - version **只能**由 `pak_linyaps.sh` 在構建時透過 `envsubst` 自動替換
    - 若 LLM 錯誤地將 version 寫死，`validate_linglong_yaml.py` 將在兼容性測試中報錯

---

## 依賴

### 構建腳本（scripts/）
- `extract_appimage.sh`：AppImage 解壓腳本（使用 --appimage-extract）
- `resolve_exec_command.sh`：Exec 命令解析腳本（從 desktop 文件提取）
- `parse_appimage_metadata.sh`：元數據提取腳本（從 AppImage 和 desktop 文件提取）
- `parse_build_config.sh`：JSON 配置解析腳本（解析 `build_config.json`，驗證必填欄位，輸出 `key=value` 格式）
- `dedup_desktop_files.sh`：Desktop 文件去重腳本（兩步去重：binary vs files_res + files_res 內部）
- `validate_bin_nesting.sh`：嵌套 bin/ 路徑驗證腳本

### 外部工具
- `jq`：JSON 解析工具（`parse_build_config.sh` 依賴）
- `ll-builder`：玲瓏構建工具（build + export + push）
- `desktop-file-validate`：desktop 文件驗證工具
- `envsubst`：環境變量替換工具（生成 linglong.yaml）

### 配置文件
- `examples/build_config.example.json`：JSON 配置範例文件（`main`/`optional` 分組結構）
- `config/base_runtime_whitelist.conf`：base/runtime 白名單配置
- `templates/linglong.yaml`：玲瓏工程模板（含 build 段）
