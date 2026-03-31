# MagicDesktop

## What This Repo Is

MagicDesktop is a macOS menu bar app that launches apps and arranges their windows into saved layouts with global shortcuts. It is an `LSUIElement` app, so there is no dock icon or main app window.

## Requirements

- macOS 14+
- Xcode 16+
- XcodeGen
- Accessibility permission in System Settings > Privacy & Security > Accessibility

## Common Commands

```bash
xcodegen generate
xcodebuild -project MagicDesktop.xcodeproj -scheme MagicDesktop -configuration Debug build
open MagicDesktop.xcodeproj
```

## Important Files

- `Sources/Services/SpaceManager.swift`: configuration activation flow; launches apps, waits for windows, then positions and raises them in config order.
- `Sources/Services/WindowManager.swift`: Accessibility API window lookup, move/resize, raise, and display coordinate conversion.
- `Sources/Models/SpaceConfiguration.swift`: saved layout model; frames are display-relative when `display` is set.
- `Sources/UI/ConfigurationEditorView.swift`: capture/edit UI for saved app layouts.
- `Sources/Services/ConfigurationStore.swift`: JSON persistence at `~/Library/Application Support/MagicDesktop/configurations.json`.

## Change Guidance

- Preserve display-relative placement. Only treat frames as absolute when `layout.display == nil`.
- Be careful with Accessibility timing. Newly launched apps may not expose a usable window immediately.
- Window stacking is order-sensitive. The final position/raise pass follows `config.appLayouts` order so later items end up above earlier ones.
- Do not assume every app exposes `kAXMainWindowAttribute`; fallback window lookup is intentional.

## Verification

- There are no automated tests in this repo today.
- Always run an `xcodebuild` compile check after code changes.
- For window-management changes, manually verify on a multi-monitor setup with Accessibility permission enabled.
