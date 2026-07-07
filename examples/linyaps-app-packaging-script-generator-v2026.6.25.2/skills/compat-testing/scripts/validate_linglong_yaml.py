#!/usr/bin/env python3
"""
linglong.yaml Format Validation Script

Validates:
1. YAML syntax compliance
2. Required fields existence
3. Command field consistency with desktop Exec value
4. Version number increment (optional, when --last-ver provided)
5. Description and build field indentation format
"""

import os
import sys
import json
import argparse
import re
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple


class ValidationResult:
    """Holds validation results for a single check."""

    def __init__(self, check_name: str):
        self.check_name = check_name
        self.passed: List[Dict[str, Any]] = []
        self.failed: List[Dict[str, Any]] = []
        self.warnings: List[Dict[str, Any]] = []

    def add_pass(self, item: str, message: str = ""):
        self.passed.append({"item": item, "message": message})

    def add_fail(self, item: str, message: str):
        self.failed.append({"item": item, "message": message})

    def add_warning(self, item: str, message: str):
        self.warnings.append({"item": item, "message": message})

    def to_dict(self) -> Dict[str, Any]:
        return {
            "check_name": self.check_name,
            "passed_count": len(self.passed),
            "failed_count": len(self.failed),
            "warning_count": len(self.warnings),
            "passed": self.passed,
            "failed": self.failed,
            "warnings": self.warnings,
        }


