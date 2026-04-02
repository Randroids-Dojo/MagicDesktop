# Configuration

A configuration defines a named set of apps and where their windows should be placed on screen.

## Creating a Configuration

1. Click the MagicDesktop icon in the menu bar.
2. Select **Edit Configurations...** (or press `Cmd+,`) to open the **Configurations** tab in the settings window.
3. Click the **+** button in the sidebar.
4. Give the configuration a name (e.g. "Dev Setup", "Writing").

## Adding Apps

Each configuration contains one or more **app layouts**. Each layout specifies:

| Field | Description |
|-------|-------------|
| **Bundle ID** | The app's bundle identifier (e.g. `com.apple.Safari`). |
| **App Name** | A display label for the layout row. |
| **X, Y** | The window's top-left origin in screen coordinates. |
| **W, H** | The window's width and height in points. |

Click **Add App** to add a blank layout, then fill in the bundle ID and frame values.

## Reordering Apps

The order of apps in a configuration matters.

- MagicDesktop applies the final move/raise pass in saved app order.
- Later items are raised later, so they end up above earlier items.
- In the editor, drag the handle on a row to reorder it.
- Drop on an app row to place the dragged app after that item.
- Drop on the top insertion line to place the dragged app first.

## Capturing the Current Layout

Instead of entering values manually, click **Capture Running Apps**. This snapshots every visible app's current window position and size into the configuration, replacing any existing layouts.

Capture is a convenient way to set things up once by hand and save the result.

The captured order is just the order returned by macOS for the currently running apps. If you care about final stacking order, reorder the saved app list after capture.

## Storage

Configurations are saved as JSON in:

```
~/Library/Application Support/MagicDesktop/configurations.json
```

Changes are persisted automatically with a short debounce so edits in the text fields are batched.

## Activating a Configuration

- Click its name in the menu bar dropdown, or
- Press its assigned [global shortcut](shortcuts.md).

MagicDesktop will:
1. Launch any apps that are not already running.
2. Wait for each newly launched app to create a window.
3. Move, resize, and raise the target windows to the configured positions in saved layout order.

Apps are launched concurrently, so a multi-app configuration activates quickly.
