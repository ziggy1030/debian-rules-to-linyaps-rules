#!/usr/bin/env python3
"""
validate-linglong-yaml.py — 检测生成的 linglong.yaml 格式化问题。

检查项:
  - YAML 可解析
  - JSON 可序列化（模拟 ll-builder 的 nlohmann-json C++ 解析器）
  - command 为数组（非 string/null）
  - version / package.* 为字符串
  - base / runtime 非空字符串
  - buildext.apt 存在，build_depends 和 depends 为 list
  - build 为字符串
  - 无 sources 段（按约束）
  - build_depends 条目无版本约束残留

用法:
    python3 validate-linglong-yaml.py <path> [--command command]
    python3 validate-linglong-yaml.py <path> --command "kate --new"

退出码: 0 = 通过, 1 = 失败
"""

import argparse
import json
import re
import sys
import yaml

COMMAND_MUST_BE_LIST = "field 'command' must be a list (not string/null/missing)"
VERSION_MUST_BE_STR = "field 'version' must be a string"
PACKAGE_MUST_HAVE = "package must have non-empty 'id', 'name', 'version', 'kind'"
BASE_RUNTIME_REQUIRED = "fields 'base' and 'runtime' must be non-empty strings"
BUILDEXT_APT_REQUIRED = "buildext.apt must be present"
DEPS_MUST_BE_LIST = "buildext.apt.{key} must be a list"
BUILD_MUST_BE_STR = "field 'build' must be a string"
NO_SOURCES = "sources section should not be present (use constraint)"
NO_VERSION_CONSTRAINT = "dep entry '{dep}' still contains version constraint"


def validate(path: str) -> list:
    errors = []

    # 1. Parse YAML
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f)
    except yaml.YAMLError as e:
        return [f"YAML parse error: {e}"]

    if not isinstance(data, dict):
        return [f"Top-level must be a mapping, got {type(data).__name__}"]

    # 2. JSON serialization (simulates ll-builder nlohmann-json behavior)
    try:
        json.dumps(data)
    except (TypeError, ValueError) as e:
        errors.append(f"JSON serialization error: {e}")

    # 3. command must be a list
    cmd = data.get('command')
    if not isinstance(cmd, list):
        errors.append(f"{COMMAND_MUST_BE_LIST} (got {type(cmd).__name__}: {cmd!r})")
    else:
        for i, item in enumerate(cmd):
            if not isinstance(item, str):
                errors.append(f"command[{i}] must be a string, got {type(item).__name__}: {item!r}")

    # 4. version must be a string
    ver = data.get('version')
    if not isinstance(ver, str) or not ver:
        errors.append(f"{VERSION_MUST_BE_STR} (got {type(ver).__name__}: {ver!r})")

    # 5. package section
    pkg = data.get('package')
    if not isinstance(pkg, dict):
        errors.append(f"package must be a mapping, got {type(pkg).__name__}")
    else:
        for field in ('id', 'name', 'version', 'kind'):
            val = pkg.get(field)
            if not isinstance(val, str) or not val:
                errors.append(f"{PACKAGE_MUST_HAVE} (field '{field}' is {val!r})")

    # 6. base and runtime
    for field in ('base', 'runtime'):
        val = data.get(field)
        if not isinstance(val, str) or not val:
            errors.append(f"{BASE_RUNTIME_REQUIRED} (field '{field}' is {val!r})")

    # 7. buildext.apt
    buildext = data.get('buildext')
    if not isinstance(buildext, dict):
        errors.append(f"buildext must be a mapping, got {type(buildext).__name__}")
    else:
        apt = buildext.get('apt')
        if not isinstance(apt, dict):
            errors.append(f"{BUILDEXT_APT_REQUIRED} (got {type(apt).__name__})")
        else:
            for key in ('build_depends', 'depends'):
                val = apt.get(key)
                if val is not None and not isinstance(val, list):
                    errors.append(DEPS_MUST_BE_LIST.format(key=key))
                elif val is not None:
                    for i, entry in enumerate(val):
                        if not isinstance(entry, str):
                            errors.append(f"buildext.apt.{key}[{i}] must be a string")

    # 8. build must be a string
    build_val = data.get('build')
    if not isinstance(build_val, str):
        errors.append(f"{BUILD_MUST_BE_STR} (got {type(build_val).__name__})")

    # 9. No sources section
    if 'sources' in data:
        errors.append(NO_SOURCES)

    # 10. build_depends entries with version constraints
    apt = (data.get('buildext') or {}).get('apt') or {}
    for dep in apt.get('build_depends') or []:
        if isinstance(dep, str):
            if re.search(r'\([^)]*\)', dep) or re.search(r'[><=!]', dep):
                errors.append(NO_VERSION_CONSTRAINT.format(dep=dep))

    return errors


def main():
    parser = argparse.ArgumentParser(description='Validate linglong.yaml formatting')
    parser.add_argument('path', help='Path to linglong.yaml')
    args = parser.parse_args()

    errors = validate(args.path)

    if errors:
        print(f"FAIL: {len(errors)} issue(s) found", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        sys.exit(1)
    else:
        print("PASS: linglong.yaml format is valid")
        sys.exit(0)


if __name__ == '__main__':
    main()