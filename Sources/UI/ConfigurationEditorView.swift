import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationEditorView: View {
    @Binding var config: SpaceConfiguration
    let slotIndex: Int
    @State private var draggedLayoutID: AppLayout.ID?
    @State private var targetedInsertionIndex: Int?
    @State private var dragResetTask: Task<Void, Never>?

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
                Text("Drag apps into the exact order you want. Drop on an app to place the dragged app after it, or use the top line to place it first.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if config.appLayouts.isEmpty {
                    ContentUnavailableView(
                        "No Apps Saved",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Capture your current windows or add apps manually.")
                    )
                } else {
                    VStack(spacing: 0) {
                        AppLayoutDropZone(
                            targetIndex: 0,
                            targetedInsertionIndex: $targetedInsertionIndex,
                            onTargetingChanged: handleDropTargetChange,
                            onDrop: moveDraggedLayout
                        )

                        ForEach(Array(config.appLayouts.enumerated()), id: \.element.id) { index, layout in
                            if let bindingIndex = config.appLayouts.firstIndex(where: { $0.id == layout.id }) {
                                AppLayoutRow(
                                    layout: $config.appLayouts[bindingIndex],
                                    isDragging: draggedLayoutID == layout.id,
                                    isDropTargeted: targetedInsertionIndex == index + 1,
                                    onDragStarted: { beginDragging(id: layout.id) },
                                    onDelete: { deleteLayout(id: layout.id) }
                                )
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [UTType.plainText],
                                    delegate: AppLayoutDropDelegate(
                                        targetIndex: index + 1,
                                        targetedInsertionIndex: $targetedInsertionIndex,
                                        onTargetingChanged: handleDropTargetChange,
                                        onDrop: moveDraggedLayout
                                    )
                                )

                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: .controlBackgroundColor))
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
                .help("Captures the position and size of all currently visible app windows and records which display each one belongs to")
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

    private func deleteLayout(id: AppLayout.ID) {
        config.appLayouts.removeAll { $0.id == id }
    }

    private func beginDragging(id: AppLayout.ID) {
        dragResetTask?.cancel()
        draggedLayoutID = id
    }

    private func handleDropTargetChange(isTargeted: Bool, at targetIndex: Int) {
        if isTargeted {
            dragResetTask?.cancel()
            targetedInsertionIndex = targetIndex
            return
        }

        if targetedInsertionIndex == targetIndex {
            targetedInsertionIndex = nil
            scheduleDragResetIfNeeded()
        }
    }

    private func scheduleDragResetIfNeeded() {
        dragResetTask?.cancel()

        guard draggedLayoutID != nil else { return }

        dragResetTask = Task {
            try? await Task.sleep(for: .milliseconds(200))

            guard !Task.isCancelled else { return }
            await MainActor.run {
                if targetedInsertionIndex == nil {
                    clearDragState()
                }
            }
        }
    }

    private func clearDragState() {
        dragResetTask?.cancel()
        dragResetTask = nil
        draggedLayoutID = nil
        targetedInsertionIndex = nil
    }

    private func moveDraggedLayout(_ draggedID: AppLayout.ID, to targetIndex: Int) {
        guard let sourceIndex = config.appLayouts.firstIndex(where: { $0.id == draggedID }) else {
            clearDragState()
            return
        }

        var destinationIndex = targetIndex
        if sourceIndex < destinationIndex {
            destinationIndex -= 1
        }

        let movedLayout = config.appLayouts.remove(at: sourceIndex)
        let clampedDestination = min(max(destinationIndex, 0), config.appLayouts.count)
        config.appLayouts.insert(movedLayout, at: clampedDestination)
        clearDragState()
    }
}

// MARK: - App Layout Row

struct AppLayoutRow: View {
    @Binding var layout: AppLayout
    let isDragging: Bool
    let isDropTargeted: Bool
    let onDragStarted: () -> Void
    let onDelete: () -> Void

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
                dragHandle
                AppLayoutSummary(layout: layout)

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove app from this configuration")
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        Color.accentColor.opacity(
                            isDragging ? 0.12 : (isDropTargeted ? 0.08 : 0)
                        )
                    )
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isDragging ? Color.accentColor.opacity(0.35) : (
                            isDropTargeted ? Color.accentColor.opacity(0.2) : .clear
                        ),
                        style: StrokeStyle(
                            lineWidth: 1,
                            dash: isDragging ? [5, 4] : []
                        )
                    )
            }
            .opacity(isDragging ? 0.38 : 1)
            .scaleEffect(isDragging ? 0.985 : 1)
            .animation(.easeInOut(duration: 0.14), value: isDragging)
            .animation(.easeInOut(duration: 0.14), value: isDropTargeted)
        }
    }

    private var dragHandle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
        }
        .frame(width: 36, height: 30)
        .contentShape(Rectangle())
        .help("Drag to reorder")
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: layout.id.uuidString as NSString)
        } preview: {
            AppLayoutDragPreview(layout: layout)
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

private struct AppLayoutSummary: View {
    let layout: AppLayout

    var body: some View {
        HStack(spacing: 8) {
            if let icon = InstalledApps.icon(for: layout.bundleIdentifier) {
                Image(nsImage: icon)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(layout.appName.isEmpty ? "Unnamed App" : layout.appName)
                Text(layout.display?.displayString ?? "Unknown Display")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppLayoutDropZone: View {
    let targetIndex: Int
    @Binding var targetedInsertionIndex: Int?
    let onTargetingChanged: (_ isTargeted: Bool, _ targetIndex: Int) -> Void
    let onDrop: (_ draggedID: AppLayout.ID, _ targetIndex: Int) -> Void

    var body: some View {
        ZStack {
            Capsule()
                .fill(targetedInsertionIndex == targetIndex ? Color.accentColor : Color.secondary.opacity(0.18))
                .frame(height: targetedInsertionIndex == targetIndex ? 5 : 1)
        }
        .frame(height: 12)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.plainText],
            delegate: AppLayoutDropDelegate(
                targetIndex: targetIndex,
                targetedInsertionIndex: $targetedInsertionIndex,
                onTargetingChanged: onTargetingChanged,
                onDrop: onDrop
            )
        )
    }
}

private struct AppLayoutDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var targetedInsertionIndex: Int?
    let onTargetingChanged: (_ isTargeted: Bool, _ targetIndex: Int) -> Void
    let onDrop: (_ draggedID: AppLayout.ID, _ targetIndex: Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        onTargetingChanged(true, targetIndex)
    }

    func dropExited(info: DropInfo) {
        onTargetingChanged(false, targetIndex)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        targetedInsertionIndex = nil

        guard let itemProvider = info.itemProviders(for: [UTType.plainText]).first else {
            return false
        }

        itemProvider.loadObject(ofClass: NSString.self) { object, _ in
            guard let identifier = object as? NSString,
                  let draggedID = UUID(uuidString: identifier as String) else {
                return
            }

            Task { @MainActor in
                onDrop(draggedID, targetIndex)
            }
        }

        return true
    }
}

private struct AppLayoutDragPreview: View {
    let layout: AppLayout

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)

            AppLayoutSummary(layout: layout)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
        .frame(minWidth: 220, alignment: .leading)
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
