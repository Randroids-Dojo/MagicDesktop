# MagicDesktop

A macOS menu bar utility that launches and arranges apps into predefined window layouts with a single global shortcut.

## Requirements

- macOS 14.0+
- Xcode 16+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Accessibility permissions (System Settings > Privacy & Security > Accessibility)

## Quick Start

```bash
xcodegen generate
open MagicDesktop.xcodeproj
```

Build and run from Xcode. MagicDesktop appears as an icon in the menu bar — there is no dock icon or main window.

## How It Works

1. Create a **configuration** — a named set of apps and their window positions/sizes.
2. Use **Capture Running Apps** to snapshot your current setup, including which display each window belongs to. Multi-monitor captures are grouped in display-layout order and can be rearranged afterward.
3. Arrange the saved app order to control the final stacking order. Later items are raised later, so they end up above earlier items.
4. Assign a **global shortcut** (defaults to Ctrl+Opt+1 through 9).
5. Press the shortcut from anywhere — MagicDesktop launches any missing apps, activates running ones, and moves/resizes all windows to match.

You can also click any configuration by name in the menu bar dropdown.

## Docs

| Topic | Link |
|-------|------|
| Creating and editing configurations | [Docs/configuration.md](Docs/configuration.md) |
| Global shortcuts | [Docs/shortcuts.md](Docs/shortcuts.md) |
| Architecture overview | [Docs/architecture.md](Docs/architecture.md) |
| Building and installing | [Docs/build-install.md](Docs/build-install.md) |
