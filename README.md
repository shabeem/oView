# OView — macOS Video Overlay

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2013%2B-blue" alt="macOS 13+">
  <img src="https://img.shields.io/badge/swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

Lightweight macOS menu bar utility that captures any app window (Telegram, Zoom, FaceTime, WhatsApp) and displays it as a **floating circle or rectangle overlay** — always on top of all windows.

Perfect for keeping an eye on your video call while working in other apps.

## Features

- **Window-based capture** via ScreenCaptureKit — works even when the source window is behind other apps
- **Circle or rectangle** shape with gradient border (blue → purple)
- **Drag** to reposition the overlay
- **Scroll** to zoom video in/out
- **Cmd + drag** to pan video inside the overlay
- **Right-click** for quick settings
- Adjustable width and height for rectangle mode
- Lives in the **menu bar** — no Dock icon clutter

## Requirements

- macOS 13 Ventura or later
- Screen Recording permission (prompted on first launch)

## Installation

### From Source

1. Clone the repo:
   ```bash
   git clone https://github.com/shabeem/oView.git
   cd oView
   ```

2. Open in Xcode:
   ```bash
   open OView.xcodeproj
   ```

3. Press **⌘R** to build and run.

### Download

Download the latest `.zip` from [Releases](https://github.com/shabeem/oView/releases).

**First time setup:**
1. Unzip the download
2. **Double-click `install.command`** — it will remove macOS quarantine, copy to Applications, and launch OView
3. Grant Screen Recording permission when prompted, then quit and reopen OView

**Or manually via Terminal:**
```bash
xattr -cr OView.app
tccutil reset ScreenCapture com.oview.app
open OView.app
```

> **Note:** macOS blocks unsigned apps by default. The install script handles this automatically.

## Usage

1. Launch OView → a circle icon appears in the menu bar
2. Click the icon → **"Capture Current Window"**
3. Select the window you want to capture (e.g., Telegram)
4. A floating overlay appears with live video from that window
5. Continue working — the overlay stays on top

### Controls

| Action | What it does |
|--------|-------------|
| Drag | Move the overlay |
| Scroll | Zoom video in/out |
| Cmd + Drag | Pan video inside the overlay |
| Right-click | Context menu (shape, reset, stop) |
| Option + Scroll | Resize the overlay |
| Pinch (trackpad) | Zoom video |

## How It Works

OView uses Apple's **ScreenCaptureKit** to capture a specific window (not a screen region). This means the captured content stays visible even when the source window is hidden behind other apps. The overlay is rendered as a borderless `NSWindow` at a level above the status bar.

## License

MIT
