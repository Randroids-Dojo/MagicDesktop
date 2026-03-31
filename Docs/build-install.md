# Building and Installing

## Development Build

```bash
# Generate the Xcode project (requires XcodeGen)
xcodegen generate

# Build from the command line
xcodebuild -project MagicDesktop.xcodeproj -scheme MagicDesktop -destination 'platform=macOS' build

# Or open in Xcode
open MagicDesktop.xcodeproj
```

## Self-Updating Install

MagicDesktop includes a built-in **Build & Reinstall** feature accessible from the menu bar under **Settings...**. It:

1. Runs `xcodegen generate` to regenerate the Xcode project.
2. Builds a release with `xcodebuild`.
3. Replaces `/Applications/MagicDesktop.app` with the new build.
4. Restarts the app.

If `/Applications` is not writable, it will prompt for administrator privileges.

### Repository Path

By default, the build service looks for the repository at the same path as the running source. You can change this with the **Choose Repo...** button in Settings. The selection is persisted in `UserDefaults`.

## Accessibility Permissions

MagicDesktop uses the macOS Accessibility API to move and resize windows. On first run, macOS will prompt you to grant access in:

**System Settings > Privacy & Security > Accessibility**

The app will not be able to position windows until this permission is granted.
