import KeyboardShortcuts
import SwiftUI
import UniformTypeIdentifiers

/// Editor for a single `SpaceConfiguration`.
///
/// The layout is a three-row stack:
///   1. Header bar — inline-editable name, shortcut chip, Capture, and Run
///   2. Desktop bar — segmented desktop chips with per-chip context menu, inline rename
///   3. Workspace — a horizontal display minimap sitting above the drag-to-position canvas
///
/// No more card-in-card — chrome is limited to two dividers and a single content padding.
@MainActor
struct ConfigurationEditorView: View {
    @Binding var config: SpaceConfiguration
    let slotIndex: Int
    let onActivate: (SpaceConfiguration) -> Void

    private let desktopManager = DesktopManager()
    @State private var captureFeedback: CaptureFeedback?
    @State private var selectedDesktopID: DesktopLayout.ID?
    @State private var selectedDisplayID: String?

    var body: some View {
        ScrollView(.vertical) {
            VStack(spacing: 0) {
                headerBar
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 18)

                Divider()

                desktopBar
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)

                Divider()

                workspace
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            ensureValidSelectedDesktop()
            ensureValidSelectedDisplay()
        }
        .onChange(of: config.desktops.map(\.id)) { _, _ in
            ensureValidSelectedDesktop()
            ensureValidSelectedDisplay()
        }
        .onChange(of: selectedDesktopID) { _, _ in
            ensureValidSelectedDisplay()
        }
        .onChange(of: connectedDisplayIdentifiers) { _, _ in
            ensureValidSelectedDisplay()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Configuration Name", text: $config.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 24, weight: .semibold))
                    .lineLimit(1)
                    .frame(maxWidth: 360, alignment: .leading)

                Text(summaryLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            if slotIndex < 9 {
                shortcutChip
            }

            Button {
                captureCurrentLayout()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "camera.viewfinder")
                    Text("Capture Windows")
                }
                .fixedSize()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("Capture the visible app windows on the active macOS desktop into the selected desktop")

            Button {
                onActivate(config)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("Run")
                        .fontWeight(.semibold)
                }
                .padding(.horizontal, 4)
                .fixedSize()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .help("Activate this configuration now")
        }
    }

    private var shortcutChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "command")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            KeyboardShortcuts.Recorder("Shortcut", name: .spaceSlot(slotIndex))
                .labelsHidden()
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var summaryLine: String {
        let d = config.desktops.count
        let a = config.totalAppCount
        let desktopText = d == 1 ? "1 desktop" : "\(d) desktops"
        let appText = a == 1 ? "1 app" : "\(a) apps"
        return "\(desktopText) · \(appText)"
    }

    // MARK: - Desktop bar

    private var desktopBar: some View {
        HStack(alignment: .center, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(config.desktops.enumerated()), id: \.element.id) { index, desktop in
                        desktopChip(desktop: desktop, index: index)
                    }

                    Button(action: addDesktop) {
                        Label("Add Desktop", systemImage: "plus")
                            .labelStyle(.iconOnly)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .help("Add another desktop to this configuration")
                }
                .padding(.vertical, 2)
            }

            Spacer(minLength: 0)

            if let index = selectedDesktopIndex {
                renameField(for: index)
            }
        }
    }

    private func desktopChip(desktop: DesktopLayout, index: Int) -> some View {
        let selected = desktop.id == resolvedSelectedDesktopID
        return Button {
            selectedDesktopID = desktop.id
        } label: {
            HStack(spacing: 6) {
                Text(desktop.name.isEmpty ? DesktopLayout.defaultName(for: index) : desktop.name)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                if desktop.appLayouts.count > 0 {
                    Text("\(desktop.appLayouts.count)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(selected ? Color.white.opacity(0.9) : Color.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(selected
                                      ? Color.white.opacity(0.22)
                                      : Color(nsColor: .quaternaryLabelColor).opacity(0.75))
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selected ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        selected ? Color.clear : Color(nsColor: .separatorColor),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Duplicate (Empty)") { duplicateDesktop(at: index) }
            Divider()
            Button("Move Left") { moveDesktop(from: index, by: -1) }
                .disabled(index == 0)
            Button("Move Right") { moveDesktop(from: index, by: 1) }
                .disabled(index >= config.desktops.count - 1)
            Divider()
            Button("Delete", role: .destructive) { deleteDesktop(at: index) }
                .disabled(config.desktops.count <= 1)
        }
    }

    private func renameField(for index: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            TextField(
                DesktopLayout.defaultName(for: index),
                text: Binding(
                    get: {
                        guard config.desktops.indices.contains(index) else { return "" }
                        return config.desktops[index].name
                    },
                    set: { newValue in
                        guard config.desktops.indices.contains(index) else { return }
                        config.desktops[index].name = newValue
                    }
                )
            )
            .textFieldStyle(.plain)
            .frame(minWidth: 120, idealWidth: 160, maxWidth: 220)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private var resolvedSelectedDesktopID: DesktopLayout.ID? {
        if let selectedDesktopID,
           config.desktops.contains(where: { $0.id == selectedDesktopID }) {
            return selectedDesktopID
        }
        return config.desktops.first?.id
    }

    // MARK: - Workspace

    @ViewBuilder
    private var workspace: some View {
        if connectedDisplays.isEmpty {
            ContentUnavailableView(
                "No Connected Displays",
                systemImage: "display.trianglebadge.exclamationmark",
                description: Text("Connect a display to edit window layouts.")
            )
            .frame(maxWidth: .infinity, minHeight: 400)
        } else if selectedDesktop == nil {
            ContentUnavailableView(
                "No Desktop Selected",
                systemImage: "rectangle.stack",
                description: Text("Create or select a desktop above to edit its layout.")
            )
            .frame(maxWidth: .infinity, minHeight: 400)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ConnectedDisplaysOverview(
                    displays: connectedDisplays,
                    selectedDisplayID: selectedDisplayID,
                    appCountForDisplay: appCount(for:),
                    isExpanded: false,
                    onToggleExpand: nil,
                    onSelect: { display in
                        selectedDisplayID = displaySectionIdentifier(for: display)
                    }
                )

                if let selectedDisplay {
                    DisplayLayoutWorkspace(
                        display: selectedDisplay,
                        layouts: appLayouts(for: selectedDisplay),
                        viewportHeightOverride: 600,
                        isExpanded: false,
                        onToggleExpand: nil,
                        onUpdateFrame: updateLayoutFrame,
                        onReorder: { draggedID, targetID in
                            reorderLayouts(on: selectedDisplay, moving: draggedID, after: targetID)
                        },
                        onAddApp: { app in
                            addApp(app, to: selectedDisplay)
                        },
                        onRemove: deleteLayout,
                        onCaptureCurrentDisplay: {
                            captureCurrentDisplay(on: selectedDisplay)
                        }
                    )
                }

                if let captureFeedback {
                    Label(captureFeedback.message, systemImage: captureFeedback.systemImage)
                        .font(.callout)
                        .foregroundStyle(captureFeedback.color)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(captureFeedback.color.opacity(0.12))
                        )
                }

                if unavailableLayoutCount > 0 {
                    UnavailableLayoutsNotice(
                        appCount: unavailableLayoutCount,
                        onRemove: removeUnavailableLayouts
                    )
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Desktop actions (index-based)

    private func duplicateDesktop(at index: Int) {
        guard config.desktops.indices.contains(index) else { return }
        let source = config.desktops[index]
        let duplicate = DesktopLayout(name: "\(source.name) Copy")
        let insertIndex = min(index + 1, config.desktops.count)
        config.desktops.insert(duplicate, at: insertIndex)
        selectedDesktopID = duplicate.id
        captureFeedback = source.appLayouts.isEmpty
            ? nil
            : CaptureFeedback(
                message: "Created \(duplicate.name) without apps. MagicDesktop currently restores one window per app bundle, so each app can belong to only one saved desktop.",
                kind: .warning
            )
    }

    private func moveDesktop(from index: Int, by offset: Int) {
        guard config.desktops.indices.contains(index) else { return }
        let destination = index + offset
        guard config.desktops.indices.contains(destination) else { return }
        let desktop = config.desktops.remove(at: index)
        config.desktops.insert(desktop, at: destination)
        selectedDesktopID = desktop.id
        captureFeedback = nil
    }

    private func deleteDesktop(at index: Int) {
        guard config.desktops.count > 1,
              config.desktops.indices.contains(index) else { return }
        let removedID = config.desktops[index].id
        config.desktops.remove(at: index)
        if selectedDesktopID == removedID {
            let fallbackIndex = min(index, config.desktops.count - 1)
            selectedDesktopID = config.desktops[fallbackIndex].id
        }
        captureFeedback = nil
    }

    private var selectedDesktopIndex: Int? {
        guard !config.desktops.isEmpty else { return nil }

        if let selectedDesktopID,
           let index = config.desktops.firstIndex(where: { $0.id == selectedDesktopID }) {
            return index
        }

        return config.desktops.startIndex
    }

    private var selectedDesktop: DesktopLayout? {
        guard let selectedDesktopIndex,
              config.desktops.indices.contains(selectedDesktopIndex) else { return nil }
        return config.desktops[selectedDesktopIndex]
    }

    private var selectedDesktopName: String {
        selectedDesktop?.name ?? DesktopLayout.defaultName(for: 0)
    }

    private var selectedDesktopLayouts: [AppLayout] {
        selectedDesktop?.appLayouts ?? []
    }

    private func ensureValidSelectedDesktop() {
        if config.desktops.isEmpty {
            config.desktops = [DesktopLayout()]
        }

        if let selectedDesktopID,
           config.desktops.contains(where: { $0.id == selectedDesktopID }) {
            return
        }

        selectedDesktopID = config.desktops.first?.id
    }

    private func updateSelectedDesktop(_ update: (inout DesktopLayout) -> Void) {
        guard let selectedDesktopIndex,
              config.desktops.indices.contains(selectedDesktopIndex) else { return }
        update(&config.desktops[selectedDesktopIndex])
    }

    private func replaceSelectedDesktopLayouts(_ layouts: [AppLayout]) {
        updateSelectedDesktop { desktop in
            desktop.appLayouts = layouts
        }
    }

    private func nextDesktopName() -> String {
        let existingNames = Set(config.desktops.map(\.name))
        var number = 1

        while existingNames.contains(DesktopLayout.defaultName(for: number - 1)) {
            number += 1
        }

        return DesktopLayout.defaultName(for: number - 1)
    }

    private func addDesktop() {
        let insertIndex = min((selectedDesktopIndex ?? (config.desktops.count - 1)) + 1, config.desktops.count)
        let desktop = DesktopLayout(name: nextDesktopName())
        config.desktops.insert(desktop, at: insertIndex)
        selectedDesktopID = desktop.id
        captureFeedback = nil
    }

    private func duplicateSelectedDesktop() {
        guard let selectedDesktopIndex,
              config.desktops.indices.contains(selectedDesktopIndex) else { return }

        let source = config.desktops[selectedDesktopIndex]
        let duplicate = DesktopLayout(name: "\(source.name) Copy")

        let insertIndex = min(selectedDesktopIndex + 1, config.desktops.count)
        config.desktops.insert(duplicate, at: insertIndex)
        selectedDesktopID = duplicate.id
        captureFeedback = source.appLayouts.isEmpty
            ? nil
            : CaptureFeedback(
                message: "Created \(duplicate.name) without apps. MagicDesktop currently restores one window per app bundle, so each app can belong to only one saved desktop.",
                kind: .warning
            )
    }

    private func deleteSelectedDesktop() {
        guard config.desktops.count > 1,
              let selectedDesktopIndex,
              config.desktops.indices.contains(selectedDesktopIndex) else { return }

        config.desktops.remove(at: selectedDesktopIndex)
        let fallbackIndex = min(selectedDesktopIndex, config.desktops.count - 1)
        selectedDesktopID = config.desktops[fallbackIndex].id
        captureFeedback = nil
    }

    private func moveSelectedDesktop(by offset: Int) {
        guard let selectedDesktopIndex,
              config.desktops.indices.contains(selectedDesktopIndex) else { return }

        let destination = selectedDesktopIndex + offset
        guard config.desktops.indices.contains(destination) else { return }

        let desktop = config.desktops.remove(at: selectedDesktopIndex)
        config.desktops.insert(desktop, at: destination)
        selectedDesktopID = desktop.id
        captureFeedback = nil
    }

    private func captureCurrentLayout() {
        guard WindowManager.ensureAccessibilityAccess(prompt: true) else {
            captureFeedback = CaptureFeedback(
                message: "Accessibility permission is required before MagicDesktop can capture window layouts.",
                kind: .warning
            )
            return
        }

        guard let activeDesktopID = activeDesktopIDForCapture() else { return }

        let workspace = NSWorkspace.shared
        var capturedLayouts: [CapturedLayout] = []

        for app in runningApplicationsForCapture(in: workspace) {
            guard let capturedLayout = captureCandidateLayout(
                for: app,
                activeDesktopID: activeDesktopID
            ) else { continue }

            capturedLayouts.append(capturedLayout)
        }

        guard !capturedLayouts.isEmpty else {
            captureFeedback = CaptureFeedback(
                message: "No standard app windows were available to capture on \(selectedDesktopName).",
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
        }.map(\.layout)

        replaceSelectedDesktopLayouts(sortedLayouts)

        let displayCount = Set(sortedLayouts.compactMap(\.display)).count
        let displaySummary = displayCount == 1 ? "1 display" : "\(displayCount) displays"
        let appSummary = sortedLayouts.count == 1 ? "1 app" : "\(sortedLayouts.count) apps"
        captureFeedback = CaptureFeedback(
            message: "Captured \(appSummary) across \(displaySummary) for \(selectedDesktopName). Reorder the list if you want a different front-to-back stacking order.",
            kind: .success
        )
    }

    private func activeDesktopIDForCapture() -> CGSSpaceID? {
        do {
            return try desktopManager.activeDesktopID()
        } catch {
            captureFeedback = CaptureFeedback(
                message: error.localizedDescription,
                kind: .warning
            )
            return nil
        }
    }

    private func captureCandidateLayout(
        for app: NSRunningApplication,
        activeDesktopID: CGSSpaceID,
        requiredDisplay: DisplayInfo? = nil
    ) -> CapturedLayout? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        guard let result = WindowManager.captureDisplayRelativeLayout(
            for: app,
            matchingWindowID: { desktopManager.isWindow($0, onDesktop: activeDesktopID) }
        ) else {
            return nil
        }

        guard result.relativeFrame.width > 0 && result.relativeFrame.height > 0 else { return nil }

        if let requiredDisplay,
           sectionDisplay(for: result.display) != requiredDisplay {
            return nil
        }

        return CapturedLayout(
            absoluteFrame: result.absoluteFrame,
            layout: AppLayout(
                bundleIdentifier: bundleID,
                appName: app.localizedName ?? bundleID,
                frame: result.relativeFrame,
                display: result.display
            )
        )
    }

    private func displaySortIndex(
        for display: DisplayInfo?,
        displayOrder: [DisplayInfo: Int]
    ) -> Int {
        guard let display else { return Int.max }
        return displayOrder[display] ?? Int.max
    }

    private func runningApplicationsForCapture(in workspace: NSWorkspace) -> [NSRunningApplication] {
        let currentAppBundleIdentifier = Bundle.main.bundleIdentifier
        let finderBundleIdentifier = "com.apple.finder"

        return workspace.runningApplications.filter { app in
            guard let bundleIdentifier = app.bundleIdentifier else { return false }
            guard bundleIdentifier != currentAppBundleIdentifier else { return false }
            guard !app.isHidden, !app.isTerminated else { return false }
            return app.activationPolicy == .regular || bundleIdentifier == finderBundleIdentifier
        }
    }

    private func sectionDisplay(for display: DisplayInfo?) -> DisplayInfo? {
        guard let display else { return nil }
        return WindowManager.connectedDisplayInfo(for: display) ?? display
    }

    private var connectedDisplays: [DisplayInfo] {
        WindowManager.currentDisplays()
    }

    private var connectedDisplayIdentifiers: [String] {
        connectedDisplays.map(displaySectionIdentifier(for:))
    }

    private var selectedDisplay: DisplayInfo? {
        guard !connectedDisplays.isEmpty else { return nil }

        if let selectedDisplayID,
           let display = connectedDisplays.first(where: { displaySectionIdentifier(for: $0) == selectedDisplayID }) {
            return display
        }

        return connectedDisplays.first(where: { appCount(for: $0) > 0 }) ?? connectedDisplays.first
    }

    private func appCount(for display: DisplayInfo) -> Int {
        appLayouts(for: display).count
    }

    private var unavailableLayoutCount: Int {
        selectedDesktopLayouts.filter { layout in
            guard let display = layout.display else { return false }
            return WindowManager.connectedDisplayInfo(for: display) == nil
        }.count
    }

    private func appLayouts(for display: DisplayInfo) -> [AppLayout] {
        selectedDesktopLayouts.filter { layout in
            sectionDisplay(for: layout.display) == display
        }
    }

    private func ensureValidSelectedDisplay() {
        guard !connectedDisplays.isEmpty else {
            selectedDisplayID = nil
            return
        }

        if let selectedDisplayID,
           connectedDisplays.contains(where: { displaySectionIdentifier(for: $0) == selectedDisplayID }) {
            return
        }

        selectedDisplayID = displaySectionIdentifier(
            for: connectedDisplays.first(where: { appCount(for: $0) > 0 }) ?? connectedDisplays[0]
        )
    }

    private func removeUnavailableLayouts() {
        replaceSelectedDesktopLayouts(
            selectedDesktopLayouts.filter { layout in
                guard let display = layout.display else { return true }
                return WindowManager.connectedDisplayInfo(for: display) != nil
            }
        )
    }

    private func deleteLayout(id: AppLayout.ID) {
        replaceSelectedDesktopLayouts(
            selectedDesktopLayouts.filter { $0.id != id }
        )
    }

    private func updateLayoutFrame(id: AppLayout.ID, frame: WindowFrame) {
        var layouts = selectedDesktopLayouts
        guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        layouts[index].frame = roundedFrame(frame)
        replaceSelectedDesktopLayouts(layouts)
    }

    private func reorderLayouts(
        on display: DisplayInfo,
        moving draggedID: AppLayout.ID,
        after targetID: AppLayout.ID?
    ) {
        var layouts = selectedDesktopLayouts
        let sectionIndices = layouts.indices.filter {
            sectionDisplay(for: layouts[$0].display) == display
        }
        guard !sectionIndices.isEmpty else { return }

        var sectionLayouts = sectionIndices.map { layouts[$0] }
        guard let sourceIndex = sectionLayouts.firstIndex(where: { $0.id == draggedID }) else { return }

        let requestedDestinationIndex: Int
        if let targetID {
            guard let targetIndex = sectionLayouts.firstIndex(where: { $0.id == targetID }) else { return }
            requestedDestinationIndex = targetIndex + 1
        } else {
            requestedDestinationIndex = 0
        }

        var destinationIndex = requestedDestinationIndex
        if sourceIndex < destinationIndex {
            destinationIndex -= 1
        }

        let clampedDestinationIndex = min(max(destinationIndex, 0), sectionLayouts.count - 1)
        guard sourceIndex != clampedDestinationIndex else { return }

        let movedLayout = sectionLayouts.remove(at: sourceIndex)
        sectionLayouts.insert(movedLayout, at: clampedDestinationIndex)

        for (offset, storageIndex) in sectionIndices.enumerated() {
            layouts[storageIndex] = sectionLayouts[offset]
        }

        replaceSelectedDesktopLayouts(layouts)
    }

    private func takeExistingLayout(bundleIdentifier: String) -> AppLayout? {
        for desktopIndex in config.desktops.indices {
            if let layoutIndex = config.desktops[desktopIndex].appLayouts.firstIndex(where: {
                $0.bundleIdentifier == bundleIdentifier
            }) {
                return config.desktops[desktopIndex].appLayouts.remove(at: layoutIndex)
            }
        }

        return nil
    }

    private func addApp(_ app: DiscoveredApp, to display: DisplayInfo) -> AppLayout.ID? {
        let frame = suggestedFrame(for: display, existingLayouts: appLayouts(for: display))
        var layout = takeExistingLayout(bundleIdentifier: app.bundleIdentifier)
            ?? AppLayout(bundleIdentifier: app.bundleIdentifier, appName: app.name)

        layout.appName = app.name
        layout.display = display
        layout.frame = frame

        var layouts = selectedDesktopLayouts.filter { $0.bundleIdentifier != app.bundleIdentifier }
        let insertionIndex = insertionIndex(for: display, in: layouts)
        layouts.insert(layout, at: insertionIndex)
        replaceSelectedDesktopLayouts(layouts)
        return layout.id
    }

    private func suggestedFrame(for display: DisplayInfo, existingLayouts: [AppLayout]) -> WindowFrame {
        let width = min(max(display.width * 0.62, 720), display.width)
        let height = min(max(display.height * 0.62, 520), display.height)
        let cascadeOffset = Double(min(existingLayouts.count, 4) * 36)
        let baseX = max((display.width - width) / 2, 0)
        let baseY = max((display.height - height) / 2, 0)
        let x = min(max(baseX + cascadeOffset, 0), max(display.width - width, 0))
        let y = min(max(baseY + cascadeOffset, 0), max(display.height - height, 0))

        return roundedFrame(
            WindowFrame(
                x: x,
                y: y,
                width: width,
                height: height
            )
        )
    }

    private func insertionIndex(for display: DisplayInfo, in layouts: [AppLayout]) -> Int {
        let displayOrder = Dictionary(
            uniqueKeysWithValues: connectedDisplays.enumerated().map { index, display in
                (displaySectionIdentifier(for: display), index)
            }
        )
        let targetOrder = displayOrder[displaySectionIdentifier(for: display)] ?? Int.max - 1

        for (index, layout) in layouts.enumerated() {
            let layoutOrder = sectionDisplay(for: layout.display)
                .flatMap { displayOrder[displaySectionIdentifier(for: $0)] } ?? Int.max
            if layoutOrder > targetOrder {
                return index
            }
        }

        return layouts.count
    }

    private func replaceLayouts(on display: DisplayInfo, with newLayouts: [AppLayout]) {
        let remainingLayouts = selectedDesktopLayouts.filter {
            sectionDisplay(for: $0.display) != display
        }
        var nextLayouts = remainingLayouts
        let insertionIndex = insertionIndex(for: display, in: nextLayouts)
        nextLayouts.insert(contentsOf: newLayouts, at: insertionIndex)
        replaceSelectedDesktopLayouts(nextLayouts)
    }

    private func captureCurrentDisplay(on display: DisplayInfo) {
        guard WindowManager.ensureAccessibilityAccess(prompt: true) else {
            captureFeedback = CaptureFeedback(
                message: "Accessibility permission is required before MagicDesktop can capture window layouts.",
                kind: .warning
            )
            return
        }

        guard let activeDesktopID = activeDesktopIDForCapture() else { return }

        let workspace = NSWorkspace.shared
        var capturedLayouts: [CapturedLayout] = []

        for app in runningApplicationsForCapture(in: workspace) {
            guard let capturedLayout = captureCandidateLayout(
                for: app,
                activeDesktopID: activeDesktopID,
                requiredDisplay: display
            ) else { continue }

            capturedLayouts.append(capturedLayout)
        }

        guard !capturedLayouts.isEmpty else {
            captureFeedback = CaptureFeedback(
                message: "No standard app windows were available on \(display.name) for \(selectedDesktopName).",
                kind: .warning
            )
            return
        }

        let sortedLayouts = capturedLayouts.sorted { lhs, rhs in
            if lhs.absoluteFrame.y != rhs.absoluteFrame.y {
                return lhs.absoluteFrame.y < rhs.absoluteFrame.y
            }

            if lhs.absoluteFrame.x != rhs.absoluteFrame.x {
                return lhs.absoluteFrame.x < rhs.absoluteFrame.x
            }

            return lhs.layout.appName.localizedStandardCompare(rhs.layout.appName) == .orderedAscending
        }.map(\.layout)

        replaceLayouts(on: display, with: sortedLayouts)

        let appSummary = sortedLayouts.count == 1 ? "1 app" : "\(sortedLayouts.count) apps"
        captureFeedback = CaptureFeedback(
            message: "Captured \(appSummary) on \(display.name) for \(selectedDesktopName). Reorder the app list on the right if you want a different front-to-back stacking order.",
            kind: .success
        )
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

private struct EditorFieldRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    init(
        label: String,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(label)
                .font(.callout.weight(.medium))
                .frame(width: 90, alignment: .leading)

            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DesktopSelectorCard: View {
    let index: Int
    let desktop: DesktopLayout
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(desktop.name)
                .font(.headline)
                .lineLimit(1)

            Text("Desktop \(index + 1)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(desktop.appLayouts.count == 1 ? "1 app" : "\(desktop.appLayouts.count) apps")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.14), in: Capsule())
                .foregroundStyle(Color.accentColor)
        }
        .padding(12)
        .frame(width: 180, height: 110, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(isSelected ? 0.24 : 0.14),
                            Color.accentColor.opacity(isSelected ? 0.08 : 0.04),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    Color.accentColor.opacity(isSelected ? 0.45 : 0.2),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ConnectedDisplaysOverview: View {
    let displays: [DisplayInfo]
    let selectedDisplayID: String?
    let appCountForDisplay: (DisplayInfo) -> Int
    let preferredHeight: CGFloat?
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?
    let onSelect: (DisplayInfo) -> Void

    private let overviewMetrics: DisplayArrangementMetrics

    init(
        displays: [DisplayInfo],
        selectedDisplayID: String?,
        appCountForDisplay: @escaping (DisplayInfo) -> Int,
        preferredHeight: CGFloat? = nil,
        isExpanded: Bool = false,
        onToggleExpand: (() -> Void)? = nil,
        onSelect: @escaping (DisplayInfo) -> Void
    ) {
        self.displays = displays
        self.selectedDisplayID = selectedDisplayID
        self.appCountForDisplay = appCountForDisplay
        self.preferredHeight = preferredHeight
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
        self.onSelect = onSelect
        self.overviewMetrics = DisplayArrangementMetrics(
            displays: displays,
            padding: 20,
            targetMaxDisplayWidth: 440,
            targetMaxDisplayHeight: 180
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Display Overview")
                    .font(.headline)

                Spacer()

                Text("Click a monitor to edit it visually. Scroll horizontally to see the full arrangement.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let onToggleExpand {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Exit full-screen view" : "Expand display overview")
                }
            }

            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .controlBackgroundColor))

                    ForEach(displays, id: \.self) { display in
                        let frame = overviewMetrics.frame(for: display)

                        Button {
                            onSelect(display)
                        } label: {
                            DisplayOverviewCard(
                                display: display,
                                appCount: appCountForDisplay(display),
                                isSelected: selectedDisplayID == displaySectionIdentifier(for: display)
                            )
                        }
                        .buttonStyle(.plain)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
                .frame(
                    width: overviewMetrics.contentSize.width,
                    height: overviewMetrics.contentSize.height,
                    alignment: .topLeading
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .frame(height: overviewHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var overviewHeight: CGFloat {
        max(preferredHeight ?? 0, overviewMetrics.contentSize.height, 190)
    }
}

private struct UnavailableLayoutsNotice: View {
    let appCount: Int
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 4) {
                Text(appCount == 1 ? "1 saved app is on an unavailable display." : "\(appCount) saved apps are on unavailable displays.")
                    .font(.callout.weight(.semibold))

                Text("Reconnect those monitors and capture again, or remove the saved layouts that no longer apply.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Remove Unavailable Apps", role: .destructive, action: onRemove)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 1)
        }
    }
}

private struct DisplayOverviewCard: View {
    let display: DisplayInfo
    let appCount: Int
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(display.name)
                .font(.headline)
                .lineLimit(1)

            Text("\(Int(display.width))×\(Int(display.height))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            HStack {
                Text(appCount == 1 ? "1 app" : "\(appCount) apps")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.14), in: Capsule())
                    .foregroundStyle(Color.accentColor)

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(isSelected ? 0.24 : 0.16),
                            Color.accentColor.opacity(isSelected ? 0.08 : 0.05),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    Color.accentColor.opacity(isSelected ? 0.45 : 0.22),
                    lineWidth: isSelected ? 2 : 1
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct DisplayArrangementMetrics {
    let bounds: CGRect
    let scale: CGFloat
    let padding: CGFloat
    let contentSize: CGSize

    init(
        displays: [DisplayInfo],
        padding: CGFloat = 18,
        targetMaxDisplayWidth: CGFloat = 440,
        targetMaxDisplayHeight: CGFloat = 180,
        maxScale: CGFloat = 0.24
    ) {
        let bounds = arrangementBounds(for: displays)
        let width = max(bounds.width, 1)
        let height = max(bounds.height, 1)
        let widestDisplay = max(displays.map { CGFloat($0.width) }.max() ?? 0, 1)
        let tallestDisplay = max(displays.map { CGFloat($0.height) }.max() ?? 0, 1)
        let widthScale = targetMaxDisplayWidth / widestDisplay
        let heightScale = targetMaxDisplayHeight / tallestDisplay
        let scale = min(widthScale, heightScale, maxScale)

        self.bounds = bounds
        self.scale = scale
        self.padding = padding
        self.contentSize = CGSize(
            width: width * scale + (padding * 2),
            height: height * scale + (padding * 2)
        )
    }

    func frame(for display: DisplayInfo) -> CGRect {
        let originX = CGFloat(display.originX ?? 0)
        let originY = CGFloat(display.originY ?? 0)
        let width = CGFloat(display.width) * scale
        let height = CGFloat(display.height) * scale
        let x = padding + (originX - bounds.minX) * scale
        let y = padding + (bounds.maxY - (originY + CGFloat(display.height))) * scale

        return CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct DisplayLayoutWorkspace: View {
    let display: DisplayInfo
    let layouts: [AppLayout]
    let viewportHeightOverride: CGFloat?
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?
    let onUpdateFrame: (AppLayout.ID, WindowFrame) -> Void
    let onReorder: (AppLayout.ID, AppLayout.ID?) -> Void
    let onAddApp: (DiscoveredApp) -> AppLayout.ID?
    let onRemove: (AppLayout.ID) -> Void
    let onCaptureCurrentDisplay: () -> Void

    @State private var activeWindowID: AppLayout.ID?
    @State private var interaction: CanvasWindowInteraction?
    @State private var selectedNewAppBundleID = ""
    @State private var draggedLayoutID: AppLayout.ID?
    @State private var targetedSidebarLayoutID: AppLayout.ID?
    @State private var isTopSidebarDropTargeted = false
    @State private var dragResetTask: Task<Void, Never>?

    init(
        display: DisplayInfo,
        layouts: [AppLayout],
        viewportHeightOverride: CGFloat? = nil,
        isExpanded: Bool = false,
        onToggleExpand: (() -> Void)? = nil,
        onUpdateFrame: @escaping (AppLayout.ID, WindowFrame) -> Void,
        onReorder: @escaping (AppLayout.ID, AppLayout.ID?) -> Void,
        onAddApp: @escaping (DiscoveredApp) -> AppLayout.ID?,
        onRemove: @escaping (AppLayout.ID) -> Void,
        onCaptureCurrentDisplay: @escaping () -> Void
    ) {
        self.display = display
        self.layouts = layouts
        self.viewportHeightOverride = viewportHeightOverride
        self.isExpanded = isExpanded
        self.onToggleExpand = onToggleExpand
        self.onUpdateFrame = onUpdateFrame
        self.onReorder = onReorder
        self.onAddApp = onAddApp
        self.onRemove = onRemove
        self.onCaptureCurrentDisplay = onCaptureCurrentDisplay
        _activeWindowID = State(initialValue: layouts.last?.id)
    }

    var body: some View {
        VStack(spacing: 18) {
            header

            HStack(alignment: .top, spacing: 18) {
                canvas
                    .layoutPriority(1)

                sidebar
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .onChange(of: layoutIdentifiers) { _, _ in
            if let activeWindowID,
               !layouts.contains(where: { $0.id == activeWindowID }) {
                self.activeWindowID = layouts.last?.id
            }

            if !availableApps.contains(where: { $0.bundleIdentifier == selectedNewAppBundleID }) {
                selectedNewAppBundleID = ""
            }

            if let interaction,
               !layouts.contains(where: { $0.id == interaction.id }) {
                self.interaction = nil
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(displayEditorLabel(for: display))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Drag a window by its title bar, resize it from the lower-right corner, and reorder the app list on the right to control stacking for this display.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                if let onToggleExpand {
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded
                              ? "arrow.down.right.and.arrow.up.left"
                              : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.borderless)
                    .help(isExpanded ? "Exit full-screen view" : "Expand display editor")
                }

                Button("Capture Current Display") {
                    onCaptureCurrentDisplay()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var canvas: some View {
        CanvasAdaptiveContainer { availableWidth in
            let metrics = DisplayCanvasMetrics(
                display: display,
                targetMaxDisplayWidth: max(availableWidth - 48, 360)
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.black.opacity(0.16))

                RoundedRectangle(cornerRadius: 18)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(nsColor: .controlBackgroundColor),
                                Color(nsColor: .windowBackgroundColor),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: metrics.canvasSize.width, height: metrics.canvasSize.height)
                    .overlay(alignment: .topLeading) {
                        Text("\(Int(display.width))×\(Int(display.height))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    .offset(x: metrics.padding, y: metrics.padding)

                if windows.isEmpty {
                    ContentUnavailableView(
                        "No Apps on This Display",
                        systemImage: "macwindow",
                        description: Text("Add apps from the sidebar or capture the current display to start arranging this screen.")
                    )
                    .frame(width: metrics.canvasSize.width, height: metrics.canvasSize.height)
                    .offset(x: metrics.padding, y: metrics.padding)
                } else {
                    ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
                        let frame = metrics.frame(for: window.frame)

                        DisplayCanvasWindow(
                            window: window,
                            isActive: activeWindowID == window.id,
                            onSelect: { activeWindowID = window.id },
                            onMoveChanged: { value in
                                moveWindow(window.id, by: value.translation, scale: metrics.scale)
                            },
                            onMoveEnded: endInteraction,
                            onResizeChanged: { value in
                                resizeWindow(window.id, by: value.translation, scale: metrics.scale)
                            },
                            onResizeEnded: endInteraction
                        )
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .zIndex(activeWindowID == window.id ? 1000 : Double(index))
                    }
                }
            }
            .frame(
                width: metrics.contentSize.width,
                height: metrics.contentSize.height,
                alignment: .topLeading
            )
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .background {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(nsColor: .windowBackgroundColor))
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Apps on This Display")
                    .font(.headline)

                Spacer()

                Text(windows.count == 1 ? "1 app" : "\(windows.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Picker("New App", selection: $selectedNewAppBundleID) {
                    Text("Choose an app…").tag("")

                    ForEach(availableApps) { app in
                        Text(app.name).tag(app.bundleIdentifier)
                    }
                }
                .labelsHidden()

                HStack {
                    Button("Add App") {
                        addSelectedApp()
                    }
                    .disabled(selectedNewAppBundleID.isEmpty)

                    if availableApps.isEmpty {
                        Text("All discovered apps are already assigned to this display.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            DisplaySidebarDropZone(
                isTargeted: isTopSidebarDropTargeted,
                onDrop: { draggedID in
                    performSidebarDrop(draggedID, after: nil)
                },
                onTargetingChanged: { isTargeted in
                    handleSidebarDropTargetChange(isTargeted: isTargeted, after: nil)
                }
            )

            if windows.isEmpty {
                Text("No windows are assigned to this display yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(windows) { window in
                        CanvasWindowSidebarRow(
                            window: window,
                            isActive: activeWindowID == window.id,
                            isDragging: draggedLayoutID == window.id,
                            isDropTargeted: targetedSidebarLayoutID == window.id,
                            onSelect: { activeWindowID = window.id },
                            onDelete: { onRemove(window.id) },
                            onDragStarted: { beginDraggingSidebar(window.id) }
                        )
                        .contentShape(Rectangle())
                        .onDrop(
                            of: [UTType.plainText],
                            delegate: DisplaySidebarDropDelegate(
                                targetAfterID: window.id,
                                onTargetingChanged: handleSidebarDropTargetChange,
                                onDrop: performSidebarDrop
                            )
                        )
                    }
                }
            }

            Text("The app list controls stacking for this display. Later items are raised later, so they end up above earlier ones.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(16)
        .frame(width: sidebarWidth, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var sidebarWidth: CGFloat {
        isExpanded ? 320 : 280
    }

    private var windows: [CanvasLayoutWindow] {
        layouts.map(CanvasLayoutWindow.init(layout:))
    }

    private var layoutIdentifiers: [AppLayout.ID] {
        layouts.map(\.id)
    }

    private var availableApps: [DiscoveredApp] {
        InstalledApps.all.filter { app in
            !layouts.contains(where: { $0.bundleIdentifier == app.bundleIdentifier })
        }
    }

    private func moveWindow(_ id: AppLayout.ID, by translation: CGSize, scale: CGFloat) {
        activeWindowID = id

        guard scale > 0,
              let startingFrame = startingFrame(for: id, kind: .move) else {
            return
        }

        var nextFrame = startingFrame
        nextFrame.x = startingFrame.x + Double(translation.width / scale)
        nextFrame.y = startingFrame.y + Double(translation.height / scale)
        onUpdateFrame(id, clampedPosition(nextFrame))
    }

    private func resizeWindow(_ id: AppLayout.ID, by translation: CGSize, scale: CGFloat) {
        activeWindowID = id

        guard scale > 0,
              let startingFrame = startingFrame(for: id, kind: .resize) else {
            return
        }

        var nextFrame = startingFrame
        nextFrame.width = startingFrame.width + Double(translation.width / scale)
        nextFrame.height = startingFrame.height + Double(translation.height / scale)
        onUpdateFrame(id, clampedResizedFrame(nextFrame))
    }

    private func startingFrame(
        for id: AppLayout.ID,
        kind: CanvasWindowInteraction.Kind
    ) -> WindowFrame? {
        guard let currentFrame = layouts.first(where: { $0.id == id })?.frame else {
            return nil
        }

        if interaction?.id != id || interaction?.kind != kind {
            interaction = CanvasWindowInteraction(
                id: id,
                kind: kind,
                startingFrame: currentFrame
            )
        }

        return interaction?.startingFrame
    }

    private func endInteraction() {
        interaction = nil
    }

    private func clampedPosition(_ frame: WindowFrame) -> WindowFrame {
        let x: Double
        if frame.width >= display.width {
            x = 0
        } else {
            x = min(max(frame.x, 0), display.width - frame.width)
        }

        let y: Double
        if frame.height >= display.height {
            y = 0
        } else {
            y = min(max(frame.y, 0), display.height - frame.height)
        }

        return WindowFrame(
            x: x,
            y: y,
            width: frame.width,
            height: frame.height
        )
    }

    private func clampedResizedFrame(_ frame: WindowFrame) -> WindowFrame {
        let minimumWidth = min(180.0, display.width)
        let minimumHeight = min(120.0, display.height)

        let width = min(max(frame.width, minimumWidth), display.width)
        let height = min(max(frame.height, minimumHeight), display.height)
        let x = min(max(frame.x, 0), max(display.width - width, 0))
        let y = min(max(frame.y, 0), max(display.height - height, 0))

        return WindowFrame(
            x: x,
            y: y,
            width: width,
            height: height
        )
    }

    private func addSelectedApp() {
        guard let app = availableApps.first(where: { $0.bundleIdentifier == selectedNewAppBundleID }) else {
            return
        }

        if let addedID = onAddApp(app) {
            activeWindowID = addedID
        }

        selectedNewAppBundleID = ""
    }

    private func beginDraggingSidebar(_ id: AppLayout.ID) {
        dragResetTask?.cancel()
        draggedLayoutID = id
    }

    private func handleSidebarDropTargetChange(isTargeted: Bool, after targetID: AppLayout.ID?) {
        if isTargeted {
            dragResetTask?.cancel()
            targetedSidebarLayoutID = targetID
            isTopSidebarDropTargeted = targetID == nil
            return
        }

        if targetID == nil {
            if isTopSidebarDropTargeted {
                isTopSidebarDropTargeted = false
                scheduleSidebarDragResetIfNeeded()
            }
            return
        }

        if targetedSidebarLayoutID == targetID {
            targetedSidebarLayoutID = nil
            scheduleSidebarDragResetIfNeeded()
        }
    }

    private func scheduleSidebarDragResetIfNeeded() {
        dragResetTask?.cancel()

        guard draggedLayoutID != nil else { return }

        dragResetTask = Task {
            try? await Task.sleep(for: .milliseconds(200))

            guard !Task.isCancelled else { return }
            await MainActor.run {
                if targetedSidebarLayoutID == nil, !isTopSidebarDropTargeted {
                    clearSidebarDragState()
                }
            }
        }
    }

    private func clearSidebarDragState() {
        dragResetTask?.cancel()
        dragResetTask = nil
        draggedLayoutID = nil
        targetedSidebarLayoutID = nil
        isTopSidebarDropTargeted = false
    }

    private func performSidebarDrop(_ draggedID: AppLayout.ID, after targetID: AppLayout.ID?) {
        onReorder(draggedID, targetID)
        clearSidebarDragState()
    }
}

private struct CanvasLayoutWindow: Identifiable {
    let id: AppLayout.ID
    let bundleIdentifier: String
    let appName: String
    var frame: WindowFrame

    init(layout: AppLayout) {
        self.id = layout.id
        self.bundleIdentifier = layout.bundleIdentifier
        self.appName = layout.appName.isEmpty ? "Unnamed App" : layout.appName
        self.frame = layout.frame
    }
}

private struct CanvasWindowInteraction {
    enum Kind {
        case move
        case resize
    }

    let id: AppLayout.ID
    let kind: Kind
    let startingFrame: WindowFrame
}

private struct DisplayCanvasMetrics {
    let scale: CGFloat
    let padding: CGFloat
    let canvasSize: CGSize
    let contentSize: CGSize

    init(
        display: DisplayInfo,
        padding: CGFloat = 24,
        targetMaxDisplayWidth: CGFloat = 1100,
        targetMaxDisplayHeight: CGFloat = 460,
        maxScale: CGFloat = 0.6
    ) {
        let width = max(CGFloat(display.width), 1)
        let height = max(CGFloat(display.height), 1)
        let horizontalScale = targetMaxDisplayWidth / width
        let verticalScale = targetMaxDisplayHeight / height
        let scale = min(horizontalScale, verticalScale, maxScale)
        let canvasSize = CGSize(width: width * scale, height: height * scale)

        self.scale = scale
        self.padding = padding
        self.canvasSize = canvasSize
        self.contentSize = CGSize(
            width: canvasSize.width + (padding * 2),
            height: canvasSize.height + (padding * 2)
        )
    }

    func frame(for windowFrame: WindowFrame) -> CGRect {
        CGRect(
            x: padding + (CGFloat(windowFrame.x) * scale),
            y: padding + (CGFloat(windowFrame.y) * scale),
            width: CGFloat(windowFrame.width) * scale,
            height: CGFloat(windowFrame.height) * scale
        )
    }
}

/// Hosts the display canvas without a `ScrollView`. Reads the available width
/// so the canvas can pick a scale that fits, then reports its intrinsic
/// height back up the view tree so the row's height matches the content.
///
/// We need the height round-trip because a bare `GeometryReader` would
/// unconditionally fill its parent's vertical space — undesirable when the
/// container lives inside an outer scroll view that should flow naturally.
private struct CanvasAdaptiveContainer<Content: View>: View {
    let content: (CGFloat) -> Content

    @State private var measuredHeight: CGFloat = 320

    init(@ViewBuilder content: @escaping (CGFloat) -> Content) {
        self.content = content
    }

    var body: some View {
        GeometryReader { geometry in
            content(geometry.size.width)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: CanvasHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
                .onPreferenceChange(CanvasHeightPreferenceKey.self) { newValue in
                    let clamped = max(newValue, 200)
                    if abs(clamped - measuredHeight) > 0.5 {
                        measuredHeight = clamped
                    }
                }
        }
        .frame(height: measuredHeight)
    }
}

private struct CanvasHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DisplayCanvasWindow: View {
    let window: CanvasLayoutWindow
    let isActive: Bool
    let onSelect: () -> Void
    let onMoveChanged: (DragGesture.Value) -> Void
    let onMoveEnded: () -> Void
    let onResizeChanged: (DragGesture.Value) -> Void
    let onResizeEnded: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            Spacer(minLength: 0)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(
                    isActive ? Color.accentColor : Color.primary.opacity(0.08),
                    lineWidth: isActive ? 2 : 1
                )
        }
        .shadow(
            color: .black.opacity(isActive ? 0.18 : 0.1),
            radius: isActive ? 16 : 10,
            y: isActive ? 6 : 4
        )
        .onTapGesture {
            onSelect()
        }
    }

    private var titleBar: some View {
        HStack(spacing: 8) {
            if let icon = InstalledApps.icon(for: window.bundleIdentifier) {
                Image(nsImage: icon)
            }

            Text(window.appName)
                .font(.callout.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.accentColor.opacity(isActive ? 0.18 : 0.12))
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(onMoveChanged)
                .onEnded { _ in onMoveEnded() }
        )
    }

    private var footer: some View {
        HStack {
            Text(positionSummary(for: window.frame))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 12)

            Spacer(minLength: 0)

            resizeHandle
        }
    }

    private var resizeHandle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.accentColor.opacity(0.18))

            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(width: 24, height: 24)
        .padding(8)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged(onResizeChanged)
                .onEnded { _ in onResizeEnded() }
        )
    }
}

private struct CanvasWindowSidebarRow: View {
    let window: CanvasLayoutWindow
    let isActive: Bool
    let isDragging: Bool
    let isDropTargeted: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onDragStarted: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            dragHandle

            Button(action: onSelect) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let icon = InstalledApps.icon(for: window.bundleIdentifier) {
                            Image(nsImage: icon)
                        }

                        Text(window.appName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)

                        Spacer(minLength: 0)
                    }

                    Text(positionSummary(for: window.frame))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundShape)
        .overlay(borderShape)
        .opacity(isDragging ? 0.4 : 1)
        .scaleEffect(isDragging ? 0.985 : 1)
        .animation(.easeInOut(duration: 0.14), value: isDragging)
        .animation(.easeInOut(duration: 0.14), value: isDropTargeted)
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                isDragging
                    ? Color.accentColor.opacity(0.12)
                    : isDropTargeted
                        ? Color.accentColor.opacity(0.08)
                        : isActive
                    ? Color.accentColor.opacity(0.12)
                    : Color(nsColor: .controlBackgroundColor)
            )
    }

    private var borderShape: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(
                isDragging
                    ? Color.accentColor.opacity(0.35)
                    : isDropTargeted
                        ? Color.accentColor.opacity(0.24)
                        : isActive
                            ? Color.accentColor.opacity(0.35)
                            : Color.clear,
                lineWidth: 1
            )
    }

    private var dragHandle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
        }
        .frame(width: 28, height: 28)
        .contentShape(Rectangle())
        .help("Drag to reorder")
        .onDrag {
            onDragStarted()
            return NSItemProvider(object: window.id.uuidString as NSString)
        } preview: {
            AppLayoutDragPreview(
                layout: AppLayout(
                    id: window.id,
                    bundleIdentifier: window.bundleIdentifier,
                    appName: window.appName,
                    frame: window.frame,
                    display: nil
                )
            )
        }
    }
}

private struct DisplaySidebarDropZone: View {
    let isTargeted: Bool
    let onDrop: (_ draggedID: AppLayout.ID) -> Void
    let onTargetingChanged: (_ isTargeted: Bool) -> Void

    var body: some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(isTargeted ? Color.accentColor : Color.secondary.opacity(0.18))
                .frame(height: isTargeted ? 5 : 1)

            Text("Drop here to move to the front")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(height: 20)
        .contentShape(Rectangle())
        .onDrop(
            of: [UTType.plainText],
            delegate: DisplaySidebarDropDelegate(
                targetAfterID: nil,
                onTargetingChanged: { isTargeted, _ in
                    onTargetingChanged(isTargeted)
                },
                onDrop: { draggedID, _ in
                    onDrop(draggedID)
                }
            )
        )
    }
}

private struct DisplaySidebarDropDelegate: DropDelegate {
    let targetAfterID: AppLayout.ID?
    let onTargetingChanged: (_ isTargeted: Bool, _ targetID: AppLayout.ID?) -> Void
    let onDrop: (_ draggedID: AppLayout.ID, _ targetID: AppLayout.ID?) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.plainText])
    }

    func dropEntered(info: DropInfo) {
        onTargetingChanged(true, targetAfterID)
    }

    func dropExited(info: DropInfo) {
        onTargetingChanged(false, targetAfterID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [UTType.plainText]).first else {
            return false
        }

        itemProvider.loadObject(ofClass: NSString.self) { object, _ in
            guard let identifier = object as? NSString,
                  let draggedID = UUID(uuidString: identifier as String) else {
                return
            }

            Task { @MainActor in
                onDrop(draggedID, targetAfterID)
            }
        }

        return true
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

private func arrangementBounds(for displays: [DisplayInfo]) -> CGRect {
    guard let firstDisplay = displays.first else {
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }

    var minX = CGFloat(firstDisplay.originX ?? 0)
    var minY = CGFloat(firstDisplay.originY ?? 0)
    var maxX = minX + CGFloat(firstDisplay.width)
    var maxY = minY + CGFloat(firstDisplay.height)

    for display in displays.dropFirst() {
        let originX = CGFloat(display.originX ?? 0)
        let originY = CGFloat(display.originY ?? 0)
        let width = CGFloat(display.width)
        let height = CGFloat(display.height)

        minX = min(minX, originX)
        minY = min(minY, originY)
        maxX = max(maxX, originX + width)
        maxY = max(maxY, originY + height)
    }

    return CGRect(
        x: minX,
        y: minY,
        width: max(maxX - minX, 1),
        height: max(maxY - minY, 1)
    )
}

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

private func roundedFrame(_ frame: WindowFrame) -> WindowFrame {
    WindowFrame(
        x: frame.x.rounded(),
        y: frame.y.rounded(),
        width: frame.width.rounded(),
        height: frame.height.rounded()
    )
}

private func positionSummary(for frame: WindowFrame) -> String {
    "x \(Int(frame.x.rounded()))  y \(Int(frame.y.rounded()))  w \(Int(frame.width.rounded()))  h \(Int(frame.height.rounded()))"
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
