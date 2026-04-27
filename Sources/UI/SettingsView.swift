import Observation
import SwiftUI

/// Historical enum kept so `MenuBarController` can still pre-select a destination
/// when opening the settings window. Internally mapped to a `SidebarDestination`.
enum SettingsTab: Hashable {
    case configurations
    case buildInstall
}

@MainActor
@Observable
final class SettingsNavigationModel {
    var selectedTab: SettingsTab = .configurations
}

/// A single selectable row in the settings sidebar.
private enum SidebarDestination: Hashable {
    case configuration(SpaceConfiguration.ID)
    case buildInstall
    case diagnostics
}

/// Root of the settings window.
///
/// Replaces the previous two-tab layout (Configurations / Build) with a single
/// `NavigationSplitView`. The sidebar groups user configurations at the top and
/// exposes "Build & Install" as a peer destination in a separate "System" section.
struct SettingsView: View {
    let navigation: SettingsNavigationModel
    @Bindable var store: ConfigurationStore
    let onActivate: (SpaceConfiguration) -> Void

    @State private var selection: SidebarDestination?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var navigation = navigation

        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 1120, minHeight: 720)
        .onAppear {
            syncSelection(with: navigation.selectedTab, force: true)
        }
        .onChange(of: navigation.selectedTab) { _, newValue in
            syncSelection(with: newValue, force: true)
        }
        .onChange(of: store.configurations.map(\.id)) { _, _ in
            // If the selected configuration was deleted, fall back to the first one.
            if case .configuration(let id) = selection,
               !store.configurations.contains(where: { $0.id == id }) {
                selection = store.configurations.first.map { .configuration($0.id) }
            }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            Section {
                ForEach(Array(store.configurations.enumerated()), id: \.element.id) { _, config in
                    ConfigurationSidebarRow(config: config)
                        .tag(SidebarDestination.configuration(config.id))
                }
                .onDelete(perform: deleteConfigurations)

                Button(action: addConfiguration) {
                    Label("New Configuration", systemImage: "plus")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
            } header: {
                sectionHeader("Configurations")
            }

            Section {
                Label {
                    Text("Build & Install")
                } icon: {
                    Image(systemName: "hammer")
                }
                .tag(SidebarDestination.buildInstall)
                .padding(.vertical, 2)

                Label {
                    Text("Diagnostics")
                } icon: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .tag(SidebarDestination.diagnostics)
                .padding(.vertical, 2)
            } header: {
                sectionHeader("System")
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: SidebarDestination.self) { ids in
            if let id = ids.first, case .configuration(let configID) = id {
                Button("Duplicate") {
                    duplicateConfiguration(id: configID)
                }
                Button("Delete", role: .destructive) {
                    if selection == .configuration(configID) {
                        selection = nil
                    }
                    store.remove(id: configID)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
            .padding(.top, 4)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.3x3")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 0) {
                Text("MagicDesktop")
                    .font(.system(size: 12, weight: .semibold))
                Text("Menu bar companion")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.bar)
    }

    // MARK: Detail routing

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .configuration(let id):
            if let index = store.configurations.firstIndex(where: { $0.id == id }) {
                ConfigurationEditorView(
                    config: Binding(
                        get: {
                            let current = store.configurations
                            guard current.indices.contains(index),
                                  current[index].id == id else {
                                return current.first(where: { $0.id == id }) ?? SpaceConfiguration()
                            }
                            return current[index]
                        },
                        set: { store.update($0) }
                    ),
                    slotIndex: index,
                    onActivate: onActivate
                )
                .id(id)
            } else {
                emptyState(
                    title: "Configuration not found",
                    systemImage: "exclamationmark.triangle"
                )
            }
        case .buildInstall:
            BuildInstallPane()
        case .diagnostics:
            DiagnosticsPane()
        case .none:
            emptyState(
                title: store.configurations.isEmpty ? "No configurations yet" : "Select a configuration",
                systemImage: "rectangle.split.3x3",
                description: store.configurations.isEmpty
                    ? "Create your first layout to get started."
                    : nil
            )
        }
    }

    @ViewBuilder
    private func emptyState(
        title: String,
        systemImage: String,
        description: String? = nil
    ) -> some View {
        if let description {
            ContentUnavailableView(
                title,
                systemImage: systemImage,
                description: Text(description)
            )
        } else {
            ContentUnavailableView(title, systemImage: systemImage)
        }
    }

    // MARK: Helpers

    private func syncSelection(with tab: SettingsTab, force: Bool) {
        switch tab {
        case .configurations:
            let alreadyOnConfiguration: Bool
            if case .configuration = selection { alreadyOnConfiguration = true } else { alreadyOnConfiguration = false }
            if force || !alreadyOnConfiguration {
                selection = store.configurations.first.map { .configuration($0.id) }
            }
        case .buildInstall:
            selection = .buildInstall
        }
    }

    private func addConfiguration() {
        let config = SpaceConfiguration()
        store.add(config)
        selection = .configuration(config.id)
    }

    private func duplicateConfiguration(id: SpaceConfiguration.ID) {
        guard let source = store.configurations.first(where: { $0.id == id }) else { return }
        let copy = SpaceConfiguration(
            id: UUID(),
            name: "\(source.name) Copy",
            desktops: source.desktops.map { desktop in
                DesktopLayout(
                    id: UUID(),
                    name: desktop.name,
                    appLayouts: desktop.appLayouts.map { layout in
                        var new = layout
                        new.id = UUID()
                        return new
                    }
                )
            }
        )
        store.add(copy)
        selection = .configuration(copy.id)
    }

    private func deleteConfigurations(at offsets: IndexSet) {
        let ids = offsets.compactMap { offset -> SpaceConfiguration.ID? in
            guard store.configurations.indices.contains(offset) else { return nil }
            return store.configurations[offset].id
        }
        store.remove(at: offsets)
        if case .configuration(let currentID) = selection, ids.contains(currentID) {
            selection = store.configurations.first.map { .configuration($0.id) }
        }
    }
}

