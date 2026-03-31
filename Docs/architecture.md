# Architecture

MagicDesktop is a SwiftUI menu bar app with no dock icon (`LSUIElement`). It uses the Observation framework (`@Observable`) for reactive state.

## Project Layout

```
Sources/
├── App/
│   ├── MagicDesktopApp.swift        # @main entry point
│   ├── AppDelegate.swift            # Wires services on launch
│   └── MenuBarController.swift      # NSStatusItem, NSMenu, window management
├── Models/
│   └── SpaceConfiguration.swift     # SpaceConfiguration, AppLayout, WindowFrame
├── Services/
│   ├── ConfigurationStore.swift     # JSON persistence with debounced saves
│   ├── SpaceManager.swift           # Launches and positions apps concurrently
│   ├── WindowManager.swift          # macOS Accessibility API (AXUIElement)
│   ├── HotkeyService.swift          # Global shortcut handlers
│   └── BuildInstallService.swift    # Dev-only build & reinstall to /Applications
├── UI/
│   ├── ConfigurationListView.swift  # NavigationSplitView sidebar + detail
│   ├── ConfigurationEditorView.swift# Form editor, capture current layout
│   └── SettingsView.swift           # Build & install controls
└── Extensions/
    └── KeyboardShortcuts+Names.swift# Shortcut slot definitions (Ctrl+Opt+1–9)
```

## Key Components

### AppDelegate
Creates the shared `ConfigurationStore` and `SpaceManager`, then hands them to `MenuBarController` and `HotkeyService`.

### MenuBarController
Owns the `NSStatusItem`. Rebuilds the menu dynamically via `NSMenuDelegate`. Manages the configuration editor and settings windows, observing close notifications to release references.

### ConfigurationStore
`@Observable` class backed by a JSON file in Application Support. Mutations go through `add`/`update`/`remove` methods that trigger a debounced (500ms) save.

### SpaceManager
Activates a configuration by launching all apps concurrently via `TaskGroup`. For newly launched apps, it polls the Accessibility API at 100ms intervals (up to 5s) until a window appears before positioning.

### WindowManager
Stateless `enum` with static methods. Uses `kAXMainWindowAttribute` for single-element AX queries (avoids fetching the full window list). Provides both `positionWindow` and `captureCurrentFrame`.

## Dependencies

| Package | Purpose |
|---------|---------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey registration and persistence |
