# ${PREFIX} 安装目录约束 — 修改方案

## 背景

源码项目 init/update 构建任务中，安装目录参数未正确使用 `${PREFIX}`，而是硬编码为 `/usr` 或 `/usr/local`。  
见 `examples/src-build.error.yaml` 中的正确示范。

## 变更清单

### 1. `skills/src2linyaps.debian.analyze-rules/scripts/analyze-rules.py`

| 位置 | 当前值 | 改为 |
|------|--------|------|
| L71 cmake `CMAKE_INSTALL_PREFIX` default | `/usr` | `${PREFIX}` |
| L88 meson `prefix` default | `/usr` | `${PREFIX}` |
| L91 autotools `prefix` default | `/usr` | `${PREFIX}` |
| L94 make `prefix` default | `/usr/local` | `${PREFIX}` |
| L170 autotools 构建模板 | `--prefix=${prefix}` 硬编码 + `{args_str}` 重复 | 移除硬编码 `--prefix=`，改为 `{args_str}` 统一传入 |

### 2. `skills/src2linyaps.source.analyze-args/scripts/extract-build-args.py`

| 位置 | 当前值 | 改为 |
|------|--------|------|
| L23 cmake `CMAKE_INSTALL_PREFIX` default | `/usr/local` | `${PREFIX}` |
| L44 meson `prefix` default | `/usr/local` | `${PREFIX}` |
| L65 make `prefix` default | `/usr/local` | `${PREFIX}` |
| L89 autotools `prefix` default | `/usr/local` | `${PREFIX}` |

### 3. `skills/src2linyaps.debian.build-res-generate/scripts/validate-linglong-yaml.py`

新增 10 条安装目录硬编码校验规则（L148-L172），在 `build:` 段校验后执行：

| # | 校验模式 | 检查目标 |
|---|---------|---------|
| 1 | `-DCMAKE_INSTALL_PREFIX=/` | CMake 安装前缀硬编码 |
| 2 | `-Dprefix=/` | CMake/Meson 前缀硬编码 |
| 3 | `--prefix=/` | Autotools 前缀硬编码 |
| 4 | `prefix=/` | Makefile 变量前缀硬编码 |
| 5 | `-DCMAKE_INSTALL_{BINDIR,LIBDIR,...}=/` | CMake 11 个子目录变量硬编码 |
| 6 | `--{bindir,libdir,...}=/` | Autotools 11 个子目录选项硬编码 |
| 7 | `DESTDIR=/` | staging 安装根目录硬编码 |
| 8 | `INSTALL_ROOT=/` | CMake 安装根目录硬编码 |
| 9 | `PREFIX=/` | 大写 PREFIX 变量硬编码 |
| 10 | `LIB_INSTALL_DIR=/` | qmake/CMake 库目录硬编码 |

所有规则均包含 `(?!\$\{PREFIX\}|\$PREFIX)` 负向前瞻，已正确的变量引用不会被误报。系统命令（`apt-get`、`dpkg`）中的 `/usr` 不在检查范围内（仅匹配 `param=value` 格式）。  
报错模板：`field 'build' uses hardcoded path '{match}' instead of ${PREFIX}`。

### 4. `skills/src2linyaps.debian.build-res-generate/scripts/generate-linglong-yaml.py`

新增 `replace_hardcoded_prefixes()` 函数（L88-L103），在 `build_yaml()` 中 `${prefix}` → `${PREFIX}` 替换后调用，作为 LLM 生成 `build_section` 的**安全网自动修正层**。

10 条正则替换规则（与校验规则一一对应）：

| 输入硬编码 | 替换结果 |
|-----------|---------|
| `-DCMAKE_INSTALL_PREFIX=/usr` | `${PREFIX}` |
| `-Dprefix=/usr` | `${PREFIX}` |
| `--prefix=/usr` | `${PREFIX}` |
| `prefix=/usr` | `${PREFIX}` |
| `-DCMAKE_INSTALL_BINDIR=/usr/bin` | `${PREFIX}/bin`（保留子目录） |
| `--bindir=/usr/bin` | `${PREFIX}/bin`（保留子目录） |
| `DESTDIR=/usr` | `${PREFIX}` |
| `INSTALL_ROOT=/usr` | `${PREFIX}` |
| `PREFIX=/usr` | `${PREFIX}` |
| `LIB_INSTALL_DIR=/usr/lib` | `${PREFIX}/lib`（保留子目录） |

工作原理：LLM 生成 `build_section` → `generate-linglong-yaml.py` 正则替换 → `validate-linglong-yaml.py` 校验残留 → 输出最终 `linglong.yaml`。  
**双层安全网**：自动替换 + 校验报错，确保无硬编码路径泄漏。

### 5. `skills/config/linglong-schema.yaml`

新增注释说明安装目录必须使用 `${PREFIX}`（约束文档化）。

### 6. `agents/debian-rules-to-linyaps.agent.md`

在 `## 约束条件` 章节新增 `${PREFIX} 安装目录约束`：

- 所有构建工具的安装目录参数必须使用 `${PREFIX}`
- 禁止 `-DCMAKE_INSTALL_PREFIX=/usr`、`--prefix=/usr`、`prefix=/usr/local`
- 二进制文件 → `${PREFIX}/bin`，库文件 → `${PREFIX}/lib`
- 校验阶段通过 `validate-linglong-yaml.py` 检查

### 7. `skills/src2linyaps.source.analyze-args/SKILL.md`

更新输出示例中的 `default` 值为 `${PREFIX}` 而非 `/usr/local`。末尾新增约束说明：所有安装目录参数的默认值必须使用 `${PREFIX}`。

### 8. `skills/src2linyaps.debian.analyze-rules/SKILL.md`

末尾新增 `${PREFIX} 安装目录约束` 说明：`build_args` 中所有安装目录参数的值必须使用 `${PREFIX}` 而非 `/usr`/`/usr/local`。

### 9. `skills/src2linyaps.debian.build-res-generate/SKILL.md`

末尾新增 `${PREFIX} 安装目录约束` 说明：`build:` 字段中所有安装目录路径必须使用 `${PREFIX}`（大写），并声明 `generate-linglong-yaml.py` 会自动将硬编码路径替换为 `${PREFIX}` 作为安全网。

## 验证

### 输出示例
生成后的 `build:` 段应类似：

```yaml
build: |
  cmake -B build-linglong \
    -DCMAKE_INSTALL_PREFIX=${PREFIX} \
    -DCMAKE_BUILD_TYPE=Release
  cmake --build build-linglong -j$(nproc)
  cmake --install build-linglong
  touch ${PREFIX}/.linyaps_genius
  chmod -R 755 ${PREFIX}
```

通过 `validate-linglong-yaml.py --schema linglong-schema.yaml` 校验不报硬编码路径错误。

### 测试结果
- **58 项单元测试全部通过**，覆盖以下场景：
  - 11 个 CMake 子目录变量（BINDIR/LIBDIR/INCLUDEDIR/...）各场景独立测试
  - 11 个 Autotools 子目录选项（--bindir/--libdir/...）各场景独立测试
  - DESTDIR/INSTALL_ROOT/PREFIX/LIB_INSTALL_DIR 各场景独立测试
  - 混合真实场景（多个硬编码同时出现）
  - 非安装路径中的 `/usr`（如 `cp /usr/share/config.sub`）不应被误替换
  - 已有的 `${PREFIX}`/`$PREFIX` 不应被二次替换
- `tests/test-mismatch.sh` 仍通过，无回归