class LinglongYamlValidator:
    """Validates linglong.yaml format compliance."""

    # Required fields in linglong.yaml
    REQUIRED_FIELDS = [
        ("version", "top-level"),
        ("package.id", "package"),
        ("package.name", "package"),
        ("package.version", "package"),
        ("package.kind", "package"),
        ("package.description", "package"),
        ("base", "top-level"),
        ("command", "top-level"),
        ("build", "top-level"),
    ]

    # Valid kind values
    VALID_KINDS = {"app", "runtime", "binary"}

    def __init__(
        self,
        input_file: str,
        exec_name: Optional[str] = None,
        last_ver: Optional[str] = None,
    ):
        self.input_file = Path(input_file).resolve()
        self.exec_name = exec_name
        self.last_ver = last_ver
        self.yaml_content: Optional[Dict[str, Any]] = None
        self.raw_content: str = ""
        self.results: Dict[str, ValidationResult] = {}

    def validate_all(self) -> Dict[str, Any]:
        """Run all validations and return results."""
        self.results = {}

        # Check if input file exists
        if not self.input_file.exists():
            return {
                "input_file": str(self.input_file),
                "error": f"Input file does not exist: {self.input_file}",
                "valid": False,
            }

        # Load YAML content
        if not self._load_yaml():
            return {
                "input_file": str(self.input_file),
                "error": "Failed to parse YAML file",
                "valid": False,
            }

        # Run validations
        self.results["yaml_format"] = self._validate_yaml_format()
        self.results["required_fields"] = self._validate_required_fields()
        self.results["base_runtime"] = self._validate_base_runtime()
        self.results["command"] = self._validate_command()

        # Optional: version validation
        if self.last_ver:
            self.results["version"] = self._validate_version()

        self.results["indentation"] = self._validate_indentation()

        # Calculate overall status
        all_passed = all(
            len(r.failed) == 0
            for r in self.results.values()
            if isinstance(r, ValidationResult)
        )

        return {
            "input_file": str(self.input_file),
            "valid": all_passed,
            "checks": {name: result.to_dict() for name, result in self.results.items()},
        }

    def _load_yaml(self) -> bool:
        """Load and parse YAML file."""
        try:
            import yaml
        except ImportError:
            print("Error: PyYAML is required. Install with: pip install pyyaml")
            return False

        try:
            self.raw_content = self.input_file.read_text(encoding="utf-8")
            self.yaml_content = yaml.safe_load(self.raw_content)
            return True
        except yaml.YAMLError as e:
            self.results["yaml_format"] = ValidationResult("YAML Format Validation")
            self.results["yaml_format"].add_fail(
                str(self.input_file), f"YAML syntax error: {e}"
            )
            return False
        except Exception as e:
            self.results["yaml_format"] = ValidationResult("YAML Format Validation")
            self.results["yaml_format"].add_fail(
                str(self.input_file), f"Failed to read file: {e}"
            )
            return False

    def _validate_yaml_format(self) -> ValidationResult:
        """Validate YAML syntax and basic structure."""
        result = ValidationResult("YAML Format Validation")

        if self.yaml_content is None:
            result.add_fail(str(self.input_file), "YAML content is empty or invalid")
            return result

        if not isinstance(self.yaml_content, dict):
            result.add_fail(str(self.input_file), "YAML root must be a dictionary")
            return result

        result.add_pass(str(self.input_file), "YAML syntax is valid")
        return result

    # Fields that must not contain unresolved variable references
    NO_VAR_FIELDS = {"package.id", "package.name", "package.description"}

    # Fields that MUST contain unresolved variable references (will be substituted
    # by pak_linyaps.sh at build time via envsubst).
    # If these fields have concrete values (e.g., version: "1.0"), the LLM has
    # wrongly replaced the variable placeholder. This will cause build failure
    # because envsubst will not find the variable to substitute.
    MUST_BE_VAR_FIELDS = {"version", "package.version"}

    def _contains_unresolved_vars(self, value: str) -> bool:
        """Check if a string contains unresolved envsubst variable references.

        Detects patterns like ${var}, $var, ${var}_suffix.

        Args:
            value: The string to check.

        Returns:
            True if unresolved variable references are found.
        """
        var_patterns = [
            r"\$\{[a-zA-Z_][a-zA-Z0-9_]*\}",  # ${var}
            r"\$[a-zA-Z_][a-zA-Z0-9_]*",       # $var
        ]
        return any(re.search(p, value) for p in var_patterns)

    def _validate_required_fields(self) -> ValidationResult:
        """Validate all required fields exist and contain concrete values."""
        result = ValidationResult("Required Fields Validation")

        if self.yaml_content is None:
            result.add_fail("yaml_content", "No YAML content to validate")
            return result

        for field_path, category in self.REQUIRED_FIELDS:
            value = self._get_nested_field(field_path)
            if value is None:
                result.add_fail(field_path, f"Required field '{field_path}' is missing")
            elif isinstance(value, str) and value.strip() == "":
                result.add_fail(field_path, f"Required field '{field_path}' is empty")
            elif (
                field_path in self.NO_VAR_FIELDS
                and isinstance(value, str)
                and self._contains_unresolved_vars(value)
            ):
                result.add_fail(
                    field_path,
                    f"Required field '{field_path}' contains unresolved variable reference: "
                    f"'{value.strip()}'. This is likely caused by envsubst not replacing "
                    f"the variable. Suggested fix: replace the variable placeholder with "
                    f"the actual value (e.g., use concrete id/name/description instead of "
                    f"${'{'}var{'}'}).",
                )
            elif (
                field_path in self.MUST_BE_VAR_FIELDS
                and isinstance(value, str)
                and not self._contains_unresolved_vars(value)
                and not (isinstance(value, str) and value.strip() == "")
            ):
                result.add_fail(
                    field_path,
                    f"Required field '{field_path}' has been hardcoded to a concrete value: "
                    f"'{value.strip()}'. It must remain as a variable reference (e.g., "
                    f"${{ll_version}}) because pak_linyaps.sh will substitute it at "
                    f"build time via envsubst. If the LLM replaced the variable placeholder, "
                    f"please restore it to ${{ll_version}}.",
                )
            else:
                result.add_pass(field_path, f"Field '{field_path}' exists")

        # Validate package.kind value
        kind = self._get_nested_field("package.kind")
        if kind and kind not in self.VALID_KINDS:
            result.add_warning(
                "package.kind",
                f"Non-standard kind value: {kind} (expected one of {self.VALID_KINDS})",
            )

        return result

    def _validate_base_runtime(self) -> ValidationResult:
        """Validate base and runtime field format and values.

        Checks:
        1. Field exists and is not empty
        2. Format is id/version (e.g., org.deepin.base/25.2.2)
        3. ID part follows reverse domain format (org.xxx.xxx)
        4. Version part follows X.Y.Z or X.Y.Z.W format
        5. No unresolved variable references (e.g., ${base_id})
        """
        result = ValidationResult("Base/Runtime Validation")

        if self.yaml_content is None:
            result.add_fail("yaml_content", "No YAML content to validate")
            return result

        # Validate base field
        base_value = self.yaml_content.get("base")
        self._validate_id_version_field(
            "base", base_value, result,
            default_id="org.deepin.base",
            default_version="25.2.2",
        )

        # Validate runtime field
        runtime_value = self.yaml_content.get("runtime")
        self._validate_id_version_field(
            "runtime", runtime_value, result,
            default_id="org.deepin.runtime.dtk",
            default_version="25.2.2",
        )

        return result

    def _validate_id_version_field(
        self,
        field_name: str,
        field_value: Any,
        result: ValidationResult,
        default_id: str = "org.deepin.base",
        default_version: str = "25.2.2",
    ):
        """Validate a field that should be in id/version format.

        Args:
            field_name: Name of the field (e.g., 'base', 'runtime')
            field_value: The actual value from YAML
            result: ValidationResult to add findings to
            default_id: Default ID for fix suggestions
            default_version: Default version for fix suggestions
        """
        # Check 1: Field exists
        if field_value is None:
            result.add_fail(
                field_name,
                f"Required field '{field_name}' is missing. "
                f"Suggested fix: {field_name}: {default_id}/{default_version}",
            )
            return

        # Check 2: Field is not empty
        if isinstance(field_value, str) and field_value.strip() == "":
            result.add_fail(
                field_name,
                f"Required field '{field_name}' is empty. "
                f"Suggested fix: {field_name}: {default_id}/{default_version}",
            )
            return

        field_str = str(field_value).strip()

        # Check 3: No unresolved variable references
        if self._contains_unresolved_vars(field_str):
            result.add_fail(
                field_name,
                f"Field '{field_name}' contains unresolved variable reference: '{field_str}'. "
                f"This is likely caused by envsubst not replacing the variable (empty value). "
                f"Suggested fix: ensure the variable is set before envsubst, "
                f"or use actual value like '{default_id}/{default_version}'",
            )
            return

        # Check 4: Format is id/version
        if "/" not in field_str:
            result.add_fail(
                field_name,
                f"Field '{field_name}' is missing '/' separator: '{field_str}'. "
                f"Expected format: id/version (e.g., {default_id}/{default_version})",
            )
            return

        parts = field_str.split("/", 1)
        field_id = parts[0]
        field_version = parts[1] if len(parts) > 1 else ""

        # Check 5: ID format (reverse domain format: org.xxx.xxx)
        id_pattern = r"^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$"
        if not re.match(id_pattern, field_id):
            result.add_warning(
                f"{field_name}.id",
                f"ID part '{field_id}' does not follow reverse domain format "
                f"(expected: org.xxx.xxx). "
                f"Common values: org.deepin.base, org.deepin.runtime.dtk",
            )

        # Check 6: Version format (X.Y.Z or X.Y.Z.W)
        version_pattern = r"^(\d+)\.(\d+)\.(\d+)(\.\d+)?$"
        if not re.match(version_pattern, field_version):
            result.add_fail(
                f"{field_name}.version",
                f"Version part '{field_version}' has invalid format. "
                f"Expected: X.Y.Z or X.Y.Z.W (e.g., 25.2.2 or 23.1.0.1)",
            )
        else:
            result.add_pass(
                f"{field_name}",
                f"Field '{field_name}' format is valid: {field_id}/{field_version}",
            )

    def _validate_command(self) -> ValidationResult:
        """Validate command field consistency with desktop Exec value."""
        result = ValidationResult("Command Validation")

        if self.yaml_content is None:
            result.add_fail("yaml_content", "No YAML content to validate")
            return result

        if not self.exec_name:
            result.add_warning(
                "command", "No --exec-name provided, skipping command validation"
            )
            return result

        # Get command from YAML
        yaml_command = self.yaml_content.get("command")
        if yaml_command is None:
            result.add_fail("command", "Command field is missing")
            return result

        # Normalize YAML command (list or string)
        if isinstance(yaml_command, list):
            yaml_cmd_parts = [str(p) for p in yaml_command]
        elif isinstance(yaml_command, str):
            yaml_cmd_parts = yaml_command.split()
        else:
            result.add_fail(
                "command", f"Command field has invalid type: {type(yaml_command)}"
            )
            return result

        # Normalize exec_name (remove %U, %F, etc.)
        exec_cleaned = re.sub(r"%[A-Za-z]+", "", self.exec_name).strip()
        exec_parts = exec_cleaned.split()

        # Compare commands
        if yaml_cmd_parts == exec_parts:
            result.add_pass(
                "command",
                f"Command matches Exec: {' '.join(yaml_cmd_parts)}",
            )
        else:
            # Check if they match ignoring order
            if set(yaml_cmd_parts) == set(exec_parts):
                result.add_warning(
                    "command",
                    f"Command parts match but order differs:\n"
                    f"  YAML command: {' '.join(yaml_cmd_parts)}\n"
                    f"  Exec value:   {' '.join(exec_parts)}",
                )
            else:
                result.add_fail(
                    "command",
                    f"Command mismatch:\n"
                    f"  YAML command: {' '.join(yaml_cmd_parts)}\n"
                    f"  Exec value:   {' '.join(exec_parts)}",
                )

        return result

    def _validate_version(self) -> ValidationResult:
        """Validate version number format and check if greater than last_ver.

        Version format must be: X.Y.Z.W (four numeric parts separated by dots)
        Example: 1.2.3.4
        """
        result = ValidationResult("Version Validation")

        if self.yaml_content is None:
            result.add_fail("yaml_content", "No YAML content to validate")
            return result

        if not self.last_ver:
            result.add_warning(
                "version", "No --last-ver provided, skipping version comparison"
            )
            return result

        # Get version fields
        top_version = self.yaml_content.get("version")
        package_version = self._get_nested_field("package.version")

        def validate_version_format(ver_str: str) -> Tuple[bool, Optional[str]]:
            """Validate version string format is X.Y.Z.W (four numeric parts).

            Returns:
                (is_valid, error_message)
            """
            if not ver_str:
                return False, "Version is empty"

            ver_str = str(ver_str).strip()

            # Must match pattern: number.number.number.number
            pattern = r"^(\d+)\.(\d+)\.(\d+)\.(\d+)$"
            match = re.match(pattern, ver_str)

            if not match:
                return (
                    False,
                    f"Invalid format: '{ver_str}' (must be X.Y.Z.W, e.g., 1.2.3.4)",
                )

            return True, None

        def parse_version(ver_str: str) -> Optional[Tuple[int, int, int, int]]:
            """Parse version string into 4-tuple of integers.

            Only accepts format: X.Y.Z.W (four numeric parts)
            Returns None if version cannot be parsed.
            """
            if not ver_str:
                return None

            ver_str = str(ver_str).strip()
            pattern = r"^(\d+)\.(\d+)\.(\d+)\.(\d+)$"
            match = re.match(pattern, ver_str)

            if not match:
                return None

            try:
                return tuple(int(match.group(i)) for i in range(1, 5))
            except (ValueError, IndexError):
                return None

        def compare_versions(
            v1: Tuple[int, int, int, int], v2: Tuple[int, int, int, int]
        ) -> int:
            """Compare two 4-tuple versions.

            Returns:
                1 if v1 > v2
                0 if v1 == v2
                -1 if v1 < v2
            """
            if v1 > v2:
                return 1
            elif v1 < v2:
                return -1
            return 0

        # Step 1: Validate all version formats first
        format_errors = []

        # Validate --last-ver format
        last_ver_valid, last_ver_error = validate_version_format(self.last_ver)
        if not last_ver_valid:
            result.add_fail(
                "--last-ver",
                f"Invalid --last-ver format: {last_ver_error}",
            )
            format_errors.append("--last-ver")

        # Validate top-level version format
        if top_version:
            is_valid, error_msg = validate_version_format(str(top_version))
            if not is_valid:
                result.add_fail("version", error_msg)
                format_errors.append("version")

        # Validate package.version format
        if package_version:
            is_valid, error_msg = validate_version_format(str(package_version))
            if not is_valid:
                result.add_fail("package.version", error_msg)
                format_errors.append("package.version")

        # If any format errors, skip version comparison
        if format_errors:
            return result

        # Step 2: All formats valid, now compare versions
        last_ver_tuple = parse_version(self.last_ver)

        # Compare top-level version
        if top_version:
            top_tuple = parse_version(str(top_version))
            cmp_result = compare_versions(top_tuple, last_ver_tuple)
            if cmp_result > 0:
                result.add_pass(
                    "version",
                    f"Top-level version {top_version} > {self.last_ver}",
                )
            elif cmp_result == 0:
                result.add_fail(
                    "version",
                    f"Top-level version {top_version} equals {self.last_ver} (must be greater)",
                )
            else:
                result.add_fail(
                    "version",
                    f"Top-level version {top_version} < {self.last_ver} (must be greater)",
                )

        # Compare package.version
        if package_version:
            pkg_tuple = parse_version(str(package_version))
            cmp_result = compare_versions(pkg_tuple, last_ver_tuple)
            if cmp_result > 0:
                result.add_pass(
                    "package.version",
                    f"Package version {package_version} > {self.last_ver}",
                )
            elif cmp_result == 0:
                result.add_fail(
                    "package.version",
                    f"Package version {package_version} equals {self.last_ver} (must be greater)",
                )
            else:
                result.add_fail(
                    "package.version",
                    f"Package version {package_version} < {self.last_ver} (must be greater)",
                )

        return result

    def _validate_indentation(self) -> ValidationResult:
        """Validate description and build field indentation."""
        result = ValidationResult("Indentation Validation")

        if not self.raw_content:
            result.add_warning("indentation", "No raw content to validate indentation")
            return result

        lines = self.raw_content.split("\n")

        # Find and validate description block
        self._validate_multiline_field(lines, "description", 4, result)

        # Find and validate build block
        self._validate_multiline_field(lines, "build", 2, result)

        return result

    def _validate_multiline_field(
        self,
        lines: List[str],
        field_name: str,
        expected_indent: int,
        result: ValidationResult,
    ):
        """Validate a multiline field's indentation."""
        in_field = False
        field_start_line = 0
        field_indent = 0
        content_lines = []

        for i, line in enumerate(lines):
            # Check for field start
            if line.strip().startswith(f"{field_name}:"):
                in_field = True
                field_start_line = i
                # Check if it's inline or multiline
                if "|" in line:
                    # Multiline format
                    field_indent = len(line) - len(line.lstrip())
                continue

            if in_field:
                # Check if we've exited the field
                stripped = line.strip()
                if not stripped:
                    content_lines.append((i + 1, line))
                    continue

                current_indent = len(line) - len(line.lstrip())

                # If indent is less than or equal to field indent, we've exited
                if current_indent <= field_indent and not line.startswith(
                    " " * (field_indent + 2)
                ):
                    break

                content_lines.append((i + 1, line))

        if not content_lines:
            result.add_warning(field_name, f"No content found for {field_name} field")
            return

        # Validate indentation of content lines
        max_line_length = 35 if field_name == "description" else None
        has_errors = False

        for line_num, line in content_lines:
            if not line.strip():
                continue

            # Check indentation
            current_indent = len(line) - len(line.lstrip())
            if current_indent < expected_indent:
                result.add_fail(
                    f"{field_name}:{line_num}",
                    f"Insufficient indentation: expected at least {expected_indent} spaces, got {current_indent}",
                )
                has_errors = True

            # Check line length for description
            if max_line_length and len(line.strip()) > max_line_length:
                result.add_warning(
                    f"{field_name}:{line_num}",
                    f"Line exceeds {max_line_length} characters: {len(line.strip())} chars",
                )

        if not has_errors:
            result.add_pass(
                field_name,
                f"{field_name} field indentation is correct ({expected_indent} spaces)",
            )

    def _get_nested_field(self, field_path: str) -> Any:
        """Get a nested field value using dot notation."""
        if self.yaml_content is None:
            return None

        parts = field_path.split(".")
        value = self.yaml_content

        for part in parts:
            if isinstance(value, dict):
                value = value.get(part)
            else:
                return None

        return value


