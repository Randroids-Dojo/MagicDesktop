import AppKit

@MainActor
final class SpaceManager {
    func activate(_ config: SpaceConfiguration) async {
        await withTaskGroup(of: Void.self) { group in
            for layout in config.appLayouts {
                group.addTask {
                    await self.launchAndPosition(layout)
                }
            }
        }
    }

    private func launchAndPosition(_ layout: AppLayout) async {
        let frame = resolveFrame(layout)
        let workspace = NSWorkspace.shared

        if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == layout.bundleIdentifier }) {
            app.activate()
            WindowManager.positionWindow(for: app, frame: frame)
        } else {
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: layout.bundleIdentifier) else {
                print("Could not find app: \(layout.bundleIdentifier)")
                return
            }

            do {
                let app = try await workspace.openApplication(
                    at: appURL,
                    configuration: NSWorkspace.OpenConfiguration()
                )
                await waitForWindow(app: app)
                WindowManager.positionWindow(for: app, frame: frame)
            } catch {
                print("Failed to launch \(layout.bundleIdentifier): \(error)")
            }
        }
    }

    /// Converts display-relative coordinates to absolute, or passes through legacy absolute coords.
    private func resolveFrame(_ layout: AppLayout) -> WindowFrame {
        guard let display = layout.display else {
            return layout.frame // legacy config: treat as absolute
        }
        return WindowManager.absoluteFrame(for: layout.frame, on: display)
    }

    private func waitForWindow(app: NSRunningApplication, timeout: Duration = .seconds(5)) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if WindowManager.captureCurrentFrame(for: app) != nil { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
