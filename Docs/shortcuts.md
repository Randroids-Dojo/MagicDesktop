# Global Shortcuts

MagicDesktop registers global keyboard shortcuts that work from any app.

## Default Bindings

| Shortcut | Action |
|----------|--------|
| `Ctrl+Opt+1` | Activate configuration in slot 1 |
| `Ctrl+Opt+2` | Activate configuration in slot 2 |
| ... | ... |
| `Ctrl+Opt+9` | Activate configuration in slot 9 |

Slots correspond to the order of configurations in the sidebar (top = slot 1).

## Customizing Shortcuts

Open a configuration in the editor. The **Shortcut** field shows a recorder — click it and press any key combination to reassign that slot's shortcut. Custom bindings are persisted across launches.

Up to 9 configurations can have shortcuts. Configurations beyond slot 9 are still accessible from the menu bar dropdown but have no default shortcut.

## How It Works

Shortcuts are managed by the [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) package, which handles registration, persistence, and conflict detection at the system level.
