#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
deb_to_linglong.py - 解析 deb 文件并生成 linglong.yaml

该脚本用于：
1. 解析 deb 文件提取元数据（Package, Version, Architecture, Description, Depends等）
2. 将提取的信息填充到 linglong.yaml 模板中
3. 支持导入、解压 deb 到指定目录

使用示例：
  # 基本用法：解析 deb 并生成 YAML
  python3 deb_to_linglong.py package.deb --base org.deepin.base/25.2.2

  # 指定 runtime
  python3 deb_to_linglong.py package.deb --base org.deepin.base/25.2.2 --runtime org.deepin.runtime.dtk/25.2.2

  # 同时解压 deb 文件
  python3 deb_to_linglong.py package.deb --base org.deepin.base/25.2.2 --extract-dir /tmp/extracted

  # 使用自定义架构映射
  python3 deb_to_linglong.py package.deb --base org.deepin.base/25.2.2 --arch-map amd64=x86_64,arm64=aarch64

  # 使用外部模板
  python3 deb_to_linglong.py package.deb --base org.deepin.base/25.2.2 --template custom.yaml
"""

import argparse
import functools
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import tarfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple

try:
    import yaml
except ImportError:
    print("错误: 缺少 PyYAML 库，请运行: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

# 缓存目录
CACHE_DIR = os.path.join(tempfile.gettempdir(), "deb_to_linglong_cache")
os.makedirs(CACHE_DIR, exist_ok=True)


# 默认架构映射
DEFAULT_ARCH_MAP = {
    "amd64": "x86_64",
    "arm64": "aarch64",
    "i386": "x86",
    "armhf": "armhf",
    "armel": "armel",
}

# 默认 linglong.yaml 模板
DEFAULT_TEMPLATE = """# SPDX-FileCopyrightText: 2023 UnionTech Software Technology Co., Ltd.
#
# SPDX-License-Identifier: LGPL-3.0-or-later

version: "{version}"

package:
  id: {package_id}
  name: "{package_name}"
  version: {version}
  kind: app
  architecture: {architecture}
  description: |
    {description}

base: {base}
{runtime_line}

buildext:
  apt:
    depends:{depends}

command:
  - "{command}"

