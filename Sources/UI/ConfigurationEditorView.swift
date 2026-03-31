import KeyboardShortcuts
import SwiftUI

struct ConfigurationEditorView: View {
    @Binding var config: SpaceConfiguration
    let slotIndex: Int

    var body: some View {
        Form {
            Section("General") {
                TextField("Name", text: $config.name)

                if slotIndex < 9 {
                    KeyboardShortcuts.Recorder(
                        "Shortcut",
                        name: .spaceSlot(slotIndex)
                    )
                }
            }

            Section("App Layouts") {
                let grouped = Dictionary(grouping: config.appLayouts) { layout in
                    layout.display?.displayString ?? "Unknown Display"
                }

                ForEach(grouped.keys.sorted(), id: \.self) { displayName in
                    Section {
                        ForEach(grouped[displayName] ?? []) { layout in
                            if let idx = config.appLayouts.firstIndex(where: { $0.id == layout.id }) {
                                AppLayoutRow(layout: $config.appLayouts[idx])
                            }
                        }
                        .onDelete { offsets in
                            let layoutsInGroup = grouped[displayName] ?? []
                            let idsToRemove = offsets.map { layoutsInGroup[$0].id }
                            config.appLayouts.removeAll { idsToRemove.contains($0.id) }
                        }
                    } header: {
                        Label(displayName, systemImage: "display")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Button("Add App") {
                    let primaryDisplay = NSScreen.screens.first.map {
                        WindowManager.displayInfo(for: $0)
                    }
                    config.appLayouts.append(AppLayout(display: primaryDisplay))
                }
            }

            Section("Capture Current Layout") {
                Button("Capture Running Apps") {
                    captureCurrentLayout()
                }
                .help("Captures the position and size of all currently visible app windows, grouped by display")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func captureCurrentLayout() {
        let workspace = NSWorkspace.shared
        var layouts: [AppLayout] = []

        for app in workspace.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            guard let result = WindowManager.captureDisplayRelativeLayout(for: app) else { continue }
            guard result.frame.width > 0 && result.frame.height > 0 else { continue }

            layouts.append(AppLayout(
                bundleIdentifier: bundleID,
                appName: app.localizedName ?? bundleID,
                frame: result.frame,
                display: result.display
            ))
        }

        config.appLayouts = layouts
    }
}

// MARK: - App Layout Row

struct AppLayoutRow: View {
    @Binding var layout: AppLayout

    var body: some View {
        DisclosureGroup {
            LabeledContent("App") {
                Picker("", selection: appSelection) {
                    Text("Choose an app…").tag("")

                    if !layout.bundleIdentifier.isEmpty,
                       !InstalledApps.all.contains(where: { $0.bundleIdentifier == layout.bundleIdentifier }) {
                        Text(layout.appName.isEmpty ? layout.bundleIdentifier : layout.appName)
                            .tag(layout.bundleIdentifier)
                    }

                    ForEach(InstalledApps.all) { app in
                        Text(app.name).tag(app.bundleIdentifier)
                    }
                }
            }

            LabeledContent("Display") {
                Picker("", selection: displaySelection) {
                    ForEach(WindowManager.currentDisplays(), id: \.self) { display in
                        Text(display.displayString).tag(display as DisplayInfo?)
                    }
                }
            }

            HStack {
                LabeledContent("X") {
                    TextField("0", value: $layout.frame.x, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                LabeledContent("Y") {
                    TextField("0", value: $layout.frame.y, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                LabeledContent("W") {
                    TextField("800", value: $layout.frame.width, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
                LabeledContent("H") {
                    TextField("600", value: $layout.frame.height, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let icon = InstalledApps.icon(for: layout.bundleIdentifier) {
                    Image(nsImage: icon)
                }
                Text(layout.appName.isEmpty ? "Unnamed App" : layout.appName)
            }
        }
    }

    private var appSelection: Binding<String> {
        Binding(
            get: { layout.bundleIdentifier },
            set: { newValue in
                layout.bundleIdentifier = newValue
                if let app = InstalledApps.all.first(where: { $0.bundleIdentifier == newValue }) {
                    layout.appName = app.name
                }
            }
        )
    }

    private var displaySelection: Binding<DisplayInfo?> {
        Binding(
            get: { layout.display },
            set: { layout.display = $0 }
        )
    }
}

// MARK: - Installed App Discovery

struct DiscoveredApp: Identifiable {
    let bundleIdentifier: String
    let name: String
    let icon: NSImage
    var id: String { bundleIdentifier }
}

enum InstalledApps {
    static let all: [DiscoveredApp] = {
        var apps: [String: DiscoveredApp] = [:]
        let fm = FileManager.default

        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        for dir in searchDirs {
            guard let enumerator = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                guard url.pathExtension == "app" else { continue }

                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier else { continue }

                guard apps[bundleID] == nil else { continue }

                let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                    ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                    ?? url.deletingPathExtension().lastPathComponent

                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icon.size = NSSize(width: 16, height: 16)

                apps[bundleID] = DiscoveredApp(
                    bundleIdentifier: bundleID,
                    name: name,
                    icon: icon
                )
            }
        }

        return apps.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }()

    static func icon(for bundleIdentifier: String) -> NSImage? {
        guard !bundleIdentifier.isEmpty else { return nil }
        if let app = all.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
            return app.icon
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        return icon
    }
}
