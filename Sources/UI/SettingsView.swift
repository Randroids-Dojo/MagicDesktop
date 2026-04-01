import Observation
import SwiftUI

enum SettingsTab: Hashable {
    case configurations
    case buildInstall
}

@MainActor
@Observable
final class SettingsNavigationModel {
    var selectedTab: SettingsTab = .configurations
}

struct SettingsView: View {
    let navigation: SettingsNavigationModel
    let store: ConfigurationStore

    var body: some View {
        @Bindable var navigation = navigation

        TabView(selection: $navigation.selectedTab) {
            ConfigurationListView(store: store)
                .tabItem {
                    Label("Configurations", systemImage: "rectangle.split.3x3")
                }
                .tag(SettingsTab.configurations)

            BuildInstallSettingsView()
                .tabItem {
                    Label("Build", systemImage: "hammer")
                }
                .tag(SettingsTab.buildInstall)
        }
        .frame(minWidth: 820, minHeight: 540)
    }
}

private struct BuildInstallSettingsView: View {
    @State private var buildService = BuildInstallService()

    var body: some View {
        Form {
            Section {
                LabeledContent("Local Clone:") {
                    Text(buildService.repositoryDisplayPath)
                }

                LabeledContent("Running App:") {
                    Text(buildService.runningVersion?.displayString ?? "–")
                }

                LabeledContent("Repo Version:") {
                    Text(buildService.repositoryVersion?.displayString ?? "–")
                }

                LabeledContent("Installed in /Applications:") {
                    Text(buildService.installedVersion?.displayString ?? "–")
                }

                HStack {
                    Button("Choose Repo…") {
                        buildService.chooseRepository()
                    }

                    Button("Reset") {
                        buildService.resetRepositoryToDefault()
                    }

                    Spacer()

                    Button("Build Latest & Re-install") {
                        buildService.buildLatestAndReinstall()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(buildService.isRunning || !buildService.hasValidRepository)
                }

                if let statusMessage = buildService.statusMessage {
                    HStack(spacing: 6) {
                        switch buildService.state {
                        case .idle:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .building, .installing:
                            ProgressView()
                                .controlSize(.small)
                        case .failed:
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }

                        Text(statusMessage)
                            .foregroundStyle(buildService.isFailed ? .red : .green)
                    }
                }

                if let snippet = buildService.lastOutputSnippet {
                    Text(snippet)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                Text("Builds the current local clone, installs MagicDesktop to /Applications, then quits and relaunches the app. After relaunch, the running and installed versions should match the repo version. macOS may prompt for permission to update /Applications.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Build & Re-install")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
