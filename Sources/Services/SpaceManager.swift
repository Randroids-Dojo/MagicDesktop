import AppKit

@MainActor
final class SpaceManager {
    private struct PreparedLayout {
        let index: Int
        let app: NSRunningApplication
        let frame: WindowFrame
    }

    func activate(_ config: SpaceConfiguration) async {
        let preparedLayouts = await withTaskGroup(of: PreparedLayout?.self, returning: [PreparedLayout].self) { group in
            for (index, layout) in config.appLayouts.enumerated() {
                group.addTask {
                    await self.prepareLayout(layout, index: index)
                }
            }

            var preparedLayouts: [PreparedLayout] = []
            for await preparedLayout in group {
                if let preparedLayout {
                    preparedLayouts.append(preparedLayout)
                }
            }

            return preparedLayouts.sorted { $0.index < $1.index }
        }

        for preparedLayout in preparedLayouts {
            if preparedLayout.app.isHidden {
                preparedLayout.app.unhide()
            }

            WindowManager.positionWindow(for: preparedLayout.app, frame: preparedLayout.frame)
            WindowManager.raiseWindow(for: preparedLayout.app)
        }
    }

    private func prepareLayout(_ layout: AppLayout, index: Int) async -> PreparedLayout? {
        let frame = resolveFrame(layout)
        let workspace = NSWorkspace.shared

        if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == layout.bundleIdentifier }) {
            return PreparedLayout(index: index, app: app, frame: frame)
        } else {
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: layout.bundleIdentifier) else {
                print("Could not find app: \(layout.bundleIdentifier)")
                return nil
            }

            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false

                let app = try await workspace.openApplication(
                    at: appURL,
                    configuration: configuration
                )
                await waitForWindow(app: app)
                return PreparedLayout(index: index, app: app, frame: frame)
            } catch {
                print("Failed to launch \(layout.bundleIdentifier): \(error)")
                return nil
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
            if WindowManager.hasWindow(for: app) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
