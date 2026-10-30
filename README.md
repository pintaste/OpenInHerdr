# OpenInHerdr

[English](./README.md) | [中文](./README-zh.md)

A minimal macOS Finder toolbar app that opens the current directory in [Herdr](https://herdr.dev) with a single click.

> Modeled on [OpenInOtty](https://github.com/pintaste/OpenInOtty), itself inspired by [OpenInTerminal-Lite](https://github.com/Ji4n1ng/OpenInTerminal).

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-blue) ![Swift 5](https://img.shields.io/badge/Swift-5-orange) ![License MIT](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **One click** — toolbar icon opens Herdr at the current Finder path
- **Smart path**
  - Selection → use selected item (if it's a **file**, use the **parent folder**)
  - No selection → current Finder window folder
  - No usable window → Desktop
- **Smart Herdr** (through Herdr's own `herdr-app` CLI, which is the app binary itself)
  - A space for that folder is already open → new tab in it (`do tab.new --space <id> --folder <path>`), then select that space
  - Otherwise → new space at that folder (`do space.new --folder <path>`)
  - Herdr window not open → launch Herdr via Launch Services, wait for the window (up to 15 s), then do the above
- **Find Herdr by bundle id** (`dev.herdr.app`), then `~/Applications/Herdr.app`, then `/Applications/Herdr.app`
- **Error alerts** — failures show an `NSAlert` (including Herdr's error output) instead of failing silently
- **No menu bar / Dock icon** — `LSUIElement = true`; quits right after dispatch

---

## Requirements

| Requirement | Version |
|---|---|
| macOS | 12.0 Monterey or later |
| Xcode | 15+ |
| [Herdr](https://herdr.dev) | Tested with 0.1.9 (herdr-core 0.1.14) |

---

## Installation

### Build from source

```bash
cd openinherdr
xcodebuild -project OpenInHerdr.xcodeproj \
           -scheme OpenInHerdr \
           -configuration Release \
           -derivedDataPath build \
           build
cp -R build/Build/Products/Release/OpenInHerdr.app /Applications/
```

### Add to Finder toolbar

Hold **⌘ (Command)** and drag `/Applications/OpenInHerdr.app` into the Finder toolbar.

The first time you click the icon, macOS asks whether OpenInHerdr may control Finder — click **Allow**.

### Reset permissions (if you accidentally denied)

```bash
tccutil reset AppleEvents com.local.OpenInHerdr
```

---

## For AI agents / LLMs

Use this section when installing, verifying, or debugging OpenInHerdr on a user's Mac. Prefer the exact commands below; do not invent alternate bundle IDs.

### Facts

| Item | Value |
|---|---|
| Bundle ID | `com.local.OpenInHerdr` |
| App install path | `/Applications/OpenInHerdr.app` |
| Herdr bundle ID | `dev.herdr.app` |
| Herdr discovery | `NSWorkspace.urlForApplication(withBundleIdentifier: "dev.herdr.app")`, else `~/Applications/Herdr.app`, else `/Applications/Herdr.app` |
| Herdr CLI | `<Herdr.app>/Contents/MacOS/Herdr` (same binary as `herdr-app`; talks to the window over `~/.config/herdr-app/herdr-app.sock`) |
| Source of truth | `OpenInHerdr/main.swift` (single-file app) |
| UI type | `LSUIElement = true` (no Dock / menu bar icon) |

### Install (agent checklist)

```bash
mdfind "kMDItemCFBundleIdentifier == 'dev.herdr.app'" | head -1   # Herdr present?
xcodebuild -version
xcodebuild -project OpenInHerdr.xcodeproj -scheme OpenInHerdr \
           -configuration Release -derivedDataPath build build
cp -R build/Build/Products/Release/OpenInHerdr.app /Applications/
```

**Human-only step:** ⌘-drag `/Applications/OpenInHerdr.app` onto the Finder toolbar, click it once, and choose **Allow** for Automation → Finder.

### Verify

```bash
HERDR="$(mdfind "kMDItemCFBundleIdentifier == 'dev.herdr.app'" | head -1)/Contents/MacOS/Herdr"
"$HERDR" --version

# Without Finder: a path argument overrides the Finder lookup (no Automation prompt)
mkdir -p /tmp/oih-check
/Applications/OpenInHerdr.app/Contents/MacOS/OpenInHerdr /tmp/oih-check
"$HERDR" ls        # expect a space whose folder is /tmp/oih-check
```

### Runtime behavior (for debugging)

1. Path: first non-`-` CLI argument if given (file → parent dir); else ScriptingBridge `finderPath()` (selection → front window → `~/Desktop`).
2. Resolve Herdr.app (bundle id → `~/Applications` → `/Applications`) and its executable.
3. `Herdr ls` must return JSON; if not ("no Herdr window"), `open -a <Herdr.app>` and poll `ls` every 0.25 s for up to 15 s.
4. If `ls` shows a local space whose folder matches (symlinks resolved, e.g. `/tmp` = `/private/tmp`) → `do tab.new --space <id> --folder <path>` + `do space.select --id <id>`; else `do space.new --folder <path>`.
5. Activate Herdr and exit 0; on failure show `NSAlert` and exit 1.

### Do / Don't

- Do pass paths as discrete `Process` arguments; never shell-interpolate into `sh -c` or AppleScript.
- Do tell the user to ⌘-drag the app to the toolbar (agents cannot skip this).
- Don't change the bundle ID without updating `Info.plist`, entitlements and this doc.
- Don't commit `build/`, `DerivedData/` or `.DS_Store`.

---

## How It Works

```
Click toolbar icon
       │
       ▼
  path = argv[1] ?? finderPath()   (selection → window → Desktop; file → parent)
       │
       ▼
  resolve Herdr.app → Contents/MacOS/Herdr
       │
       ▼
  window up? (Herdr ls) ── no ──► open -a Herdr.app, wait ≤15 s
       │
       ▼
  space with this folder? ── yes ─► do tab.new --space <id> --folder <path>
       │                              do space.select --id <id>
       no
       ▼
  do space.new --folder <path>
       │
       ▼
  activate Herdr / NSAlert on error → exit
```

**Why `perform(NSSelectorFromString:)` instead of a ScriptingBridge protocol?** Swift's `@objc optional` protocol calls check `respondsToSelector:` first, and ScriptingBridge's private `SBScriptableApplication` returns `false` for forwarded Apple Event methods, so calls silently return `nil` and the TCC prompt never appears. `perform()` skips that check.

---

## Project Structure

```
openinherdr/
├── OpenInHerdr.xcodeproj/
├── OpenInHerdr/
│   ├── main.swift                 # All app logic
│   ├── Info.plist                 # LSUIElement=true, usage description
│   ├── OpenInHerdr.entitlements   # Apple Events entitlement, no sandbox
│   └── Assets.xcassets/           # App icon
├── scripts/
│   └── make_app_icon.py           # Rebuild icon from Herdr.app (needs Pillow)
├── README.md
└── README-zh.md
```

---

## Troubleshooting

**Nothing happens when I click the icon** — check **System Settings → Privacy & Security → Automation** (OpenInHerdr → Finder), or run `tccutil reset AppleEvents com.local.OpenInHerdr` and click again.

**Opens Desktop instead of the current folder** — you need a non-minimized Finder window or a selected item.

**"Herdr window not ready" alert** — Herdr took longer than 15 s to open its window (e.g. installing an update on launch). Click again once the window is up.

**A new space appears instead of a tab** — tabs are only added to a space whose folder is exactly this folder; otherwise a new space is created.

---

## License

MIT — see [LICENSE](LICENSE).
