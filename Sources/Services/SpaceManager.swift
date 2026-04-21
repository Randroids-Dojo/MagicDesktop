import AppKit
import OSLog

@MainActor
final class SpaceManager {
    private static let finderBundleIdentifier = "com.apple.finder"

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MagicDesktop",
        category: "SpaceManager"
    )
    private let desktopManager = DesktopManager()

    private struct PreparedLayout {
        let index: Int
        let app: NSRunningApplication
        let frame: WindowFrame
        let layout: AppLayout
        let desktop: DesktopManager.ManagedDesktop
    }

    func activate(_ config: SpaceConfiguration) async {
        guard WindowManager.ensureAccessibilityAccess(prompt: true) else {
            logger.error("Cannot activate configuration '\(config.name)' because Accessibility permission is not granted")
            return
        }

        do {
            try desktopManager.validateEnvironment()
            let targetDesktops = try desktopManager.ensureDesktopCount(config.desktops.count)

            logger.debug(
                "Activating configuration '\(config.name)' with \(config.desktops.count) desktop(s) and \(config.totalAppCount) app layout(s)"
            )

            for (desktopIndex, desktopLayout) in config.desktops.enumerated() {
                let targetDesktop = targetDesktops[desktopIndex]

                logger.debug(
                    "Preparing desktop \(desktopIndex + 1) '\(desktopLayout.name)' spaceID=\(targetDesktop.id) with \(desktopLayout.appLayouts.count) app(s)"
                )

                desktopManager.renameDesktop(targetDesktop, to: desktopLayout.name)
                try await desktopManager.switchToDesktop(targetDesktop)

                let preparedLayouts = await withTaskGroup(of: PreparedLayout?.self, returning: [PreparedLayout].self) { group in
                    for (layoutIndex, layout) in desktopLayout.appLayouts.enumerated() {
                        group.addTask {
                            await self.prepareLayout(layout, index: layoutIndex, on: targetDesktop)
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
                        "Applying desktop \(desktopIndex + 1) layout \(preparedLayout.index) for '\(preparedLayout.layout.appName)' bundle=\(preparedLayout.layout.bundleIdentifier) targetFrame=\(Self.describe(preparedLayout.frame)) display=\(preparedLayout.layout.display?.displayString ?? "none")"
                    )

                    await WindowManager.positionAndRaiseWindow(for: preparedLayout.app, frame: preparedLayout.frame)

                    if let finalFrame = WindowManager.captureCurrentFrame(for: preparedLayout.app) {
                        logger.debug("Final observed frame for '\(preparedLayout.layout.appName)' is \(Self.describe(finalFrame))")
                    } else {
                        logger.error("Could not read final frame for '\(preparedLayout.layout.appName)' after move")
                    }
                }
            }
        } catch {
            logger.error("Failed to activate configuration '\(config.name)': \(error.localizedDescription)")
            presentActivationError(error.localizedDescription)
        }
    }

    private func prepareLayout(
        _ layout: AppLayout,
        index: Int,
        on desktop: DesktopManager.ManagedDesktop
    ) async -> PreparedLayout? {
        let frame = resolveFrame(layout)
        let workspace = NSWorkspace.shared

        if let app = workspace.runningApplications.first(where: { $0.bundleIdentifier == layout.bundleIdentifier }) {
            logger.debug(
                "Using running app '\(layout.appName)' bundle=\(layout.bundleIdentifier) pid=\(app.processIdentifier) resolvedFrame=\(Self.describe(frame))"
            )
            await ensureRestorableWindow(for: app, layout: layout, workspace: workspace)
            moveWindowIfNeeded(for: app, to: desktop, layout: layout)
            return PreparedLayout(index: index, app: app, frame: frame, layout: layout, desktop: desktop)
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
                moveWindowIfNeeded(for: app, to: desktop, layout: layout)
                logger.debug("Launched app bundle=\(layout.bundleIdentifier) pid=\(app.processIdentifier) resolvedFrame=\(Self.describe(frame))")
                return PreparedLayout(index: index, app: app, frame: frame, layout: layout, desktop: desktop)
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

    private func moveWindowIfNeeded(
        for app: NSRunningApplication,
        to desktop: DesktopManager.ManagedDesktop,
        layout: AppLayout
    ) {
        guard let windowID = WindowManager.targetWindowID(for: app) else {
            logger.debug(
                "No CGWindowID available for '\(layout.appName)' bundle=\(layout.bundleIdentifier); leaving it on the current desktop"
            )
            return
        }

        desktopManager.moveWindow(windowID, to: desktop)
    }

    private func presentActivationError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "MagicDesktop could not restore this configuration"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private static func describe(_ frame: WindowFrame) -> String {
        "(x: \(Int(frame.x)), y: \(Int(frame.y)), w: \(Int(frame.width)), h: \(Int(frame.height)))"
    }
}