build: |
  ##Extract res
  cp -rf /project/binary/* ${{prefix}}/
  cp -rf /project/files_res/* ${{prefix}}/
"""


def get_file_hash(file_path: str) -> str:
    """
    计算文件的 MD5 哈希值用于缓存键

    Args:
        file_path: 文件路径

    Returns:
        MD5 哈希字符串
    """
    hash_md5 = hashlib.md5()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(4096), b""):
            hash_md5.update(chunk)
    return hash_md5.hexdigest()


def cache_result(func):
    """
    缓存装饰器，用于缓存函数结果到文件系统

    使用文件哈希作为缓存键，避免重复处理相同的 deb 文件
    """

    @functools.wraps(func)
    def wrapper(deb_file: str, *args, **kwargs):
        # 计算文件哈希作为缓存键
        file_hash = get_file_hash(deb_file)
        cache_file = os.path.join(CACHE_DIR, f"{func.__name__}_{file_hash}.json")

        # 尝试从缓存读取
        if os.path.exists(cache_file):
            try:
                with open(cache_file, "r", encoding="utf-8") as f:
                    cached_data = json.load(f)
                    print(f"✓ 从缓存读取: {func.__name__}")
                    return cached_data
            except (json.JSONDecodeError, IOError):
                # 缓存损坏，继续执行函数
                pass

        # 执行函数
        result = func(deb_file, *args, **kwargs)

        # 保存到缓存
        try:
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump(result, f, ensure_ascii=False, indent=2)
        except IOError:
            # 缓存写入失败，不影响主流程
            pass

        return result

    return wrapper


def extract_control_file_via_ar(deb_file: str) -> str:
    """
    使用 ar -x 提取 control 文件内容（后备方案）

    Args:
        deb_file: deb 文件路径

    Returns:
        control 文件内容

    Raises:
        ValueError: 提取失败时
    """
    with tempfile.TemporaryDirectory() as temp_dir:
        # 使用 ar 解压 deb 归档
        try:
            subprocess.run(
                ["ar", "-x", deb_file], cwd=temp_dir, check=True, capture_output=True
            )
        except subprocess.CalledProcessError as e:
            raise ValueError(f"ar 解压失败: {e}")
        except FileNotFoundError:
            raise ValueError("ar 命令未找到，请确保已安装 binutils")

        # 查找 control 文件
        control_tar = None
        for file in os.listdir(temp_dir):
            if file.startswith("control."):
                control_tar = os.path.join(temp_dir, file)
                break

        if not control_tar:
            raise ValueError("无法找到 control 归档文件")

        # 解压 control
        try:
            with tarfile.open(control_tar, "r:*") as tar:
                tar.extractall(temp_dir)
        except Exception as e:
            raise ValueError(f"解压 control 归档失败: {e}")

        # 读取 control 文件
        control_file = os.path.join(temp_dir, "control")
        if not os.path.exists(control_file):
            raise ValueError("control 文件不存在")

        with open(control_file, "r", encoding="utf-8", errors="ignore") as f:
            return f.read()


@cache_result
def extract_deb_info(deb_file: str) -> Dict[str, str]:
    """
    从 deb 文件中提取元数据信息

    优先使用 dpkg -I，失败时回退到 ar -x 方式

    Args:
        deb_file: deb 文件路径

    Returns:
        包含元数据的字典

    Raises:
        ValueError: 当缺少必要字段时
    """
    if not os.path.isfile(deb_file):
        raise ValueError(f"deb 文件不存在: {deb_file}")

    output = None
    use_fallback = False

    # 尝试使用 dpkg -I 命令提取信息
    try:
        result = subprocess.run(
            ["dpkg", "-I", deb_file],
            capture_output=True,
            text=True,
            check=True,
            timeout=30,
        )
        output = result.stdout
        print("✓ 使用 dpkg -I 提取信息")
    except subprocess.CalledProcessError as e:
        print(f"⚠ dpkg -I 失败: {e}，尝试使用后备方案", file=sys.stderr)
        use_fallback = True
    except FileNotFoundError:
        print("⚠ dpkg 命令未找到，尝试使用后备方案", file=sys.stderr)
        use_fallback = True
    except subprocess.TimeoutExpired:
        print("⚠ dpkg -I 超时，尝试使用后备方案", file=sys.stderr)
        use_fallback = True

    # 使用后备方案：ar -x + 手动解析 control 文件
    if use_fallback or not output:
        try:
            output = extract_control_file_via_ar(deb_file)
            print("✓ 使用 ar -x 后备方案提取信息")
        except Exception as e:
            raise ValueError(f"后备方案也失败: {e}")

    # 解析输出
    info = {}

    # 提取 Package 字段
    match = re.search(r"^ Package:\s*(.+)$", output, re.MULTILINE)
    info["Package"] = match.group(1).strip() if match else None

    # 提取 Source 字段（可选）
    match = re.search(r"^ Source:\s*(.+)$", output, re.MULTILINE)
    info["Source"] = match.group(1).strip() if match else info.get("Package")

    # 提取 Version 字段
    match = re.search(r"^ Version:\s*(.+)$", output, re.MULTILINE)
    info["Version"] = match.group(1).strip() if match else None

    # 提取 Architecture 字段
    match = re.search(r"^ Architecture:\s*(.+)$", output, re.MULTILINE)
    info["Architecture"] = match.group(1).strip() if match else None

    # 提取 Description 字段
    match = re.search(r"^ Description:\s*(.+)$", output, re.MULTILINE)
    info["Description"] = match.group(1).strip() if match else None

    # 提取 Homepage 字段（可选）
    match = re.search(r"^ Homepage:\s*(.+)$", output, re.MULTILINE)
    info["Homepage"] = match.group(1).strip() if match else None

    # 提取 Depends 字段
    match = re.search(r"^ Depends:\s*(.+)$", output, re.MULTILINE)
    info["Depends"] = match.group(1).strip() if match else None

    # 验证必要字段
    missing_fields = []
    for field in ["Package", "Version", "Architecture"]:
        if not info.get(field):
            missing_fields.append(field)

    if missing_fields:
        raise ValueError(f"deb 文件缺少必要字段: {', '.join(missing_fields)}")

    return info


def parse_depends(depends_str: Optional[str]) -> List[str]:
    """
    解析依赖字符串，去除版本号和架构限定符

    Args:
        depends_str: 依赖字符串，如 "libssl1.1 (>= 1.1.1), libcurl4:amd64 (>= 7.0)"

    Returns:
        纯净的依赖包名列表，如 ["libssl1.1", "libcurl4"]
    """
    if not depends_str:
        return []

    dependencies = []

    # 按逗号分割
    for dep in depends_str.split(","):
        dep = dep.strip()
        if not dep:
            continue

        # 去除架构限定符 (如 :amd64, :arm64)
        dep = re.sub(r":[a-z0-9]+", "", dep)

        # 去除版本号约束 (如 (>= 1.1.1), (<< 2.0))
        dep = re.sub(r"\s*\([^)]+\)", "", dep)

        # 去除替代操作符 (如 |)
        dep = dep.split("|")[0].strip()

        # 去除剩余空格
        dep = dep.strip()

        if dep:
            dependencies.append(dep)

    return dependencies


def convert_version_to_linglong(deb_version: str) -> str:
    """
    将 deb 版本号转换为 linglong 格式 (x.x.x.x)

    Args:
        deb_version: deb 版本号，如 "1.2.3-1", "1:2.3.4-5ubuntu1"

    Returns:
        linglong 格式的版本号，如 "1.2.3.1", "2.3.4.5"
    """
    # 去除 epoch (如 "1:2.3.4" -> "2.3.4")
    if ":" in deb_version:
        deb_version = deb_version.split(":", 1)[1]

    # 去除后缀 (如 "1.2.3-1ubuntu1" -> "1.2.3-1")
    deb_version = re.sub(r"[a-zA-Z].*$", "", deb_version)

    # 提取所有数字部分
    parts = re.findall(r"\d+", deb_version)

    # 补齐到4个部分
    while len(parts) < 4:
        parts.append("0")

    # 只取前4个部分
    version = ".".join(parts[:4])

    return version


def map_architecture(deb_arch: str, arch_map: Optional[Dict[str, str]] = None) -> str:
    """
    将 deb 架构映射到 linglong 架构

    Args:
        deb_arch: deb 架构名称，如 "amd64", "arm64"
        arch_map: 自定义架构映射字典

    Returns:
        linglong 架构名称，如 "x86_64", "aarch64"
    """
    if arch_map is None:
        arch_map = DEFAULT_ARCH_MAP

    return arch_map.get(deb_arch, deb_arch)


def parse_arch_map_string(arch_map_str: str) -> Dict[str, str]:
    """
    解析架构映射字符串

    Args:
        arch_map_str: 架构映射字符串，如 "amd64=x86_64,arm64=aarch64"

    Returns:
        架构映射字典
    """
    arch_map = {}
    for mapping in arch_map_str.split(","):
        mapping = mapping.strip()
        if "=" in mapping:
            key, value = mapping.split("=", 1)
            arch_map[key.strip()] = value.strip()
    return arch_map


def generate_linglong_yaml(
    deb_info: Dict[str, str],
    base: str,
    runtime: Optional[str] = None,
    template_path: Optional[str] = None,
    arch_map: Optional[Dict[str, str]] = None,
) -> str:
    """
    生成 linglong.yaml 内容

    Args:
        deb_info: deb 元数据字典
        base: base 字段值
        runtime: runtime 字段值（可选）
        template_path: 外部模板文件路径（可选）
        arch_map: 架构映射字典

    Returns:
        YAML 字符串
    """
    # 获取包信息
    package_id = deb_info["Package"]
    package_name = deb_info.get("Source", package_id)
    version = convert_version_to_linglong(deb_info["Version"])
    architecture = map_architecture(deb_info["Architecture"], arch_map)
    description = deb_info.get("Description", "No description available")

    # 解析依赖
    depends = parse_depends(deb_info.get("Depends"))
    depends_str = "\n      - " + "\n      - ".join(depends) if depends else " []"

    # 处理 runtime 行
    runtime_line = f"runtime: {runtime}" if runtime else ""

    # 推断命令名称
    command = package_id

    # 使用外部模板或默认模板
    if template_path and os.path.isfile(template_path):
        with open(template_path, "r", encoding="utf-8") as f:
            template = f.read()
    else:
        template = DEFAULT_TEMPLATE

    # 替换模板变量
    yaml_content = template.format(
        version=version,
        package_id=package_id,
        package_name=package_name,
        architecture=architecture,
        description=description,
        base=base,
        runtime_line=runtime_line,
        depends=depends_str,
        command=command,
    )

    return yaml_content


def extract_deb_archive(deb_file: str, target_dir: str) -> Tuple[str, str]:
    """
    解压 deb 文件到指定目录

    优先使用 ar -x 方式（更兼容），失败时尝试 dpkg -x

    Args:
        deb_file: deb 文件路径
        target_dir: 目标目录

    Returns:
        (control目录路径, data目录路径)

    Raises:
        ValueError: 解压失败时
    """
    if not os.path.isfile(deb_file):
        raise ValueError(f"deb 文件不存在: {deb_file}")

    # 创建目标目录
    os.makedirs(target_dir, exist_ok=True)

    # 方案1: 使用 ar -x 解压（推荐，更兼容）
    try:
        control_dir, data_dir = _extract_via_ar(deb_file, target_dir)
        print("✓ 使用 ar -x 解压成功")
        return control_dir, data_dir
    except Exception as e:
        print(f"⚠ ar -x 解压失败: {e}，尝试使用 dpkg -x 后备方案", file=sys.stderr)

    # 方案2: 使用 dpkg -x 解压（后备方案）
    try:
        control_dir, data_dir = _extract_via_dpkg(deb_file, target_dir)
        print("✓ 使用 dpkg -x 后备方案解压成功")
        return control_dir, data_dir
    except Exception as e:
        raise ValueError(f"所有解压方案都失败: {e}")


def _extract_via_ar(deb_file: str, target_dir: str) -> Tuple[str, str]:
    """
    使用 ar -x 解压 deb 文件

    Args:
        deb_file: deb 文件路径
        target_dir: 目标目录

    Returns:
        (control目录路径, data目录路径)
    """
    # 创建临时目录用于解压
    with tempfile.TemporaryDirectory() as temp_dir:
        # 使用 ar 解压 deb 归档
        try:
            subprocess.run(
                ["ar", "-x", deb_file],
                cwd=temp_dir,
                check=True,
                capture_output=True,
                timeout=60,
            )
        except subprocess.CalledProcessError as e:
            raise ValueError(f"ar 解压失败: {e}")
        except FileNotFoundError:
            raise ValueError("ar 命令未找到，请确保已安装 binutils")
        except subprocess.TimeoutExpired:
            raise ValueError("ar 解压超时")

        # 查找 control 和 data 文件
        control_tar = None
        data_tar = None

        for file in os.listdir(temp_dir):
            file_path = os.path.join(temp_dir, file)
            if file.startswith("control."):
                control_tar = file_path
            elif file.startswith("data."):
                data_tar = file_path

        if not control_tar or not data_tar:
            raise ValueError("无法找到 control 或 data 归档文件")

        # 解压 control 和 data
        control_dir = os.path.join(target_dir, "control")
        data_dir = os.path.join(target_dir, "data")

        os.makedirs(control_dir, exist_ok=True)
        os.makedirs(data_dir, exist_ok=True)

        # 解压 control
        try:
            with tarfile.open(control_tar, "r:*") as tar:
                tar.extractall(control_dir)
        except Exception as e:
            raise ValueError(f"解压 control 归档失败: {e}")

        # 解压 data
        try:
            with tarfile.open(data_tar, "r:*") as tar:
                tar.extractall(data_dir)
        except Exception as e:
            raise ValueError(f"解压 data 归档失败: {e}")

    return control_dir, data_dir


def _extract_via_dpkg(deb_file: str, target_dir: str) -> Tuple[str, str]:
    """
    使用 dpkg -x 解压 deb 文件（后备方案）

    Args:
        deb_file: deb 文件路径
        target_dir: 目标目录

    Returns:
        (control目录路径, data目录路径)
    """
    # dpkg -x 只能解压 data 部分
    data_dir = os.path.join(target_dir, "data")
    os.makedirs(data_dir, exist_ok=True)

    try:
        subprocess.run(
            ["dpkg", "-x", deb_file, data_dir],
            check=True,
            capture_output=True,
            timeout=120,
        )
    except subprocess.CalledProcessError as e:
        raise ValueError(f"dpkg -x 解压失败: {e}")
    except FileNotFoundError:
        raise ValueError("dpkg 命令未找到")
    except subprocess.TimeoutExpired:
        raise ValueError("dpkg -x 解压超时")

    # dpkg -x 无法提取 control，需要使用 ar -x 或 dpkg -e
    # 尝试使用 dpkg -e 提取 control
    control_dir = os.path.join(target_dir, "control")
    os.makedirs(control_dir, exist_ok=True)

    try:
        subprocess.run(
            ["dpkg", "-e", deb_file, control_dir],
            check=True,
            capture_output=True,
            timeout=30,
        )
    except (
        subprocess.CalledProcessError,
        FileNotFoundError,
        subprocess.TimeoutExpired,
    ) as e:
        # dpkg -e 失败，尝试手动提取 control
        try:
            with tempfile.TemporaryDirectory() as temp_dir:
                subprocess.run(
                    ["ar", "-x", deb_file],
                    cwd=temp_dir,
                    check=True,
                    capture_output=True,
                )

                for file in os.listdir(temp_dir):
                    if file.startswith("control."):
                        control_tar = os.path.join(temp_dir, file)
                        with tarfile.open(control_tar, "r:*") as tar:
                            tar.extractall(control_dir)
                        break
        except Exception as e:
            raise ValueError(f"无法提取 control 文件: {e}")

    return control_dir, data_dir


def main():
    """主函数"""
    parser = argparse.ArgumentParser(
        description="解析 deb 文件并生成 linglong.yaml",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
使用示例:
  %(prog)s package.deb --base org.deepin.base/25.2.2
  %(prog)s package.deb --base org.deepin.base/25.2.2 --runtime org.deepin.runtime.dtk/25.2.2
  %(prog)s package.deb --base org.deepin.base/25.2.2 --extract-dir /tmp/extracted
        """,
    )

    # 必需参数
    parser.add_argument("deb_file", help="deb 文件路径")

    # 可选参数
    parser.add_argument(
        "--output-dir", default=".", help="YAML 输出目录 (默认: 当前目录)"
    )

    parser.add_argument("--template", help="外部模板文件路径")

    parser.add_argument("--extract-dir", help="解压目录 (指定则执行解压)")

    parser.add_argument("--base", required=True, help="base 字段值 (必需)")

    parser.add_argument("--runtime", help="runtime 字段值 (可选)")

    parser.add_argument(
        "--arch-map", help="架构映射规则，格式: amd64=x86_64,arm64=aarch64"
    )

    args = parser.parse_args()

    try:
        # 解析架构映射
        arch_map = None
        if args.arch_map:
            arch_map = parse_arch_map_string(args.arch_map)

        # 提取 deb 信息
        print(f"正在解析 deb 文件: {args.deb_file}")
        deb_info = extract_deb_info(args.deb_file)

        print(f"包名称: {deb_info['Package']}")
        print(f"版本: {deb_info['Version']}")
        print(f"架构: {deb_info['Architecture']}")

        # 解压 deb 文件（如果指定）
        if args.extract_dir:
            print(f"\n正在解压到: {args.extract_dir}")
            control_dir, data_dir = extract_deb_archive(args.deb_file, args.extract_dir)
            print(f"解压完成:")
            print(f"  - control: {control_dir}")
            print(f"  - data: {data_dir}")

        # 生成 YAML
        print(f"\n正在生成 linglong.yaml...")
        yaml_content = generate_linglong_yaml(
            deb_info=deb_info,
            base=args.base,
            runtime=args.runtime,
            template_path=args.template,
            arch_map=arch_map,
        )

        # 写入文件
        output_file = os.path.join(args.output_dir, f"{deb_info['Package']}.yaml")
        os.makedirs(args.output_dir, exist_ok=True)

        with open(output_file, "w", encoding="utf-8") as f:
            f.write(yaml_content)

        print(f"\n✓ 成功生成: {output_file}")

        # 显示依赖信息
        depends = parse_depends(deb_info.get("Depends"))
        if depends:
            print(f"\n依赖包 ({len(depends)} 个):")
            for dep in depends[:10]:  # 只显示前10个
                print(f"  - {dep}")
            if len(depends) > 10:
                print(f"  ... 还有 {len(depends) - 10} 个依赖")

    except ValueError as e:
        print(f"错误: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"未预期的错误: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
