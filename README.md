# Blazium Crash Reporter

Official sidecar UI for [Blazium Engine](https://github.com/blazium-games/blazium) crash reports. Used by first-party Blazium utilities such as the engine, hub, and other internal tools.

This project does **not** contain Breakpad. The engine writes `{crash-dir}/{id}.dmp` plus `{id}.json` metadata. This app only presents and uploads those files.

Companion ingest server: [blazium_crash_reporter_server](https://github.com/blazium-games/blazium_crash_reporter_server).

## CLI contract

The engine launches this binary with:

```text
crash_reporter --crash-dir <dir> --report-id <id> --endpoint <url> --app-id <id> --api-key <key> --contact-url <url> --privacy-url <url>
```

Sidecar JSON is preferred when present; CLI flags fill gaps.

## Export beside a utility

1. Export this project for Windows or Linux (point the export preset at a `crash_reporter=yes` custom template if you want the same engine tree as the utility).
2. Place the binary next to the utility executable (or in a subfolder).
3. In the utility project set:
   - `application/crash_reporter/enabled = true`
   - `application/crash_reporter/upload_mode = Sidecar` or `Both`
   - `application/crash_reporter/reporter_path` to the relative binary path
   - `application/crash_reporter/endpoint` to the ingest URL

## Privacy

Nothing is uploaded until the user confirms. Do not put secrets in Project Settings; `api_key` is a public client key.

## License

Proprietary — see [LICENSE](LICENSE). All rights reserved.
