import KeyboardShortcuts
import OSLog

@MainActor
final class HotkeyService {
    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MagicDesktop",
        category: "HotkeyService"
    )

    private let configStore: ConfigurationStore
    private let spaceManager: SpaceManager

    init(configStore: ConfigurationStore, spaceManager: SpaceManager) {
        self.configStore = configStore
        self.spaceManager = spaceManager
        setupHandlers()
    }

    private func setupHandlers() {
        for i in 0..<9 {
            let name = KeyboardShortcuts.Name.spaceSlot(i)
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                Task { @MainActor in
                    self?.logger.debug("Received shortcut for slot \(i)")
                    self?.activateSlot(i)
                }
            }
        }
    }

    private func activateSlot(_ index: Int) {
        let configs = configStore.configurations
        guard index < configs.count else {
            logger.error("Shortcut slot \(index) has no configuration")
            return
        }

        logger.debug("Activating slot \(index) config '\(configs[index].name)'")
        Task {
            await spaceManager.activate(configs[index])
        }
    }
}
