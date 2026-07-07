#!/usr/bin/env python3
"""
Directory Structure Validation Script

Validates:
1. Desktop files in ${inputDir}/files/share/applications - Icon/Exec fields use relative names
2. Icons in ${inputDir}/files/share/icons/hicolor organized per XDG specifications
3. Binaries in ${inputDir}/files/bin exist and are executable
"""

import os
import sys
import json
import argparse
import re
from pathlib import Path
from typing import Dict, List, Any, Optional


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


class DirectoryStructureValidator:
    """Validates directory structure compliance."""

    # XDG standard icon sizes
    XDG_STANDARD_SIZES = [
        "16x16",
        "22x22",
        "24x24",
        "32x32",
        "36x36",
        "48x48",
        "64x64",
        "72x72",
        "96x96",
        "128x128",
        "192x192",
        "256x256",
        "512x512",
        "scalable",
    ]

    # Valid icon extensions
    VALID_ICON_EXTENSIONS = {".png", ".jpg", ".jpeg", ".svg", ".svgz"}

    # Fixed-size icon extensions (not scalable)
    FIXED_SIZE_EXTENSIONS = {".png", ".jpg", ".jpeg"}

    def __init__(self, input_dir: str):
        self.input_dir = Path(input_dir).resolve()

        # ${inputDir} should directly contain share/ and bin/
        self.applications_dir = self.input_dir / "share" / "applications"
        self.icons_dir = self.input_dir / "share" / "icons" / "hicolor"
        self.bin_dir = self.input_dir / "bin"
        self.results: Dict[str, ValidationResult] = {}

    def validate_all(self) -> Dict[str, Any]:
        """Run all validations and return results."""
        self.results = {}

        # Check if input directory exists
        if not self.input_dir.exists():
            return {
                "error": f"Input directory does not exist: {self.input_dir}",
                "valid": False,
            }

        # Run validations
        self.results["desktop_files"] = self._validate_desktop_files()
        self.results["icons"] = self._validate_icons()
        self.results["binaries"] = self._validate_binaries()

        # Calculate overall status
        all_passed = all(
            len(r.failed) == 0
            for r in self.results.values()
            if isinstance(r, ValidationResult)
        )

        return {
            "input_dir": str(self.input_dir),
            "valid": all_passed,
            "checks": {name: result.to_dict() for name, result in self.results.items()},
        }

    def _validate_desktop_files(self) -> ValidationResult:
        """Validate desktop files for Icon and Exec field compliance."""
        result = ValidationResult("Desktop Files Validation")

        if not self.applications_dir.exists():
            result.add_warning(
                str(self.applications_dir), "Applications directory does not exist"
            )
            return result

        desktop_files = list(self.applications_dir.glob("*.desktop"))

        if not desktop_files:
            result.add_warning(str(self.applications_dir), "No desktop files found")
            return result

        for desktop_file in desktop_files:
            self._validate_single_desktop(desktop_file, result)

        return result

    def _validate_single_desktop(self, desktop_file: Path, result: ValidationResult):
        """Validate a single desktop file."""
        try:
            content = desktop_file.read_text(encoding="utf-8", errors="ignore")
        except Exception as e:
            result.add_fail(str(desktop_file), f"Cannot read file: {e}")
            return

        icon_field = None
        exec_field = None

        # Parse desktop file
        for line in content.splitlines():
            line = line.strip()
            if line.startswith("Icon="):
                icon_field = line[5:].strip()
            elif line.startswith("Exec="):
                exec_field = line[5:].strip()

        file_valid = True

        # Validate Icon field
        if icon_field is None:
            result.add_warning(str(desktop_file), "No Icon field found")
        elif icon_field.startswith("/"):
            result.add_fail(
                str(desktop_file), f"Icon field uses absolute path: {icon_field}"
            )
            file_valid = False
        else:
            result.add_pass(str(desktop_file), f"Icon field valid: {icon_field}")

        # Validate Exec field
        if exec_field is None:
            result.add_warning(str(desktop_file), "No Exec field found")
        else:
            # Extract the binary name (first part before space)
            exec_binary = exec_field.split()[0] if exec_field else ""

            if exec_binary.startswith("/"):
                # Check if it's an absolute path
                result.add_fail(
                    str(desktop_file), f"Exec field uses absolute path: {exec_binary}"
                )
                file_valid = False
            else:
                result.add_pass(str(desktop_file), f"Exec field valid: {exec_binary}")

        if file_valid and icon_field and exec_field:
            result.add_pass(str(desktop_file), "Desktop file validation passed")

    def _validate_icons(self) -> ValidationResult:
        """Validate icon directory structure per XDG specifications."""
        result = ValidationResult("Icons Validation")

        if not self.icons_dir.exists():
            result.add_warning(
                str(self.icons_dir), "Icons hicolor directory does not exist"
            )
            return result

        # Check for valid size directories
        size_dirs = [d for d in self.icons_dir.iterdir() if d.is_dir()]

        if not size_dirs:
            result.add_warning(str(self.icons_dir), "No icon size directories found")
            return result

        for size_dir in size_dirs:
            size_name = size_dir.name

            # Check if size directory name is valid
            if size_name not in self.XDG_STANDARD_SIZES:
                # Check if it matches NxN pattern
                if not re.match(r"^\d+x\d+$", size_name):
                    result.add_warning(
                        str(size_dir), f"Non-standard size directory: {size_name}"
                    )

            # Check for apps subdirectory
            apps_dir = size_dir / "apps"
            if not apps_dir.exists():
                result.add_warning(
                    str(size_dir), f"Missing 'apps' subdirectory in {size_name}"
                )
                continue

            # Validate icons in apps directory
            self._validate_icon_files(apps_dir, size_name, result)

        return result

    def _validate_icon_files(
        self, apps_dir: Path, size_name: str, result: ValidationResult
    ):
        """Validate icon files in an apps directory."""
        icon_files = list(apps_dir.iterdir())

        if not icon_files:
            result.add_warning(str(apps_dir), f"No icons found in {size_name}/apps")
            return

        for icon_file in icon_files:
            if not icon_file.is_file():
                continue

            ext = icon_file.suffix.lower()

            # Check file extension
            if ext not in self.VALID_ICON_EXTENSIONS:
                result.add_fail(str(icon_file), f"Invalid icon extension: {ext}")
                continue

            # Check if scalable directory has raster formats
            if size_name == "scalable" and ext in self.FIXED_SIZE_EXTENSIONS:
                result.add_warning(
                    str(icon_file),
                    f"Raster image in scalable directory (should be SVG)",
                )

            # Check if fixed-size directory has SVG
            if size_name != "scalable" and ext in {".svg", ".svgz"}:
                result.add_warning(
                    str(icon_file), f"SVG in fixed-size directory {size_name}"
                )

            result.add_pass(str(icon_file), f"Valid icon in {size_name}/apps")

    def _validate_binaries(self) -> ValidationResult:
        """Validate binary executability."""
        result = ValidationResult("Binaries Validation")

        if not self.bin_dir.exists():
            result.add_fail(str(self.bin_dir), "Bin directory does not exist")
            return result

        # Get all binaries from desktop files
        required_binaries = self._get_required_binaries()

        if not required_binaries:
            result.add_warning(
                "desktop files", "No binaries referenced in desktop files"
            )
            return result

        for binary_name in required_binaries:
            # Search for binary in bin directory
            binary_path = self._find_binary(binary_name)

            if binary_path is None:
                result.add_fail(binary_name, f"Binary not found in {self.bin_dir}")
                continue

            # Check if executable
            if os.access(binary_path, os.X_OK):
                result.add_pass(
                    str(binary_path), f"Binary is executable: {binary_name}"
                )
            else:
                result.add_fail(
                    str(binary_path),
                    f"Binary exists but is not executable: {binary_name}",
                )

        return result

    def _get_required_binaries(self) -> set:
        """Extract binary names from desktop files."""
        binaries = set()

        if not self.applications_dir.exists():
            return binaries

        for desktop_file in self.applications_dir.glob("*.desktop"):
            try:
                content = desktop_file.read_text(encoding="utf-8", errors="ignore")
                for line in content.splitlines():
                    line = line.strip()
                    if line.startswith("Exec="):
                        exec_value = line[5:].strip()
                        # Get the binary name (first part)
                        binary = exec_value.split()[0] if exec_value else ""
                        # Remove path if present
                        binary_name = os.path.basename(binary)
                        if binary_name:
                            binaries.add(binary_name)
            except Exception:
                continue

        return binaries

    def _find_binary(self, binary_name: str) -> Optional[Path]:
        """Find a binary in the bin directory (including subdirectories)."""
        if not self.bin_dir.exists():
            return None

        # Direct match
        direct_path = self.bin_dir / binary_name
        if direct_path.exists():
            return direct_path

        # Search in subdirectories (up to 2 levels deep)
        for item in self.bin_dir.rglob(binary_name):
            if item.is_file():
                return item

        return None


def main():
    parser = argparse.ArgumentParser(
        description="Validate directory structure compliance"
    )
    parser.add_argument("input_dir", help="Input directory to validate")
    parser.add_argument(
        "--json", action="store_true", help="Output results in JSON format"
    )
    parser.add_argument("--output", "-o", help="Output file path for JSON report")

    args = parser.parse_args()

    validator = DirectoryStructureValidator(args.input_dir)
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
        print(f"Directory Structure Validation Report")
        print(f"{'='*60}")
        print(f"Input: {results['input_dir']}")
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
