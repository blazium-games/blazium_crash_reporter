#!/usr/bin/env python3
"""Download the official Blazium linux editor and one export template."""

from __future__ import annotations

import argparse
import json
import shutil
import urllib.request
import zipfile
from pathlib import Path
from typing import Any

LATEST_URL = "https://cdn.blazium.app/catalog/versions/release/latest.json"


def load_json(url: str) -> Any:
    req = urllib.request.Request(url, headers={"Cache-Control": "no-cache"})
    with urllib.request.urlopen(req, timeout=120) as resp:
        return json.load(resp)


def download(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    print(f"fetch {url} -> {dest}")
    with urllib.request.urlopen(url, timeout=300) as resp, dest.open("wb") as out:
        shutil.copyfileobj(resp, out)


def pick_editor_url(editors: list[dict[str, Any]]) -> str:
    for row in editors:
        name = str(row.get("filename") or "")
        if name.endswith("linux.x86_64.zip") and ".mono." not in name:
            return str(row.get("download_url") or "")
    raise SystemExit("linux x86_64 editor zip not found")


def pick_template(templates: list[dict[str, Any]], platform: str, arch: str) -> dict[str, Any]:
    for row in templates:
        if row.get("mono"):
            continue
        if str(row.get("platform") or "") != platform:
            continue
        if str(row.get("arch") or "") != arch:
            continue
        name = str(row.get("filename") or "")
        if platform == "linux" and name.startswith("linux_release.") and name.endswith(".zip"):
            return row
        if platform == "windows" and name.startswith("windows_release_") and name.endswith(".exe") and "_console" not in name:
            return row
    raise SystemExit(f"no official template for {platform}/{arch}")


def extract_linux_template(zip_path: Path, dest: Path) -> Path:
    dest.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        names = [n for n in zf.namelist() if not n.endswith("/")]
        if not names:
            raise SystemExit(f"{zip_path}: empty zip")
        # Prefer the inner binary that looks like a template, else first file.
        pick = names[0]
        for n in names:
            base = Path(n).name
            if "linux_release" in base or base.startswith("blazium") or base.startswith("godot"):
                pick = n
                break
        target = dest / Path(pick).name
        with zf.open(pick) as src, target.open("wb") as out:
            shutil.copyfileobj(src, out)
    target.chmod(target.stat().st_mode | 0o111)
    return target


def find_editor_bin(root: Path) -> Path:
    preferred = list(root.rglob("blazium*x86_64"))
    preferred = [p for p in preferred if p.is_file() and ".console" not in p.name]
    if preferred:
        bin_path = preferred[0]
        bin_path.chmod(bin_path.stat().st_mode | 0o111)
        return bin_path
    for p in root.rglob("blazium*"):
        if p.is_file() and p.stat().st_mode & 0o111:
            return p
    raise SystemExit(f"editor binary not found under {root}")


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
    parser.add_argument("--platform", required=True, choices=("linux", "windows"))
    parser.add_argument("--arch", required=True, choices=("x86_64", "x86_32"))
    parser.add_argument("--preset", required=True)
    parser.add_argument("--editor-dir", default=".ci/editor")
    parser.add_argument("--template-dir", default=".ci/template")
    parser.add_argument("--presets", default="export_presets.cfg")
    parser.add_argument("--editor-out", default=".ci/editor_bin.txt")
    parser.add_argument("--template-out", default=".ci/template_bin.txt")
    args = parser.parse_args()

    latest = load_json(LATEST_URL)
    ver = str(latest.get("version") or "")
    editors_url = str(latest.get("editors_url") or f"https://cdn.blazium.app/release/{ver}/editors.json")
    templates_url = f"https://cdn.blazium.app/release/{ver}/templates.json"
    editor_url = pick_editor_url(load_json(editors_url))
    template = pick_template(load_json(templates_url), args.platform, args.arch)

    editor_dir = Path(args.editor_dir)
    editor_zip = editor_dir / "editor.zip"
    if not editor_zip.is_file():
        download(editor_url, editor_zip)
        with zipfile.ZipFile(editor_zip) as zf:
            zf.extractall(editor_dir / "out")
    editor_bin = find_editor_bin(editor_dir / "out")

    template_dir = Path(args.template_dir)
    raw = template_dir / Path(str(template["filename"])).name
    if not raw.is_file():
        download(str(template["download_url"]), raw)
    if raw.suffix.lower() == ".zip":
        template_bin = extract_linux_template(raw, template_dir / "out")
    else:
        template_bin = raw

    patch_preset(Path(args.presets), args.preset, template_bin)
    Path(args.editor_out).write_text(str(editor_bin.resolve()), encoding="utf-8")
    Path(args.template_out).write_text(str(template_bin.resolve()), encoding="utf-8")
    print(f"editor={editor_bin}")
    print(f"template={template_bin}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
