import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!
    private var settingsWindow: NSWindow?

    private let configStore: ConfigurationStore
    private let spaceManager: SpaceManager
    private let settingsNavigation = SettingsNavigationModel()

    init(configStore: ConfigurationStore, spaceManager: SpaceManager) {
        self.configStore = configStore
        self.spaceManager = spaceManager
        super.init()
        setupStatusItem()
        setupMenu()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "rectangle.split.3x3",
            accessibilityDescription: "MagicDesktop"
        )
        button.imagePosition = .imageLeading
    }

    // MARK: - Menu

    private func setupMenu() {
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let configs = configStore.configurations
        if configs.isEmpty {
            let emptyItem = NSMenuItem(title: "No Configurations", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for config in configs {
                let item = NSMenuItem(
                    title: config.name,
                    action: #selector(activateConfiguration(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = config.id
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let editItem = NSMenuItem(
            title: "Edit Configurations…",
            action: #selector(openConfigEditor),
            keyEquivalent: ","
        )
        editItem.target = self
        menu.addItem(editItem)

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ""
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MagicDesktop",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func activateConfiguration(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? SpaceConfiguration.ID else { return }
        guard let config = configStore.configurations.first(where: { $0.id == id }) else { return }
        Task {
            await spaceManager.activate(config)
        }
    }

    @objc private func openConfigEditor() {
        openSettingsWindow(selecting: .configurations)
    }

    @objc private func openSettings() {
        openSettingsWindow(selecting: .buildInstall)
    }

    // MARK: - Window Helpers

    private func openSettingsWindow(selecting tab: SettingsTab) {
        settingsNavigation.selectedTab = tab

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let spaceManager = self.spaceManager
        let view = SettingsView(
            navigation: settingsNavigation,
            store: configStore,
            onActivate: { config in
                Task { await spaceManager.activate(config) }
            }
        )
        settingsWindow = makeWindow(title: "MagicDesktop Settings", rootView: view, size: NSSize(width: 1140, height: 760))
    }

    private func makeWindow<V: View>(title: String, rootView: V, size: NSSize) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(size)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] notification in
            guard let closedWindow = notification.object as? NSWindow else { return }
            Task { @MainActor in
                if self?.settingsWindow === closedWindow { self?.settingsWindow = nil }
            }
        }

        return window
    }
}
