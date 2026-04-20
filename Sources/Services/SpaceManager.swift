import AppKit
import OSLog

@MainActor
final class SpaceManager {
    private static let finderBundleIdentifier = "com.apple.finder"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MagicDesktop",
        category: "SpaceManager"
    )

    private struct PreparedLayout {
        let index: Int
        let app: NSRunningApplication
        let frame: WindowFrame
        let layout: AppLayout
    }

    func activate(_ config: SpaceConfiguration) async {
        guard WindowManager.ensureAccessibilityAccess(prompt: true) else {
            logger.error("Cannot activate configuration '\(config.name)' because Accessibility permission is not granted")
            return
        }

        logger.debug("Activating configuration '\(config.name)' with \(config.appLayouts.count) app layout(s)")

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
                logger.debug("Unhiding app '\(preparedLayout.layout.appName)' pid=\(preparedLayout.app.processIdentifier)")
                preparedLayout.app.unhide()
            }

            logger.debug(
                "Applying layout \(preparedLayout.index) for '\(preparedLayout.layout.appName)' bundle=\(preparedLayout.layout.bundleIdentifier) targetFrame=\(Self.describe(preparedLayout.frame)) display=\(preparedLayout.layout.display?.displayString ?? "none")"
            )

            await WindowManager.positionAndRaiseWindow(for: preparedLayout.app, frame: preparedLayout.frame)

            if let finalFrame = WindowManager.captureCurrentFrame(for: preparedLayout.app) {
                logger.debug("Final observed frame for '\(preparedLayout.layout.appName)' is \(Self.describe(finalFrame))")
            } else {
                logger.error("Could not read final frame for '\(preparedLayout.layout.appName)' after move")
            }
        }
    }

    private func prepareLayout(_ layout: AppLayout, index: Int) async -> PreparedLayout? {
        let frame = resolveFrame(layout)
        let workspace = NSWorkspace.shared

        if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == layout.bundleIdentifier }) {
            logger.debug(
                "Using running app '\(layout.appName)' bundle=\(layout.bundleIdentifier) pid=\(app.processIdentifier) resolvedFrame=\(Self.describe(frame))"
            )
            await ensureRestorableWindow(for: app, layout: layout, workspace: workspace)
            return PreparedLayout(index: index, app: app, frame: frame, layout: layout)
        } else {
            guard let appURL = workspace.urlForApplication(withBundleIdentifier: layout.bundleIdentifier) else {
                logger.error("Could not find app bundle=\(layout.bundleIdentifier)")
                return nil
            }

            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false

                logger.debug("Launching app bundle=\(layout.bundleIdentifier) from \(appURL.path)")
                let app = try await workspace.openApplication(
                    at: appURL,
                    configuration: configuration
                )
                if layout.bundleIdentifier == Self.finderBundleIdentifier {
                    await ensureRestorableWindow(for: app, layout: layout, workspace: workspace)
                } else {
                    await waitForWindow(app: app)
                }
                logger.debug("Launched app bundle=\(layout.bundleIdentifier) pid=\(app.processIdentifier) resolvedFrame=\(Self.describe(frame))")
                return PreparedLayout(index: index, app: app, frame: frame, layout: layout)
            } catch {
                logger.error("Failed to launch bundle=\(layout.bundleIdentifier): \(error.localizedDescription)")
                return nil
            }
        }
    }

    /// Converts display-relative coordinates to absolute, or passes through legacy absolute coords.
    private func resolveFrame(_ layout: AppLayout) -> WindowFrame {
        guard let display = layout.display else {
            logger.debug("Layout '\(layout.appName)' has no display; using legacy absolute frame \(Self.describe(layout.frame))")
            return layout.frame
        }

        let resolved = WindowManager.absoluteFrame(for: layout.frame, on: display)
        logger.debug(
            "Resolved display-relative frame for '\(layout.appName)' display=\(display.displayString) from \(Self.describe(layout.frame)) to absolute \(Self.describe(resolved))"
        )
        return resolved
    }

    private func waitForWindow(app: NSRunningApplication, timeout: Duration = .seconds(5)) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if WindowManager.hasWindow(for: app) { return }
            try? await Task.sleep(for: .milliseconds(100))
        }

        logger.error("Timed out waiting for window for pid=\(app.processIdentifier)")
    }

    private func ensureRestorableWindow(
        for app: NSRunningApplication,
        layout: AppLayout,
        workspace: NSWorkspace
    ) async {
        guard layout.bundleIdentifier == Self.finderBundleIdentifier else { return }
        guard !WindowManager.hasWindow(for: app) else { return }

        let homeURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        logger.debug(
            "Finder has no browser window for saved layout '\(layout.appName)'; opening \(homeURL.path) so the window can be restored"
        )

        _ = workspace.open(homeURL)
        await waitForWindow(app: app)
    }

    private static func describe(_ frame: WindowFrame) -> String {
        "(x: \(Int(frame.x)), y: \(Int(frame.y)), w: \(Int(frame.width)), h: \(Int(frame.height)))"
    }
}
