# BarDisplay

A lightweight macOS menu bar app for managing displays, inspired by BetterDisplay.

## Features

- **Display list:** every connected display, with built-in and main display indicators. The list refreshes automatically when displays change.
- **Resolution switching:** a resolution picker per display that lists every resolution macOS offers. Resolutions that render at 2× pixel density are listed separately and labelled **HiDPI**.
- **Disconnect toggle:** soft-disconnects and reconnects a display without unplugging it. Turning off the last active display is blocked.
- **Launch at login:** a switch that registers the app as a login item.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (Swift 5.9+)

## Build & run

```bash
./build.sh && open BarDisplay.app
```

`build.sh` compiles a release build, wraps it into `BarDisplay.app`, generates the app icon from `Resources/icon.png`, ad-hoc signs the bundle, and installs it to `~/Applications` (quitting any running copy first).

For launch at login, install the app to a fixed location first:

```bash
cp -R BarDisplay.app /Applications/ && open /Applications/BarDisplay.app
```

## Project layout

| Path | Purpose |
| --- | --- |
| `Sources/BarDisplay/BarDisplayApp.swift` | App entry point and menu bar item (no Dock icon) |
| `Sources/BarDisplay/MenuView.swift` | Menu UI: display rows, resolution picker, toggles |
| `Sources/BarDisplay/DisplayManager.swift` | Lists displays and modes, switches resolution, tracks disconnected displays |
| `Sources/BarDisplay/SkyLight.swift` | Bridge to Apple's private SkyLight API: disconnects/reconnects displays and reads/applies the full display mode table |
| `Sources/BarDisplay/Info.plist` | Bundle metadata |
| `Resources/icon.png` | Source image for the app icon |
| `build.sh` | Build, bundle, icon, and sign script |

## How it works

- **Modes:** the app asks macOS for every display mode, including the duplicate low-resolution modes it normally hides. A mode counts as HiDPI when its pixel width is larger than its point width. The public API hides some HiDPI modes a monitor still supports, such as 1920 × 1080 HiDPI on a 1080p panel, so the app also reads SkyLight's private mode table (`CGSGetNumberOfDisplayModes` / `CGSGetDisplayModeDescriptionOfLength`, the same source displayplacer uses) and adds hidden HiDPI modes no larger than the panel's native size. Those are applied with `CGSConfigureDisplayMode`. Changes are applied permanently (`kCGConfigurePermanently`), so they stay after the app quits and after a restart.
- **Disconnect:** uses `CGSConfigureDisplayEnabled`, which is loaded at runtime from the private SkyLight framework. A disabled display disappears from the system's display list, so the app keeps disabled displays in `UserDefaults` to be able to reconnect them.
- **Launch at login:** uses `SMAppService.mainApp`.

## Caveats

- The disconnect feature depends on a private Apple API that may change in a future macOS release. If the API is unavailable, the toggle is greyed out. Hidden HiDPI modes rely on the same private framework; if it is missing, only the public modes are listed.
- The app is ad-hoc signed. Distributing it to other people needs a Developer ID signature and notarization.
