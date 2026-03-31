import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class BuildInstallService {
    struct AppVersion: Equatable {
        let shortVersion: String
        let buildVersion: String

        var displayString: String {
            "\(shortVersion) (\(buildVersion))"
        }
    }

    enum State: Equatable {
        case idle
        case building(String)
        case installing
        case failed(String)
    }

    private struct BuildInstallError: LocalizedError {
        let message: String
        let outputSnippet: String?

        var errorDescription: String? {
            message
        }
    }

    private static let repositoryPathDefaultsKey = "buildInstall.repositoryPath"
    private static let installAppURL = URL(fileURLWithPath: "/Applications/MagicDesktop.app", isDirectory: true)

    private(set) var state: State = .idle
    private(set) var repositoryURL: URL
    private(set) var lastOutputSnippet: String?
    private(set) var runningVersion: AppVersion?
    private(set) var repositoryVersion: AppVersion?
    private(set) var installedVersion: AppVersion?

    init(repositoryURL: URL? = nil) {
        if let repositoryURL {
            self.repositoryURL = repositoryURL.standardizedFileURL
        } else if let savedPath = UserDefaults.standard.string(forKey: Self.repositoryPathDefaultsKey),
                  !savedPath.isEmpty {
            self.repositoryURL = URL(fileURLWithPath: savedPath).standardizedFileURL
        } else {
            self.repositoryURL = Self.defaultRepositoryURL
        }

        self.runningVersion = Self.version(atBundleURL: Bundle.main.bundleURL)
        self.repositoryVersion = Self.version(atRepositoryURL: self.repositoryURL)
        self.installedVersion = Self.version(atBundleURL: Self.installAppURL)
    }

    var isRunning: Bool {
        switch state {
        case .building, .installing:
            true
        default:
            false
        }
    }

    var isFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    var hasValidRepository: Bool {
        Self.isValidRepository(at: repositoryURL)
    }

    var repositoryDisplayPath: String {
        let path = repositoryURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var statusMessage: String? {
        switch state {
        case .idle:
            return hasValidRepository ? "Ready to build from the selected local clone" : nil
        case .building(let step):
            return step
        case .installing:
            return "Installing…"
        case .failed(let message):
            return message
        }
    }

    func chooseRepository() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose Repo"
        panel.directoryURL = repositoryURL

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard Self.isValidRepository(at: url) else {
            lastOutputSnippet = nil
            state = .failed("Choose the MagicDesktop repository root that contains `project.yml`.")
            return
        }

        setRepositoryURL(url)
    }

    func resetRepositoryToDefault() {
        setRepositoryURL(Self.defaultRepositoryURL)
    }

    func buildLatestAndReinstall() {
        guard !isRunning else { return }
        Task { await performBuildAndReinstall() }
    }

    private func setRepositoryURL(_ url: URL) {
        repositoryURL = url.standardizedFileURL
        UserDefaults.standard.set(repositoryURL.path, forKey: Self.repositoryPathDefaultsKey)
        refreshVersionInfo()
        lastOutputSnippet = nil
        state = .idle
    }

    private func performBuildAndReinstall() async {
        refreshVersionInfo()
        lastOutputSnippet = nil

        guard Self.isValidRepository(at: repositoryURL) else {
            state = .failed("Repository path is invalid. Choose the MagicDesktop repo root first.")
            return
        }

        let buildRoot = repositoryURL.appendingPathComponent(".build/reinstall", isDirectory: true)

        do {
            try Self.prepareBuildDirectory(at: buildRoot)

            if let xcodegenURL = Self.findXcodegen() {
                state = .building("Generating Xcode project...")
                _ = try await Self.runCommand(
                    step: "xcodegen generate",
                    executableURL: xcodegenURL,
                    arguments: ["generate"],
                    currentDirectoryURL: repositoryURL
                )
            }

            let projectURL = repositoryURL.appendingPathComponent("MagicDesktop.xcodeproj", isDirectory: true)
            guard FileManager.default.fileExists(atPath: projectURL.path) else {
                state = .failed("`MagicDesktop.xcodeproj` was not found in the selected repository.")
                return
            }

            state = .building("Building MagicDesktop...")
            _ = try await Self.runCommand(
                step: "xcodebuild",
                executableURL: URL(fileURLWithPath: "/usr/bin/xcodebuild"),
                arguments: [
                    "-project", "MagicDesktop.xcodeproj",
                    "-scheme", "MagicDesktop",
                    "-destination", "platform=macOS",
                    "-derivedDataPath", buildRoot.path,
                    "build",
                ],
                currentDirectoryURL: repositoryURL
            )

            let builtAppURL = buildRoot
                .appendingPathComponent("Build", isDirectory: true)
                .appendingPathComponent("Products", isDirectory: true)
                .appendingPathComponent("Debug", isDirectory: true)
                .appendingPathComponent("MagicDesktop.app", isDirectory: true)

            guard FileManager.default.fileExists(atPath: builtAppURL.path) else {
                state = .failed("Build completed, but the app bundle was not found at `\(builtAppURL.path)`.")
                return
            }

            state = .installing
            try Self.launchInstallerScript(from: builtAppURL, to: Self.installAppURL)

            NSApp.terminate(nil)
        } catch let error as BuildInstallError {
            lastOutputSnippet = error.outputSnippet
            state = .failed(error.errorDescription ?? "Build and re-install failed.")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func refreshVersionInfo() {
        runningVersion = Self.version(atBundleURL: Bundle.main.bundleURL)
        repositoryVersion = Self.version(atRepositoryURL: repositoryURL)
        installedVersion = Self.version(atBundleURL: Self.installAppURL)
    }

    private nonisolated static var defaultRepositoryURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Services
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // repo root
            .standardizedFileURL
    }

    private nonisolated static func version(atBundleURL url: URL) -> AppVersion? {
        guard
            let bundle = Bundle(url: url),
            let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return nil
        }
        return AppVersion(shortVersion: shortVersion, buildVersion: buildVersion)
    }

    private nonisolated static func version(atRepositoryURL url: URL) -> AppVersion? {
        let projectURL = url.appendingPathComponent("project.yml")
        guard let contents = try? String(contentsOf: projectURL, encoding: .utf8) else { return nil }
        guard
            let shortVersion = firstMatch(for: #"MARKETING_VERSION:\s*"?(.*?)"?\s*$"#, in: contents),
            let buildVersion = firstMatch(for: #"CURRENT_PROJECT_VERSION:\s*"?(.*?)"?\s*$"#, in: contents)
        else {
            return nil
        }
        return AppVersion(shortVersion: shortVersion, buildVersion: buildVersion)
    }

    private nonisolated static func firstMatch(for pattern: String, in contents: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else {
            return nil
        }
        let range = NSRange(contents.startIndex..<contents.endIndex, in: contents)
        guard
            let match = regex.firstMatch(in: contents, options: [], range: range),
            let captureRange = Range(match.range(at: 1), in: contents)
        else {
            return nil
        }
        return contents[captureRange].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func isValidRepository(at url: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: url.appendingPathComponent("project.yml").path)
            && fm.fileExists(atPath: url.appendingPathComponent("Sources/App/MagicDesktopApp.swift").path)
    }

    private nonisolated static func prepareBuildDirectory(at url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private nonisolated static func findXcodegen() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/xcodegen",
            "/usr/local/bin/xcodegen",
        ]
        for candidate in candidates {
            guard FileManager.default.isExecutableFile(atPath: candidate) else { continue }
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }

    private nonisolated static func runCommand(
        step: String,
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL
    ) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.currentDirectoryURL = currentDirectoryURL

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("magicdesktop-build-\(UUID().uuidString).log")
            _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
            let outputHandle = try FileHandle(forWritingTo: outputURL)
            process.standardOutput = outputHandle
            process.standardError = outputHandle

            do {
                try process.run()
            } catch {
                try? outputHandle.close()
                try? FileManager.default.removeItem(at: outputURL)
                throw BuildInstallError(
                    message: "Failed to start `\(step)`: \(error.localizedDescription)",
                    outputSnippet: nil
                )
            }

            process.waitUntilExit()
            try? outputHandle.close()

            let outputData = (try? Data(contentsOf: outputURL)) ?? Data()
            try? FileManager.default.removeItem(at: outputURL)
            let output = String(decoding: outputData, as: UTF8.self)

            guard process.terminationStatus == 0 else {
                throw BuildInstallError(
                    message: "`\(step)` failed with exit code \(process.terminationStatus).",
                    outputSnippet: tail(output)
                )
            }

            return output
        }.value
    }

    private nonisolated static func launchInstallerScript(from sourceAppURL: URL, to installURL: URL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("magicdesktop-reinstall-\(UUID().uuidString).zsh")

        let installCommand = """
        /bin/rm -rf \(shellQuoted(installURL.path)) && /usr/bin/ditto \(shellQuoted(sourceAppURL.path)) \(shellQuoted(installURL.path)) && /usr/bin/open \(shellQuoted(installURL.path))
        """

        let privilegedInstallCommand = appleScriptEscaped(installCommand)
        let installParent = installURL.deletingLastPathComponent().path
        let currentPID = ProcessInfo.processInfo.processIdentifier

        let script = """
        #!/bin/zsh
        set -euo pipefail

        while kill -0 \(currentPID) 2>/dev/null; do
            sleep 1
        done

        if [ -w \(shellQuoted(installParent)) ]; then
            \(installCommand)
        else
            /usr/bin/osascript -e "do shell script \\"\(privilegedInstallCommand)\\" with administrator privileges"
        fi

        /bin/rm -f \(shellQuoted(scriptURL.path))
        """

        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [scriptURL.path]
        try process.run()
    }

    private nonisolated static func tail(_ output: String, lineCount: Int = 20) -> String? {
        let lines = output
            .split(whereSeparator: \.isNewline)
            .suffix(lineCount)
            .map(String.init)
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private nonisolated static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private nonisolated static func appleScriptEscaped(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