def main():
    parser = argparse.ArgumentParser(
        description="Validate linglong.yaml format compliance"
    )
    parser.add_argument(
        "--input",
        "-i",
        required=True,
        help="Input linglong.yaml file path",
    )
    parser.add_argument(
        "--exec-name",
        required=True,
        help="Desktop file Exec field value for command validation",
    )
    parser.add_argument(
        "--last-ver",
        help="Last version number for version increment validation (optional)",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results in JSON format",
    )
    parser.add_argument(
        "--output",
        "-o",
        help="Output file path for JSON report",
    )

    args = parser.parse_args()

    validator = LinglongYamlValidator(
        input_file=args.input,
        exec_name=args.exec_name,
        last_ver=args.last_ver,
    )
    results = validator.validate_all()

    if args.json or args.output:
        json_output = json.dumps(results, indent=2, ensure_ascii=False)

        if args.output:
            output_path = Path(args.output)
            output_path.write_text(json_output, encoding="utf-8")
            print(f"Report saved to: {output_path}")
        else:
            print(json_output)
    else:
        # Human-readable output
        print(f"\n{'='*60}")
        print(f"linglong.yaml Validation Report")
        print(f"{'='*60}")

        # Handle error cases
        if "error" in results:
            print(f"Error: {results['error']}")
            print(f"Overall Status: ✗ FAILED")
            print(f"\n{'='*60}")
            sys.exit(1)

        print(f"Input: {results.get('input_file', args.input)}")
        print(f"Overall Status: {'✓ PASSED' if results['valid'] else '✗ FAILED'}")
        print()

        for check_name, check_data in results.get("checks", {}).items():
            print(f"\n--- {check_data['check_name']} ---")
            print(f"  Passed: {check_data['passed_count']}")
            print(f"  Failed: {check_data['failed_count']}")
            print(f"  Warnings: {check_data['warning_count']}")

            if check_data["failed"]:
                print("\n  Failures:")
                for item in check_data["failed"]:
                    print(f"    ✗ {item['item']}: {item['message']}")

            if check_data["warnings"]:
                print("\n  Warnings:")
                for item in check_data["warnings"]:
                    print(f"    ⚠ {item['item']}: {item['message']}")

        print(f"\n{'='*60}")

    # Exit with appropriate code
    sys.exit(0 if results["valid"] else 1)


if __name__ == "__main__":
    main()
