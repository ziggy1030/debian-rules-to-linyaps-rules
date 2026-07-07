---
name: compat-testing
description: >
  执行玲珑打包构建测试，验证生成的工程是否可以正常构建，
  并运行兼容性检测确保应用能在玲珑环境中正常运行。
user-invocable: false
---

# 兼容性测试

## 功能说明

执行玲珑打包构建测试，验证生成的工程是否可以正常构建，并运行兼容性检测确保应用能在玲珑环境中正常运行。

## 触发场景

- 需要测试打包脚本是否正常工作
- 需要验证linglong.yaml格式正确性
- 需要检测应用运行时兼容性
- 需要在推送前验证构建结果

## 工作流程

### 1. 验证 linglong.yaml 格式

调用 `scripts/validate_linglong_yaml.py`：

```bash
cd scripts
python3 validate_linglong_yaml.py \
  --input templates/linglong.yaml \
  --exec-name "$(get_exec_from_desktop)" \
  --json \
  --output reports/yaml_validation.json
```

验证项：
- YAML语法正确
- 必需字段存在（version, package.*, base, command, build）
- command与desktop Exec一致
- 版本格式正确（x.x.x.x）
- 缩进格式正确

### 2. 验证资源目录结构

调用 `scripts/common-data-verify.py`：

```bash
cd scripts
python3 common-data-verify.py \
  templates/files_res \
  --json \
  --output reports/structure_validation.json
```

验证项：
- desktop文件格式正确
- 图标目录结构规范
- 二进制文件可执行

### 3. 执行打包测试

运行 `pak_linyaps.sh`：

```bash
cd CI_ll_<package_id>

# 准备测试环境
mkdir -p src bins
cp <deb_file> src/

# 执行打包
./pak_linyaps.sh \
  --linyaps_arch=x86_64 \
  --origin_version=<version> \
  --src_path=src/<deb_name> \
  --output_dir=bins

# 检查构建结果
if [ -f bins/*binary.layer ]; then
  echo "Build success"
else
  echo "Build failed"
fi
```

### 4. 运行兼容性检测

调用 `scripts/demos/compat_checker.py`：

```python
import sys
sys.path.insert(0, "scripts")
from demos.compat_checker import CompatChecker
from pathlib import Path

checker = CompatChecker(
    build_dir=Path("/path/to/build/tmp"),
    enable_compat_check=True,
    timeout=30,
    verbose=True
)

success, message = checker.check()
status = checker.get_status()  # "passed", "failed", "N/A"

if not success:
    error_log = checker.get_error_log_content()
    print(f"Compat check failed: {message}")
    print(f"Error log:\n{error_log}")
```

或使用 `ll-builder run`：

```bash
cd <build_tmp_dir>
timeout 30 ll-builder run || exit_code=$?

# exit_code 0: 正常退出
# exit_code 124: 超时（应用持续运行，视为成功）
# 其他: 运行失败
```

### 5. 生成测试报告

```json
{
  "package_id": "com.example.app",
  "test_time": "2024-01-15T10:30:00Z",
  "overall_status": "passed",
  "tests": {
    "yaml_validation": {
      "status": "passed",
      "details": []
    },
    "structure_validation": {
      "status": "passed",
      "details": []
    },
    "build_test": {
      "status": "passed",
      "output_layer": "bins/com.example.app-binary.layer",
      "build_time": "45.2s"
    },
    "compat_check": {
      "status": "passed",
      "timeout": 30,
      "exit_code": 124
    }
  },
  "errors": [],
  "warnings": []
}
```

## 测试失败处理

| 失败类型 | 处理方式 |
|---------|---------|
| YAML格式错误 | 调用 linglong-fix skill 修复 |
| 资源结构问题 | 调用 linglong-fix skill 修复 |
| 构建失败 | 分析错误日志，提示用户检查 |
| 兼容性失败 | 保存错误日志，调用 linglong-fix skill |

## 错误日志位置

```
CI_ll_<package_id>/
└── reports/
    ├── yaml_validation.json
    ├── structure_validation.json
    ├── build.log
    └── compat-check-errors/
        └── run-error.log
```

## 依赖工具

- `ll-builder` - 玲珑构建工具
- `dpkg` - deb包处理
- `timeout` - 超时控制
- Python库: `yaml`, `pathlib`

## 注意事项

1. 构建测试需要足够的磁盘空间
2. 兼容性检测超时视为成功（应用正常启动并持续运行）
3. 测试失败时保存完整日志便于分析
4. 多架构需要分别测试
5. 测试完成后可清理临时构建目录
