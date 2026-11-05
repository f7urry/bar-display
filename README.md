# BarDisplay

A lightweight macOS menu bar app for managing displays, inspired by BetterDisplay.

## Features

- **Display list:** every connected display, with built-in and main display indicators. The list refreshes automatically when displays change.
- **Resolution switching:** a resolution picker per display, plus a **HiDPI** switch that renders the selected resolution at 2× pixel density. On external monitors where macOS has no HiDPI mode (for example 1920 × 1080 on a 1080p panel), the switch forces it with a virtual display.
- **Disconnect toggle:** soft-disconnects and reconnects a display without unplugging it. Turning off the last active display is blocked.
- **Launch at login:** a switch that registers the app as a login item.

## Requirements

- macOS 13 Ventura or later
- Xcode Command Line Tools (Swift 5.9+)

## Build & run

```bash
./build.sh && open BarDisplay.app
```

`build.sh` compiles a release build, wraps it into `BarDisplay.app`, generates the app icon from `Resources/icon.png`, and ad-hoc signs the bundle.

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
| `Sources/BarDisplay/SkyLight.swift` | Bridge to Apple's private SkyLight API that disconnects and reconnects displays |
| `Sources/BarDisplay/VirtualHiDPI.swift` | Forced HiDPI: creates a virtual 2× display and mirrors the monitor to it |
| `Sources/CGVirtualDisplayPrivate/` | Header for Apple's private `CGVirtualDisplay` classes |
| `Sources/BarDisplay/Info.plist` | Bundle metadata |
| `Resources/icon.png` | Source image for the app icon |
| `build.sh` | Build, bundle, icon, and sign script |

## How it works

- **Modes:** the app asks macOS for every display mode, including the duplicate low-resolution modes it normally hides. A mode counts as HiDPI when its pixel width is larger than its point width. Changes are applied permanently.
- **Disconnect:** uses `CGSConfigureDisplayEnabled`, which is loaded at runtime from the private SkyLight framework. A disabled display disappears from the system's display list, so the app keeps disabled displays in `UserDefaults` to be able to reconnect them.
- **Forced HiDPI:** creates a virtual display (private `CGVirtualDisplay` API) with each of the monitor's point sizes at 2× pixels, then mirrors the real monitor to it, so macOS renders at, say, 3840 × 2160 and scales down to the 1080p panel. Each size is also listed at 1×, because macOS only marks a 2× mode usable when its 1× twin exists. The choice is saved in `UserDefaults` and restored when the app starts or the monitor is plugged back in. The virtual display is removed when the monitor goes away, and quitting the app ends the mirror.
- **Launch at login:** uses `SMAppService.mainApp`.

## Caveats

- The disconnect feature depends on a private Apple API that may change in a future macOS release. If the API is unavailable, the toggle is greyed out. Forced HiDPI likewise depends on the private `CGVirtualDisplay` API, and rendering at 2× costs some GPU time and makes text and UI smaller unless you pick a smaller size.
- The app is ad-hoc signed. Distributing it to other people needs a Developer ID signature and notarization.
