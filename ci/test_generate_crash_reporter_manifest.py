#!/usr/bin/env python3
"""Fixture checks for crash_reporter.json generation and version stamping."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from generate_crash_reporter_manifest import merge_version, pick_latest
from patch_export_template import patch_preset
from stamp_version import four_part, stamp_project


class ManifestTests(unittest.TestCase):
    def test_pick_latest(self) -> None:
        self.assertEqual(pick_latest({"0.1.0": {}, "0.1.2": {}, "0.1.10": {}}), "0.1.10")

    def test_merge_version_writes_hub_fields(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            linux = root / "linux" / "x86_64"
            linux.mkdir(parents=True)
            bin_path = linux / "crash_reporter"
            bin_path.write_bytes(b"MZFAKE")
            (linux / "crash_reporter.sig").write_bytes(b"sig")
            doc: dict = {"latest": "", "released_on": "", "versions": {}}
            merge_version(doc, "0.2.0", "2026-01-01T00:00:00Z", root)
            downloads = doc["versions"]["0.2.0"]["downloads"]
            self.assertEqual(len(downloads), 1)
            row = downloads[0]
            self.assertEqual(row["platform"], "linux")
            self.assertEqual(row["arch"], "x86_64")
            self.assertEqual(row["filename"], "crash_reporter")
            self.assertTrue(row["download_url"].endswith("/crash_reporter/linux/x86_64/0.2.0/crash_reporter"))
            self.assertTrue(row["sig_url"].endswith("/crash_reporter.sig"))
            self.assertEqual(row["size"], 6)
            self.assertEqual(row["signing"], "gpg")
            self.assertEqual(doc["latest"], "0.2.0")


class StampTests(unittest.TestCase):
    def test_four_part(self) -> None:
        self.assertEqual(four_part("1.2.3"), "1.2.3.0")

    def test_stamp_project(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            path = Path(raw) / "project.blazium"
            path.write_text('config/name="x"\nconfig/version="1.0.0"\n', encoding="utf-8")
            stamp_project(path, "0.3.1")
            self.assertIn('config/version="0.3.1"', path.read_text(encoding="utf-8"))

    def test_app_version_autoload_is_wired(self) -> None:
        root = Path(__file__).resolve().parents[1]
        project = (root / "project.blazium").read_text(encoding="utf-8")
        script = (root / "scripts" / "app_version.gd").read_text(encoding="utf-8")
        self.assertIn('AppVersion="*res://scripts/app_version.gd"', project)
        self.assertIn("--app-version", script)
        self.assertIn("CRASH_REPORTER_VERSION=", script)


class PatchPresetTests(unittest.TestCase):
    def test_patches_named_preset_only(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            root = Path(raw)
            presets = root / "export_presets.cfg"
            presets.write_text(
                '[preset.0]\nname="Linux/X11"\n[preset.0.options]\ncustom_template/release=""\n'
                '[preset.1]\nname="Linux/X11 x86_32"\n[preset.1.options]\ncustom_template/release=""\n',
                encoding="utf-8",
            )
            tpl = root / "template_release"
            tpl.write_bytes(b"x")
            patch_preset(presets, "Linux/X11", tpl)
            text = presets.read_text(encoding="utf-8")
            self.assertIn(f'custom_template/release="{tpl.resolve().as_posix()}"', text)
            self.assertEqual(text.count('custom_template/release=""'), 1)


if __name__ == "__main__":
    unittest.main()
