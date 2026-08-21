#!/usr/bin/env python3
"""Stamp the sidecar semver into project.blazium and export_presets.cfg."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def four_part(semver: str) -> str:
    parts = [p for p in re.split(r"[^\d]+", semver.strip()) if p != ""]
    nums = [(int(p) if p.isdigit() else 0) for p in parts[:3]]
    while len(nums) < 3:
        nums.append(0)
    return f"{nums[0]}.{nums[1]}.{nums[2]}.0"


def stamp_project(path: Path, version: str) -> None:
    text = path.read_text(encoding="utf-8")
    new, n = re.subn(
        r'(?m)^config/version="[^"]*"$',
        f'config/version="{version}"',
        text,
        count=1,
    )
    if n != 1:
        raise SystemExit(f"{path}: config/version not found or ambiguous ({n})")
    path.write_text(new, encoding="utf-8")


def stamp_presets(path: Path, version: str) -> None:
    text = path.read_text(encoding="utf-8")
    file_ver = four_part(version)
    text, n_file = re.subn(
        r'(?m)^application/file_version="[^"]*"$',
        f'application/file_version="{file_ver}"',
        text,
    )
    text, n_prod = re.subn(
        r'(?m)^application/product_version="[^"]*"$',
        f'application/product_version="{file_ver}"',
        text,
    )
    if n_file == 0 and n_prod == 0:
        raise SystemExit(f"{path}: no application version keys to stamp")
    path.write_text(text, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("--project", default="project.blazium")
    parser.add_argument("--presets", default="export_presets.cfg")
    args = parser.parse_args()
    version = args.version.strip()
    if not version:
        raise SystemExit("version is required")
    stamp_project(Path(args.project), version)
    stamp_presets(Path(args.presets), version)
    print(f"stamped version {version}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
