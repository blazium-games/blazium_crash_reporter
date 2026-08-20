# Blazium Crash Reporter

Official sidecar UI for [Blazium Engine](https://github.com/blazium-games/blazium) crash reports. Used by first-party Blazium utilities such as the engine, hub, and other internal tools.

This project does **not** contain Breakpad. The engine writes `{crash-dir}/{id}.dmp` plus `{id}.json` metadata. This app only presents and uploads those files.

Companion ingest server: [blazium_crash_reporter_server](https://github.com/blazium-games/blazium_crash_reporter_server).

## CLI contract

The engine launches this binary with already-resolved identity:

```text
crash_reporter --crash-dir <dir> --report-id <id> --endpoint <url> --app-id <id> --build-id <id> --contact-url <url> --privacy-url <url>
```

The **engine** no longer accepts `--app-id` / `--build-id` (unknown flags). This sidecar still does. Sidecar JSON fills gaps when a flag is omitted.

## How the engine finds this binary

- **Editor:** pass `--crash-reporter <path>` when launching the editor. Relative paths are resolved next to the editor executable. Editor identity is SCons-baked (`editor_app_id`, `editor_build_id`); there is no engine CLI override.
- **Exported games:** place this binary next to the game executable. Games use `application/crash_reporter/*` in Project Settings:
  - `reporter_filename` (default `crash_reporter` / `crash_reporter.exe` on Windows)
  - `reporter_path` as a fallback (relative to the executable, or absolute)
  - optional `reporter_sha256` (lowercase hex; empty skips the check)

## Export beside a utility

1. Export this project for Windows or Linux (point the export preset at a `crash_reporter=yes` custom template if you want the same engine tree as the utility).
2. Place the binary next to the utility executable.
3. In the utility project set:
   - `application/crash_reporter/enabled = true`
   - `application/crash_reporter/upload_mode = Sidecar` or `Both`
   - `application/crash_reporter/reporter_filename` (or `reporter_path`)
   - `application/crash_reporter/endpoint` to the ingest URL

## Privacy

Nothing is uploaded until the user confirms. Do not put secrets in Project Settings.

## License

Proprietary — see [LICENSE](LICENSE). All rights reserved.
