# Blazium Crash Reporter

Official sidecar UI for [Blazium Engine](https://github.com/blazium-games/blazium) crash reports. Used by first-party Blazium utilities such as the engine, hub, and other internal tools.

## Community

- Official website: [https://blazium.app/](https://blazium.app/)
- IndieDB blog: [https://www.indiedb.com/engines/blazium-engine](https://www.indiedb.com/engines/blazium-engine)
- Official community: [Blazium Discord](https://discord.gg/sZaf9KYzDp)
- Docs: [docs.blazium.app](https://docs.blazium.app)

## Ecosystem

| Product | Role | Release |
|---------|------|---------|
| [CLI](https://github.com/blazium-games/blazium-cli) | Install editors, projects, remote control, Steam/itch deploy | Linux and Windows, x86_64 and x86_32. Catalog: [cli.json](https://cdn.blazium.app/cli/cli.json) |
| [Hub](https://github.com/blazium-games/blazium-hub) | Desktop companion; installers bundle the CLI | Linux and Windows, x86_64 and x86_32. Engine builds track `blazium_4.8` |
| [Crash reporter](https://github.com/blazium-games/blazium_crash_reporter) | Sidecar UI for engine and Hub crash reports | Linux and Windows, x86_64 and x86_32. Catalog: [crash_reporter.json](https://cdn.blazium.app/crash_reporter/crash_reporter.json). Engine builds track `blazium_4.8` |
| [Toolchain](https://github.com/blazium-games/blazium-toolchain) | PS1, PS2, N64, and Interactive DVD | Linux and Windows, x86_64 and x86_32. Catalog: [toolchain.json](https://cdn.blazium.app/toolchain/toolchain.json) |
| [Skills](https://github.com/blazium-games/blazium-skills) | Agent skill packs for Claude, Cursor, Codex, and Grok | Own semver, separate from the 0.6.x API baseline. Catalog: [skills.json](https://cdn.blazium.app/skills/skills.json) |
| [Subagents](https://github.com/blazium-games/blazium-subagents) | Studio roster that loads those skills | Own semver. Catalog: [subagents.json](https://cdn.blazium.app/subagents/subagents.json) |

Published binaries are Linux and Windows, x86_64 and x86_32. CI compiles the export editor and templates from `blazium-games/blazium` branch `blazium_4.8`. CDN upload runs only after every required build exists. Catalog: [crash_reporter.json](https://cdn.blazium.app/crash_reporter/crash_reporter.json).

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
