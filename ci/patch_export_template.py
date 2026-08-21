#!/usr/bin/env python3
"""Point one named export preset at a custom template_release binary."""

from __future__ import annotations

import argparse
from pathlib import Path


def patch_preset(presets: Path, preset_name: str, template: Path) -> None:
    text = presets.read_text(encoding="utf-8")
    lines = text.splitlines()
    in_preset = False
    in_options = False
    out: list[str] = []
    patched = False
    for line in lines:
        if line.startswith("name="):
            in_preset = line.split("=", 1)[1].strip().strip('"') == preset_name
            in_options = False
        if line.startswith("[") and line.endswith(".options]"):
            in_options = in_preset
        if in_options and line.startswith("custom_template/release="):
            out.append(f'custom_template/release="{template.resolve().as_posix()}"')
            patched = True
            continue
        out.append(line)
    if not patched:
        raise SystemExit(f"{presets}: custom_template/release not found for {preset_name}")
    presets.write_text("\n".join(out) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--presets", default="export_presets.cfg")
    parser.add_argument("--preset", required=True)
    parser.add_argument("--template", required=True)
    args = parser.parse_args()
    path = Path(args.template)
    if not path.is_file():
        raise SystemExit(f"template missing: {path}")
    patch_preset(Path(args.presets), args.preset, path)
    print(f"patched {args.preset} -> {path.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
