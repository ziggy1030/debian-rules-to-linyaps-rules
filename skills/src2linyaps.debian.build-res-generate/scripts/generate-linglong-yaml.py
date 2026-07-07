#!/usr/bin/env python3
"""
generate-linglong-yaml.py — 基于 analyze-control 输出的依赖信息 + analyze-rules 输出的 build 段，
结合模板和默认值配置，生成完整的 linglong.yaml。

用法:
    python3 generate-linglong-yaml.py \\
        --control-info <path> \\
        --build-section <string> \\
        --package-version <version> \\
        --template-with-deps <path> \\
        --template-without-deps <path> \\
        --output <path> \\
        [--defaults <path>] \\
        [--architecture <arch>] \\
        [--base <base>] \\
        [--runtime <runtime>] \\
        [--command <cmd>]

取值优先级: CLI 显式参数 > defaults JSON > 硬编码默认值
"""

import argparse
import json
import os
import re
import sys
import yaml

SPDX_HEADER = """# SPDX-FileCopyrightText: 2023 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: LGPL-3.0-or-later
"""


class LiteralBlock(str):
    """标记为 YAML 字面块标量 (|) 的字符串"""


def literal_block_representer(dumper, data):
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')


yaml.add_representer(LiteralBlock, literal_block_representer)


def strip_version_constraint(dep: str) -> str:
    dep = re.sub(r'\s*\([^)]*\)', '', dep).strip()
    dep = re.sub(r'\s*<[^>]+>', '', dep).strip()
    dep = re.sub(r':\w+$', '', dep).strip()
    return dep


def read_yaml(path: str) -> dict:
    with open(path, 'r', encoding='utf-8') as f:
        return yaml.safe_load(f)


def read_json(path: str) -> dict:
    with open(path, 'r', encoding='utf-8') as f:
        return json.load(f)


def get_value(cli_val, default_val):
    return cli_val if cli_val is not None else default_val


def build_yaml(data, build_section, version, architecture, base, runtime, command, with_deps):
    pkg_name = data.get('pkgName', '') or ''
    description = data.get('pkgDescription', '') or ''
    raw_build_depends = data.get('buildDepends', []) or []
    runtime_depends = data.get('runtimeDepends', []) or []

    build_depends = [strip_version_constraint(d) for d in raw_build_depends if strip_version_constraint(d)]

    if not build_section.endswith('\n'):
        build_section += '\n'

    result = {
        'version': version,
        'package': {
            'id': pkg_name,
            'name': pkg_name,
            'version': version,
            'kind': 'app',
            'architecture': architecture,
            'description': description,
        },
        'base': base,
        'runtime': runtime,
        'buildext': {
            'apt': {},
        },
        'command': command if command else '',
        'build': LiteralBlock(build_section),
    }

    if with_deps:
        result['buildext']['apt']['build_depends'] = build_depends
        result['buildext']['apt']['depends'] = runtime_depends
    else:
        result['buildext']['apt']['depends'] = runtime_depends

    return result


def main():
    parser = argparse.ArgumentParser(description='Generate linglong.yaml')
    parser.add_argument('--control-info', required=True)
    parser.add_argument('--build-section', default='')
    parser.add_argument('--package-version', default=None)
    parser.add_argument('--architecture', default=None)
    parser.add_argument('--base', default=None)
    parser.add_argument('--runtime', default=None)
    parser.add_argument('--command', default=None)
    parser.add_argument('--defaults', default='')
    parser.add_argument('--template-with-deps', required=True)
    parser.add_argument('--template-without-deps', required=True)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()

    control_info = read_yaml(args.control_info)

    defaults = {}
    if args.defaults and os.path.isfile(args.defaults):
        defaults = read_json(args.defaults)

    build_depends_raw = control_info.get('buildDepends', []) or []
    with_deps = bool(build_depends_raw)

    version = get_value(args.package_version, defaults.get('version', '0.0.0.1'))
    architecture = get_value(args.architecture, defaults.get('architecture', 'x86_64'))
    base = get_value(args.base, defaults.get('base', ''))
    runtime = get_value(args.runtime, defaults.get('runtime', ''))
    command = get_value(args.command, defaults.get('command', ''))
    build_section = args.build_section if args.build_section else defaults.get('build_section_fallback', '')

    result = build_yaml(control_info, build_section, version, architecture, base, runtime, command, with_deps)

    os.makedirs(os.path.dirname(args.output) or '.', exist_ok=True)
    with open(args.output, 'w', encoding='utf-8') as f:
        f.write(SPDX_HEADER)
        f.write('\n')
        yaml.dump(result, f, default_flow_style=False, allow_unicode=True, sort_keys=False, width=4096)

    print(f"linglong.yaml generated: {args.output}")


if __name__ == '__main__':
    main()