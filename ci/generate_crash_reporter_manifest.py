#!/usr/bin/env python3
"""Merge crash_reporter.json the same way Hub and blazium-cli already consume it."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


CDN_BASE = "https://cdn.blazium.app/crash_reporter"


def version_key(ver: str) -> tuple[int, ...]:
    parts: list[int] = []
    for p in str(ver).split("."):
        try:
            parts.append(int(p))
        except ValueError:
            parts.append(-1)
    return tuple(parts)


def pick_latest(versions: dict[str, Any]) -> str:
    if not versions:
        return ""
    return sorted(versions.keys(), key=version_key)[-1]


def file_sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def load_base(path: Path | None) -> dict[str, Any]:
    if path is None or not path.is_file():
        return {"latest": "", "released_on": "", "versions": {}}
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        return {"latest": "", "released_on": "", "versions": {}}
    versions = data.get("versions") or {}
    if not isinstance(versions, dict):
        versions = {}
    return {
        "latest": str(data.get("latest") or ""),
        "released_on": str(data.get("released_on") or ""),
        "versions": versions,
    }


def add_download(
    downloads: list[dict[str, Any]],
    platform: str,
    arch: str,
    path: Path,
    version: str,
    signing: str,
    sig_url: str,
) -> None:
    if not path.is_file():
        return
    filename = path.name
    entry = {
        "platform": platform,
        "arch": arch,
        "filename": filename,
        "download_url": f"{CDN_BASE}/{platform}/{arch}/{version}/{filename}",
        "sig_url": sig_url,
        "sha256": file_sha256(path),
        "size": path.stat().st_size,
        "signing": signing,
    }
    key = (platform, arch)
    kept = [d for d in downloads if (d.get("platform"), d.get("arch")) != key]
    kept.append(entry)
    downloads[:] = kept


def merge_version(doc: dict[str, Any], version: str, released_on: str, artifacts: Path) -> None:
    versions: dict[str, Any] = doc.setdefault("versions", {})
    entry = versions.get(version) or {"released_on": released_on, "downloads": []}
    if not entry.get("released_on"):
        entry["released_on"] = released_on
    downloads = list(entry.get("downloads") or [])
    cells = [
        ("linux", "x86_64", artifacts / "linux" / "x86_64" / "crash_reporter", "gpg"),
        ("linux", "x86_32", artifacts / "linux" / "x86_32" / "crash_reporter", "gpg"),
        ("windows", "x86_64", artifacts / "windows" / "x86_64" / "crash_reporter.exe", "sslcom"),
        ("windows", "x86_32", artifacts / "windows" / "x86_32" / "crash_reporter.exe", "sslcom"),
    ]
    for platform, arch, path, signing in cells:
        sig = ""
        if platform != "windows":
            sig_path = path.with_suffix(path.suffix + ".sig") if path.suffix else Path(str(path) + ".sig")
            if not sig_path.is_file():
                sig_path = Path(str(path) + ".sig")
            if sig_path.is_file():
                sig = f"{CDN_BASE}/{platform}/{arch}/{version}/{sig_path.name}"
        add_download(downloads, platform, arch, path, version, signing, sig)
    entry["downloads"] = downloads
    versions[version] = entry
    latest = pick_latest(versions)
    doc["latest"] = latest
    if latest:
        doc["released_on"] = versions[latest].get("released_on") or released_on


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--released-on", default="")
    parser.add_argument("--artifacts", default="artifacts")
    parser.add_argument("--base-manifest", default="")
    parser.add_argument("--out", default="crash_reporter.json")
    args = parser.parse_args()
    released = args.released_on.strip()
    if not released:
        from datetime import datetime, timezone

        released = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    base = Path(args.base_manifest) if args.base_manifest else None
    doc = load_base(base)
    merge_version(doc, args.version.strip(), released, Path(args.artifacts))
    if not doc["versions"].get(args.version.strip(), {}).get("downloads"):
        raise SystemExit("no crash_reporter artifacts found")
    out = Path(args.out)
    out.write_text(json.dumps(doc, indent=2) + "\n", encoding="utf-8")
    print(f"wrote {out} latest={doc['latest']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
