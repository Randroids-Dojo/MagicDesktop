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
| **Display** | The monitor the window should be restored onto. |
| **X, Y** | The window's top-left origin relative to that display. |
| **W, H** | The window's width and height in points. |

The main editor is display-first:

- Click a monitor in the overview to open that display's workspace inline.
- Use **Capture All Displays** at the top of Display Setup when you want to rebuild the full configuration from what is currently open.
- Use the app picker on the right to add or move an app onto the selected display.
- Drag windows on the canvas to place them visually.
- Use **Capture Current Display** inside the selected display workspace when you want to replace only that screen.

## Reordering Apps

The order of apps in a configuration matters.

- MagicDesktop applies the final move/raise pass in saved app order.
- Later items are raised later, so they end up above earlier items.
- The editor groups saved apps by display so each screen has its own list.
- In the editor, drag the handle on a row to reorder it.
- Drop on an app row to place the dragged app after that item.
- Use the top insertion line inside a display section to place the dragged app first on that display.

## Visual Display Editor

The Configurations tab shows a scaled overview of every currently connected display and uses the selected display workspace as the main setup flow.

- Each monitor card preserves that display's relative size and position.
- Selecting a monitor opens an inline workspace for that display.
- The canvas shows the apps assigned to that screen as draggable, resizable windows.
- The app list on the right supports drag-and-drop reordering for stacking, app removal, and app selection.
- Changes made in the canvas update the saved display-relative coordinates directly.
- If saved layouts belong to displays that are no longer connected, the editor shows a maintenance notice instead of a second editing surface.

The visual editor works in the same display-relative coordinate system used by MagicDesktop at activation time, so the saved layout remains portable across monitor arrangements.

## Capturing the Current Layout

Instead of entering values manually, click **Capture Running Apps**. This snapshots every visible app's current window position and size into the configuration, replacing any existing layouts.

Capture is a convenient way to set things up once by hand and save the result.

Multi-monitor capture behavior:

- Each window is assigned to the display that contains the largest share of that window.
- Captured apps are grouped in display-layout order, then by window position within each display.
- The display picker and row summary show display placement hints such as `Built-in`, `Left`, `Right`, `Above`, or `Below`.
- If MagicDesktop cannot confidently match a saved display, the row stays attached to that saved display and is marked `Unavailable`.
- The selected display workspace also includes **Capture Current Display**, which replaces only that screen's saved layouts and leaves other displays untouched.

Capture order is still editable. If you care about final stacking order, reorder the saved app list after capture.

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
