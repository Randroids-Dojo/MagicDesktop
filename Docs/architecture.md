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
│   └── SettingsView.swift           # Tabbed settings window for configurations + build/install
└── Extensions/
    └── KeyboardShortcuts+Names.swift# Shortcut slot definitions (Ctrl+Opt+1–9)
```

## Key Components

### AppDelegate
Creates the shared `ConfigurationStore` and `SpaceManager`, then hands them to `MenuBarController` and `HotkeyService`.

### MenuBarController
Owns the `NSStatusItem`. Rebuilds the menu dynamically via `NSMenuDelegate`. Opens a shared settings window and selects either the Configurations or Build tab depending on which menu item was used.

### ConfigurationStore
`@Observable` class backed by a JSON file in Application Support. Mutations go through `add`/`update`/`remove` methods that trigger a debounced (500ms) save.

### SpaceManager
Activates a configuration by launching or resolving apps concurrently via `TaskGroup`, then applies the final move/raise pass in saved layout order so stacking is deterministic.

### ConfigurationEditorView
Edits the saved `appLayouts` array directly. Capture replaces the array from the current running apps, and drag-and-drop reordering updates that saved order so users can control final window stacking.

### WindowManager
Stateless `enum` with static methods. Uses the macOS Accessibility API to find a target window, convert display-relative coordinates, and retry move/raise operations until the configured frame sticks.

## Dependencies

| Package | Purpose |
|---------|---------|
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | Global hotkey registration and persistence |
