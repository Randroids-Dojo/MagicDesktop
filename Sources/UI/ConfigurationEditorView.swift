import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationEditorView: View {
    @Binding var config: SpaceConfiguration
    let slotIndex: Int
    @State private var draggedLayoutID: AppLayout.ID?
    @State private var targetedInsertionIndex: Int?
    @State private var dragResetTask: Task<Void, Never>?
    @State private var captureFeedback: CaptureFeedback?

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
                Text("Apps are grouped by display. Drag within a display to control the front-to-back order for that screen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if config.appLayouts.isEmpty {
                    ContentUnavailableView(
                        "No Apps Saved",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Capture your current windows or add apps manually.")
                    )
                } else {
                    VStack(spacing: 14) {
                        ForEach(displaySections) { section in
                            VStack(spacing: 0) {
                                AppLayoutSectionHeader(section: section)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 12)
                                    .padding(.bottom, 8)

                                AppLayoutDropZone(
                                    targetIndex: section.startIndex,
                                    targetedInsertionIndex: $targetedInsertionIndex,
                                    isEnabled: canDrop(into: section.display),
                                    onTargetingChanged: handleDropTargetChange,
                                    onDrop: moveDraggedLayout
                                )
                                .padding(.horizontal, 14)

                                ForEach(section.layouts) { item in
                                    if let bindingIndex = config.appLayouts.firstIndex(where: { $0.id == item.layout.id }) {
                                        AppLayoutRow(
                                            layout: $config.appLayouts[bindingIndex],
                                            isDragging: draggedLayoutID == item.layout.id,
                                            isDropTargeted: targetedInsertionIndex == item.storageIndex + 1,
                                            onDragStarted: { beginDragging(id: item.layout.id) },
                                            onDelete: { deleteLayout(id: item.layout.id) }
                                        )
                                        .contentShape(Rectangle())
                                        .padding(.horizontal, 12)
                                        .onDrop(
                                            of: [UTType.plainText],
                                            delegate: AppLayoutDropDelegate(
                                                targetIndex: item.storageIndex + 1,
                                                targetedInsertionIndex: $targetedInsertionIndex,
                                                isEnabled: canDrop(into: section.display),
                                                onTargetingChanged: handleDropTargetChange,
                                                onDrop: moveDraggedLayout
                                            )
                                        )
                                    }
                                }
                            }
                            .padding(.bottom, 10)
                            .background {
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                            }
                        }
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

                if let captureFeedback {
                    Label(captureFeedback.message, systemImage: captureFeedback.systemImage)
                        .font(.callout)
                        .foregroundStyle(captureFeedback.color)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func captureCurrentLayout() {
        guard WindowManager.ensureAccessibilityAccess(prompt: true) else {
            captureFeedback = CaptureFeedback(
                message: "Accessibility permission is required before MagicDesktop can capture window layouts.",
                kind: .warning
            )
            return
        }

        let workspace = NSWorkspace.shared
        var capturedLayouts: [CapturedLayout] = []

        for app in workspace.runningApplications where app.activationPolicy == .regular {
            guard let bundleID = app.bundleIdentifier else { continue }
            guard let result = WindowManager.captureDisplayRelativeLayout(for: app) else { continue }
            guard result.relativeFrame.width > 0 && result.relativeFrame.height > 0 else { continue }

            capturedLayouts.append(
                CapturedLayout(
                    absoluteFrame: result.absoluteFrame,
                    layout: AppLayout(
                        bundleIdentifier: bundleID,
                        appName: app.localizedName ?? bundleID,
                        frame: result.relativeFrame,
                        display: result.display
                    )
                )
            )
        }

        guard !capturedLayouts.isEmpty else {
            captureFeedback = CaptureFeedback(
                message: "No standard app windows were available to capture.",
                kind: .warning
            )
            return
        }

        let displayOrder = Dictionary(
            uniqueKeysWithValues: WindowManager.currentDisplays().enumerated().map { index, display in
                (display, index)
            }
        )

        let sortedLayouts = capturedLayouts.sorted { lhs, rhs in
            let lhsDisplayIndex = displaySortIndex(for: lhs.layout.display, displayOrder: displayOrder)
            let rhsDisplayIndex = displaySortIndex(for: rhs.layout.display, displayOrder: displayOrder)

            if lhsDisplayIndex != rhsDisplayIndex {
                return lhsDisplayIndex < rhsDisplayIndex
            }

            if lhs.absoluteFrame.y != rhs.absoluteFrame.y {
                return lhs.absoluteFrame.y < rhs.absoluteFrame.y
            }

            if lhs.absoluteFrame.x != rhs.absoluteFrame.x {
                return lhs.absoluteFrame.x < rhs.absoluteFrame.x
            }

            return lhs.layout.appName.localizedStandardCompare(rhs.layout.appName) == .orderedAscending
        }

        config.appLayouts = sortedLayouts.map(\.layout)

        let displayCount = Set(sortedLayouts.compactMap(\.layout.display)).count
        let displaySummary = displayCount == 1 ? "1 display" : "\(displayCount) displays"
        let appSummary = sortedLayouts.count == 1 ? "1 app" : "\(sortedLayouts.count) apps"
        captureFeedback = CaptureFeedback(
            message: "Captured \(appSummary) across \(displaySummary). Reorder the list if you want a different front-to-back stacking order.",
            kind: .success
        )
    }

    private func displaySortIndex(
        for display: DisplayInfo?,
        displayOrder: [DisplayInfo: Int]
    ) -> Int {
        guard let display else { return Int.max }
        return displayOrder[display] ?? Int.max
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

    private var displaySections: [AppLayoutSection] {
        let currentDisplayOrder = WindowManager.currentDisplays().map { DisplaySectionKey(display: $0) }
        var groupedItems: [DisplaySectionKey: [IndexedAppLayout]] = [:]
        var extraKeys: [DisplaySectionKey] = []

        for (storageIndex, layout) in config.appLayouts.enumerated() {
            let key = DisplaySectionKey(display: sectionDisplay(for: layout.display))

            if groupedItems[key] == nil,
               !currentDisplayOrder.contains(key),
               !extraKeys.contains(key) {
                extraKeys.append(key)
            }

            groupedItems[key, default: []].append(
                IndexedAppLayout(
                    storageIndex: storageIndex,
                    layout: layout
                )
            )
        }

        let orderedKeys = currentDisplayOrder.filter { groupedItems[$0] != nil } + extraKeys

        return orderedKeys.compactMap { key in
            guard let layouts = groupedItems[key], !layouts.isEmpty else { return nil }
            return AppLayoutSection(display: key.display, layouts: layouts)
        }
    }

    private func canDrop(into display: DisplayInfo?) -> Bool {
        guard let draggedLayoutID,
              let draggedLayout = config.appLayouts.first(where: { $0.id == draggedLayoutID }) else {
            return true
        }

        return sectionDisplay(for: draggedLayout.display) == display
    }

    private func sectionDisplay(for display: DisplayInfo?) -> DisplayInfo? {
        guard let display else { return nil }
        return WindowManager.connectedDisplayInfo(for: display) ?? display
    }
}

private struct CapturedLayout {
    let absoluteFrame: WindowFrame
    let layout: AppLayout
}

private struct CaptureFeedback {
    enum Kind {
        case success
        case warning
    }

    let message: String
    let kind: Kind

    var systemImage: String {
        switch kind {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch kind {
        case .success:
            .green
        case .warning:
            .orange
        }
    }
}

private struct IndexedAppLayout: Identifiable {
    let storageIndex: Int
    let layout: AppLayout

    var id: AppLayout.ID { layout.id }
}

private struct DisplaySectionKey: Hashable {
    let display: DisplayInfo?
}

private struct AppLayoutSection: Identifiable {
    let display: DisplayInfo?
    let layouts: [IndexedAppLayout]

    var id: String {
        if let display {
            displaySectionIdentifier(for: display)
        } else {
            "no-display"
        }
    }

    var startIndex: Int {
        layouts.map(\.storageIndex).min() ?? 0
    }
}

private struct AppLayoutSectionHeader: View {
    let section: AppLayoutSection

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sectionTitle)
                    .font(.headline)

                Text(appCountLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let display = section.display,
               !WindowManager.isDisplayConnected(display) {
                Text(unavailableDisplayLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.14), in: Capsule())
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sectionTitle: String {
        guard let display = section.display else { return "No Display" }
        return displayEditorLabel(for: display)
    }

    private var appCountLabel: String {
        let count = section.layouts.count
        return count == 1 ? "1 app" : "\(count) apps"
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
                    ForEach(availableDisplays, id: \.self) { display in
                        Text(displayLabel(for: display)).tag(display as DisplayInfo?)
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
            get: {
                guard let display = layout.display else { return nil }
                return WindowManager.connectedDisplayInfo(for: display) ?? display
            },
            set: { layout.display = $0 }
        )
    }

    private var availableDisplays: [DisplayInfo] {
        var displays = WindowManager.currentDisplays()

        if let storedDisplay = layout.display,
           WindowManager.connectedDisplayInfo(for: storedDisplay) == nil {
            displays.append(storedDisplay)
        }

        return displays
    }

    private func displayLabel(for display: DisplayInfo) -> String {
        if WindowManager.isDisplayConnected(display) {
            return displayEditorLabel(for: display)
        }

        return "\(displayEditorLabel(for: display)) (\(unavailableDisplayLabel))"
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

                if let display = layout.display {
                    HStack(spacing: 6) {
                        Text(displayEditorLabel(for: display))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if !WindowManager.isDisplayConnected(display) {
                            Text(unavailableDisplayLabel)
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.14), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Unknown Display")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private let unavailableDisplayLabel = "Unavailable"

private func displaySectionIdentifier(for display: DisplayInfo) -> String {
    if let uuid = display.uuid {
        return uuid
    }

    return [
        display.name,
        String(Int(display.width)),
        String(Int(display.height)),
        String(display.originX ?? 0),
        String(display.originY ?? 0),
        String(display.isBuiltIn ?? false),
    ].joined(separator: "|")
}

private func displayEditorLabel(for display: DisplayInfo) -> String {
    let resolvedDisplay = WindowManager.connectedDisplayInfo(for: display) ?? display
    let detail = displayPlacementDetail(for: resolvedDisplay)

    if let detail {
        return "\(resolvedDisplay.displayString) • \(detail)"
    }

    return resolvedDisplay.displayString
}

private func displayPlacementDetail(for display: DisplayInfo) -> String? {
    if display.isBuiltIn == true {
        return "Built-in"
    }

    guard let originX = display.originX,
          let originY = display.originY else {
        return nil
    }

    let horizontal: String?
    if originX < -1 {
        horizontal = "Left"
    } else if originX > 1 {
        horizontal = "Right"
    } else {
        horizontal = nil
    }

    let vertical: String?
    if originY > 1 {
        vertical = "Above"
    } else if originY < -1 {
        vertical = "Below"
    } else {
        vertical = nil
    }

    switch (vertical, horizontal) {
    case let (vertical?, horizontal?):
        return "\(vertical) \(horizontal)"
    case let (vertical?, nil):
        return vertical
    case let (nil, horizontal?):
        return horizontal
    case (nil, nil):
        return "Primary Display"
    }
}

private struct AppLayoutDropZone: View {
    let targetIndex: Int
    @Binding var targetedInsertionIndex: Int?
    let isEnabled: Bool
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
                isEnabled: isEnabled,
                onTargetingChanged: onTargetingChanged,
                onDrop: onDrop
            )
        )
    }
}

private struct AppLayoutDropDelegate: DropDelegate {
    let targetIndex: Int
    @Binding var targetedInsertionIndex: Int?
    let isEnabled: Bool
    let onTargetingChanged: (_ isTargeted: Bool, _ targetIndex: Int) -> Void
    let onDrop: (_ draggedID: AppLayout.ID, _ targetIndex: Int) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        isEnabled && info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        guard isEnabled else { return }
        onTargetingChanged(true, targetIndex)
    }

    func dropExited(info: DropInfo) {
        guard isEnabled else { return }
        onTargetingChanged(false, targetIndex)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard isEnabled else { return nil }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard isEnabled else { return false }
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
