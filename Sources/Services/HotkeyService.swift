import KeyboardShortcuts

@MainActor
final class HotkeyService {
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
                    self?.activateSlot(i)
                }
            }
        }
    }

    private func activateSlot(_ index: Int) {
        let configs = configStore.configurations
        guard index < configs.count else { return }
        Task {
            await spaceManager.activate(configs[index])
        }
    }
}