// MARK: - Sidebar Row

private struct ConfigurationSidebarRow: View {
    let config: SpaceConfiguration

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.split.3x3.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(config.name.isEmpty ? "Untitled" : config.name)
                    .font(.body)
                    .lineLimit(1)
                Text(summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private var summary: String {
        let d = config.desktops.count
        let a = config.totalAppCount
        let desktopText = d == 1 ? "1 desktop" : "\(d) desktops"
        let appText = a == 1 ? "1 app" : "\(a) apps"
        return "\(desktopText) · \(appText)"
    }
}

// MARK: - Build & Install Pane

private struct BuildInstallPane: View {
    @State private var buildService = BuildInstallService()
    @State private var outputExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                card {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Source")

                        LabeledContent("Local clone") {
                            Text(buildService.repositoryDisplayPath)
                                .font(.system(.body, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        HStack(spacing: 8) {
                            Button("Choose…") { buildService.chooseRepository() }
                            Button("Reset to Default") { buildService.resetRepositoryToDefault() }
                            Spacer()
                        }
                        .controlSize(.regular)
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Versions")

                        versionRow(label: "Running", value: buildService.runningVersion?.displayString)
                        Divider().opacity(0.4)
                        versionRow(label: "Repository", value: buildService.repositoryVersion?.displayString)
                        Divider().opacity(0.4)
                        versionRow(label: "Installed", value: buildService.installedVersion?.displayString)
                    }
                }

                card {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Build")

                        Button {
                            buildService.buildLatestAndReinstall()
                        } label: {
                            HStack(spacing: 10) {
                                if buildService.isRunning {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "hammer.fill")
                                }
                                Text(buildService.isRunning
                                     ? "Building & Installing…"
                                     : "Build Latest & Re-install")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(buildService.isRunning || !buildService.hasValidRepository)

                        if let message = buildService.statusMessage {
                            statusLine(message)
                        }

                        if let snippet = buildService.lastOutputSnippet {
                            DisclosureGroup(isExpanded: $outputExpanded) {
                                ScrollView {
                                    Text(snippet)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                        .padding(8)
                                }
                                .frame(maxHeight: 200)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(nsColor: .textBackgroundColor).opacity(0.6))
                                )
                            } label: {
                                Label("Diagnostic Output", systemImage: "text.alignleft")
                                    .font(.callout)
                            }
                        }
                    }
                }

                Text("Builds the current local clone, installs MagicDesktop to /Applications, then quits and relaunches. After relaunch, the running and installed versions should match the repo version. macOS may prompt for permission to update /Applications.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Build & Install")
                .font(.system(size: 22, weight: .semibold))
            Text("Rebuild MagicDesktop from your local repository and replace the copy in /Applications.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    @ViewBuilder
    private func versionRow(label: String, value: String?) -> some View {
        LabeledContent(label) {
            Text(value ?? "—")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(value == nil ? .tertiary : .primary)
        }
    }

    @ViewBuilder
    private func statusLine(_ message: String) -> some View {
        HStack(spacing: 8) {
            switch buildService.state {
            case .idle:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .building, .installing:
                ProgressView().controlSize(.small)
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(buildService.isFailed ? .red : .secondary)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}

// MARK: - Diagnostics Pane

private struct DiagnosticsPane: View {
    @State private var diagnosticService = DiagnosticLogService()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                card {
                    VStack(alignment: .leading, spacing: 14) {
                        sectionTitle("Logs")

                        Button {
                            diagnosticService.captureFullLogs()
                        } label: {
                            HStack(spacing: 10) {
                                if diagnosticService.isCapturing {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "doc.text.magnifyingglass")
                                }
                                Text(diagnosticService.isCapturing ? "Capturing Logs..." : "Capture Full Logs")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(diagnosticService.isCapturing)

                        if let message = diagnosticService.statusMessage {
                            statusLine(message)
                        }
                    }
                }

                Text("Creates a timestamped diagnostics report on the Desktop and reveals it in Finder. The report includes MagicDesktop unified logs, Spaces preferences, display information, app versions, process details, and the saved configuration JSON.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Diagnostics")
                .font(.system(size: 22, weight: .semibold))
            Text("Capture MagicDesktop logs and local state for troubleshooting.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    @ViewBuilder
    private func statusLine(_ message: String) -> some View {
        HStack(spacing: 8) {
            switch diagnosticService.state {
            case .idle:
                EmptyView()
            case .capturing:
                ProgressView().controlSize(.small)
            case .completed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed:
                Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
            }

            Text(message)
                .font(.callout)
                .foregroundStyle(isFailed ? .red : .secondary)
                .lineLimit(2)
        }
    }

    private var isFailed: Bool {
        if case .failed = diagnosticService.state { return true }
        return false
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
    }
}
