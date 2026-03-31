import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var hotkeyService: HotkeyService?
    private let configStore = ConfigurationStore()
    private let spaceManager = SpaceManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController(
            configStore: configStore,
            spaceManager: spaceManager
        )

        hotkeyService = HotkeyService(
            configStore: configStore,
            spaceManager: spaceManager
        )
    }
}
