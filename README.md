# LabCapture

**English** | [한국어](README.ko.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | [Español](README.es.md)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift) ![License: MIT](https://img.shields.io/badge/License-MIT-green) ![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

**Build in public, without breaking your flow.**

LabCapture is a tiny macOS menu bar app that automatically records your screen + webcam for ~3 seconds while you work, and turns the footage into ready-to-post content: GIFs, a high-quality daily timelapse with a circular face cam, and an AI-written build journal.

You build. It captures. At the end of the day you have a 1080p timelapse of your work session, share-ready GIFs, and a Markdown journal of what you did — all generated on your machine.

## What you get

Every capture (default: every 20 minutes, plus on every `git push`) produces files named `YYYY-MM-DD_HHmmss_*`:

- `*_screen.gif` — your screen (960px wide, timestamped)
- `*_face.gif` — your webcam
- `*_combo.gif` — screen with a **circular face cam** overlay (lime ring, picture-in-picture)
- `*_screen.mp4` / `*_face.mp4` — high-quality originals (CRF 18, 30 fps)

And once a day (one click or one API call):

- **Timelapse** — all of today's captures stitched into one 1080p/30fps MP4: your screen as the background, your face as a circle in the center, per-segment timestamps
- **Build journal** — Claude reads your capture manifest + key frames and writes `summary.md`: a one-line summary, a timeline of what you worked on, and 1–2 suggested posts for X/Twitter
- **Clipboard helper** — copy the last capture and ⌘V it straight into a post

## Privacy & safety first

This is a tool that records your screen, so it is designed to be paranoid:

- **100% local.** No accounts, no telemetry, no uploads. Files only ever exist in `~/LabCapture` on your machine. The only optional network call is the build journal, which sends data to the Claude API *only when you trigger it*.
- **Secret guard (OCR).** Right after each recording, Apple Vision OCR scans the frames. If an API key, token, password, or DB connection string is visible on screen, the **entire capture is discarded** and retried. Three consecutive discards pause capturing for hours (configurable). Patterns covered: `sk-...` keys, GitHub PATs, AWS keys, Slack/Notion tokens, JWTs, PRIVATE KEY blocks, Bearer tokens, `API_KEY=` env assignments, and more — matched loosely on purpose, because over-detection is the safe direction.
- **Pre-capture warning.** An optional notification fires a few seconds before each capture so you're never recorded by surprise.
- **Kill switches everywhere.** Toggle screen/face sources independently from the menu bar (or API), pause for an hour / for today / on a nightly schedule. Captures auto-skip while your screen is locked or asleep.
- **Nothing is ever committed.** The repo's `.gitignore` blocks all media files, and your output folder lives outside the repo.

## Requirements

- macOS 14+ (Apple Silicon)
- ffmpeg: `brew install ffmpeg`
- Xcode Command Line Tools (to build): `xcode-select --install`

## Install

```bash
git clone https://github.com/Joonsense/labcapture.git
cd labcapture
./build.sh
open dist/LabCapture.app
```

On first launch, an onboarding window walks you through the two permissions it needs:

| Permission | Where | Used for |
|---|---|---|
| Screen Recording | System Settings → Privacy & Security | screen capture (ffmpeg child process) |
| Camera | System Settings → Privacy & Security | webcam capture |

Tips:

- Grant permissions while running the built `dist/LabCapture.app` (not a terminal build) — TCC tracks them separately.
- If captures fail and the toggle *looks* enabled, the permission record is stale: `tccutil reset ScreenCapture com.deblockx.labcapture`, then re-grant. See [docs/SIGNING.md](docs/SIGNING.md) for how to create a local signing certificate so permissions **survive rebuilds** (recommended if you hack on the source).
- Without permissions, captures skip gracefully with a notification — no crashes.

## Usage

- **Automatic** — captures every 20 minutes by default (5–120 min configurable)
- **Menu bar** — capture now / pause (1 h, today) / reveal last capture / open today's folder / settings
- **Global hotkey** — `⌃⌥⌘C` by default (rebindable)
- **Quiet hours** — e.g. pause timer captures 21:00–09:00 (manual capture still works)
- Auto-skips while locked/asleep, and when free disk space drops below 500 MB

### Menu bar icon

Two shapes: **rectangle = screen source, circle = face source**. Filled = on, outlined + slash = off. The color shows overall state: 🟢 lime active · ⚪ gray paused · 🔴 red capturing · 🟠 orange last capture failed.

## Output layout

```
~/LabCapture/
  2026-06-12/
    2026-06-12_143012_screen.gif
    2026-06-12_143012_face.gif
    2026-06-12_143012_combo.gif
    2026-06-12_143012_screen.mp4     ← when "keep originals" is on (default)
    2026-06-12_143012_face.mp4
    timelapse_2026-06-12_213000.mp4  ← daily timelapse
    summary.md                       ← AI build journal
    manifest.jsonl                   ← one JSON line per capture
  labcapture.log
```

## HTTP API — built for humans *and* AI agents

The app listens on `http://127.0.0.1:48620` (loopback only, never exposed). **An LLM agent can discover the entire API from a single call to `GET /capabilities`** — it returns a machine-readable spec.

| Method | Path | Action |
|---|---|---|
| GET | `/capabilities` | machine-readable API spec |
| GET | `/status` | state (`active/paused/capturing/warning`), sources, next capture time, last error/file |
| POST | `/capture` | capture now (202; 409 if busy). `GET/POST /trigger` is an alias for git hooks |
| POST | `/source/screen/on` · `/off` | toggle screen source |
| POST | `/source/face/on` · `/off` | toggle face (webcam) source |
| POST | `/pause` · `/pause/today` · `/resume` | pause 1 h / until midnight / resume |
| POST | `/last/copy` | copy last combo.gif to the clipboard (⌘V into X) |
| POST | `/timelapse` | compile today's originals into the 1080p timelapse (202) |
| POST | `/summary` | generate today's AI build journal (202; 400 without API key) |

```bash
curl -s http://127.0.0.1:48620/status | jq .sources
curl -s -X POST http://127.0.0.1:48620/source/face/off   # screen-only captures
curl -s -X POST http://127.0.0.1:48620/capture
```

### Capture on every git push

```bash
# <your-repo>/.git/hooks/pre-push  (chmod +x)
#!/bin/sh
curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null 2>&1 || true
exit 0
```

Or as a global alias that fires right after a successful push:

```bash
git config --global alias.pushc '!git push "$@" && curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null; true'
```

## AI build journal (optional)

Set a Claude API key (never hardcoded — file or env var):

```bash
mkdir -p ~/.config/labcapture && printf '%s' 'sk-ant-...' > ~/.config/labcapture/anthropic_api_key && chmod 600 ~/.config/labcapture/anthropic_api_key
```

Then "Daily wrap-up" in the menu (or `POST /summary`) sends `manifest.jsonl` + up to 6 representative frames to Claude and writes `summary.md`: one-line summary, work timeline, and suggested X posts based on what's actually visible in your captures.

## Settings

| Setting | Default | Range |
|---|---|---|
| Capture interval | 20 min | 5–120 |
| Capture length | 3 s | 1–5 |
| Pre-capture notice / lead time | on / 3 s | 0–10 s |
| Webcam capture | on | off → screen-only |
| PiP position (combo GIF) | bottom-right | tl / tr / bl / br |
| GIF fps | 15 | 8–15 |
| Screen GIF width | 960 px | 480–1080 |
| Output folder | `~/LabCapture` | any |
| Keep original mp4s | on | off → timelapse falls back to GIFs (low quality) |
| Quiet hours | off | start/end time |
| Global hotkey | ⌃⌥⌘C | rebindable |
| Secret guard (OCR) | on | pause 1–12 h after 3 discards |

All settings persist via `UserDefaults`.

## manifest.jsonl schema (LLM pipeline input)

One JSON line per capture, `schema: 1`:

```json
{"schema":1,"ts":"2026-06-12T18:25:23+09:00","trigger":"push","duration":3,
 "sources":["screen","face"],
 "files":["2026-06-12_182523_screen.gif","2026-06-12_182523_face.gif","2026-06-12_182523_combo.gif"],
 "kinds":{"2026-06-12_182523_screen.gif":"screen","2026-06-12_182523_face.gif":"face","2026-06-12_182523_combo.gif":"combo"}}
```

`trigger`: `timer` / `manual` / `hotkey` / `push` (git integration)

## Architecture

A Swift/SwiftUI menu bar app orchestrates; recording/encoding is delegated to ffmpeg subprocesses.

```
Sources/LabCapture/
  LabCaptureApp.swift    entry (MenuBarExtra + Settings scene)
  AppModel.swift         central state: timer/pause/lock-detection/error log/onboarding
  CaptureEngine.swift    record → 3 GIFs → manifest (core pipeline)
  DailyPipeline.swift    timelapse + Claude journal + clipboard helper
  FFmpeg.swift           ffmpeg process runner + avfoundation device detection
  OCRGuard.swift         Vision OCR secret detection
  TriggerServer.swift    127.0.0.1:48620 HTTP server
  HotkeyManager.swift    Carbon global hotkey
  Permissions.swift      TCC checks / settings deep-links
  Views/                 menu / settings / onboarding UI
```

Encoding details: two-pass GIF palette (`palettegen stats_mode=diff` → `paletteuse` sierra2_4a dithering); circular face mask via `geq` alpha with a feathered edge; timelapse segments normalized to 1080p/30fps then losslessly concatenated; timestamps via `drawtext` + `textfile=` (avoids filtergraph colon-escaping).

## Troubleshooting

- **"Configuration of video device failed"** while the Screen Recording toggle looks ON → stale TCC record (the app was re-signed). Fix: `tccutil reset ScreenCapture com.deblockx.labcapture`, relaunch, re-grant. Prevent it permanently with a [local signing certificate](docs/SIGNING.md).
- **ffmpeg not found** → `brew install ffmpeg` (expected at `/opt/homebrew/bin/ffmpeg`).
- Errors are logged to `~/LabCapture/labcapture.log` (also viewable from the menu).

## Roadmap

- ffmpeg bundling (zero-dependency install)
- Notarized releases
- Multi-monitor selection (currently main display)
- Intel mac support

PRs welcome.

## License

[MIT](LICENSE) © DeblockX Labs
