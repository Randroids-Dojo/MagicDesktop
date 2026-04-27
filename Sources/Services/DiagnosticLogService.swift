import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DiagnosticLogService {
    enum State: Equatable {
        case idle
        case capturing
        case completed(URL)
        case failed(String)
    }

    private(set) var state: State = .idle

    var isCapturing: Bool {
        if case .capturing = state { return true }
        return false
    }

    var statusMessage: String? {
        switch state {
        case .idle:
            nil
        case .capturing:
            "Capturing diagnostics..."
        case .completed(let url):
            "Saved \(url.lastPathComponent)"
        case .failed(let message):
            message
        }
    }

    func captureFullLogs() {
        guard !isCapturing else { return }
        state = .capturing

        Task {
            do {
                let report = try await Self.buildReport()
                let url = try Self.writeReport(report)
                NSWorkspace.shared.activateFileViewerSelecting([url])
                state = .completed(url)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private nonisolated static func buildReport() async throws -> String {
        async let logOutput = runCommand(
            executable: "/usr/bin/log",
            arguments: [
                "show",
                "--last", "24h",
                "--style", "syslog",
                "--info",
                "--debug",
                "--predicate", "(process == \"MagicDesktop\") OR (subsystem == \"com.randy.MagicDesktop\")",
            ]
        )
        async let spacesDefaults = runCommand(
            executable: "/usr/bin/defaults",
            arguments: ["read", "com.apple.spaces"]
        )
        async let displayProfile = runCommand(
            executable: "/usr/sbin/system_profiler",
            arguments: ["SPDisplaysDataType", "-detailLevel", "mini"]
        )
        async let processList = runCommand(
            executable: "/bin/ps",
            arguments: ["axo", "pid,ppid,stat,comm"]
        )

        var sections: [(String, String)] = []
        sections.append(("Summary", summary()))
        sections.append(("Bundle Versions", bundleVersions()))
        sections.append(("Screens", screens()))
        sections.append(("Saved Configurations", savedConfigurations()))
        sections.append(("Spaces Preferences", await resultText(spacesDefaults)))
        sections.append(("Display System Profile", await resultText(displayProfile)))
        sections.append(("MagicDesktop Unified Logs", await resultText(logOutput)))
        sections.append(("Process List", await resultText(processList)))

        return sections.map { title, body in
            """
            ===== \(title) =====
            \(body.trimmingCharacters(in: .whitespacesAndNewlines))
            """
        }.joined(separator: "\n\n") + "\n"
    }

    private nonisolated static func writeReport(_ report: String) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "MagicDesktop-Diagnostics-\(formatter.string(from: Date())).txt"
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        let url = desktopURL.appendingPathComponent(filename)
        try report.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private nonisolated static func resultText(_ result: Result<String, Error>) -> String {
        switch result {
        case .success(let output):
            output.isEmpty ? "(no output)" : output
        case .failure(let error):
            "Command failed: \(error.localizedDescription)"
        }
    }

    private nonisolated static func runCommand(
        executable: String,
        arguments: [String]
    ) async -> Result<String, Error> {
        await Task.detached(priority: .utility) {
            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = arguments

                let outputURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("magicdesktop-diagnostics-\(UUID().uuidString).log")
                _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
                let outputHandle = try FileHandle(forWritingTo: outputURL)
                defer {
                    try? outputHandle.close()
                    try? FileManager.default.removeItem(at: outputURL)
                }
                process.standardOutput = outputHandle
                process.standardError = outputHandle

                try process.run()
                process.waitUntilExit()
                try? outputHandle.close()

                let data = (try? Data(contentsOf: outputURL)) ?? Data()
                let output = String(decoding: data, as: UTF8.self)
                guard process.terminationStatus == 0 else {
                    throw DiagnosticError.commandFailed(
                        command: ([executable] + arguments).joined(separator: " "),
                        status: process.terminationStatus,
                        output: output
                    )
                }
                return .success(output)
            } catch {
                return .failure(error)
            }
        }.value
    }

    private nonisolated static func summary() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let host = Host.current().localizedName ?? "unknown"
        return """
        Generated: \(Date())
        Host: \(host)
        OS: \(os)
        Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")
        """
    }

    private nonisolated static func bundleVersions() -> String {
        let running = version(atBundleURL: Bundle.main.bundleURL) ?? "unknown"
        let installed = version(atBundleURL: URL(fileURLWithPath: "/Applications/MagicDesktop.app", isDirectory: true)) ?? "unknown"
        return """
        Running: \(running)
        Installed: \(installed)
        Running bundle path: \(Bundle.main.bundleURL.path)
        """
    }

    private nonisolated static func version(atBundleURL url: URL) -> String? {
        guard
            let bundle = Bundle(url: url),
            let shortVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            let buildVersion = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        else {
            return nil
        }
        return "\(shortVersion) (\(buildVersion))"
    }

    private nonisolated static func screens() -> String {
        let capture = {
            NSScreen.screens.enumerated().map { index, screen in
                let frame = screen.frame
                let visibleFrame = screen.visibleFrame
                let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] ?? "unknown"
                return """
                Screen \(index + 1):
                  name: \(screen.localizedName)
                  number: \(number)
                  frame: x=\(Int(frame.origin.x)) y=\(Int(frame.origin.y)) w=\(Int(frame.width)) h=\(Int(frame.height))
                  visible: x=\(Int(visibleFrame.origin.x)) y=\(Int(visibleFrame.origin.y)) w=\(Int(visibleFrame.width)) h=\(Int(visibleFrame.height))
                  scale: \(screen.backingScaleFactor)
                """
            }.joined(separator: "\n")
        }

        if Thread.isMainThread {
            return capture()
        }

        return DispatchQueue.main.sync(execute: capture)
    }

    private nonisolated static func savedConfigurations() -> String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let url = appSupport?
            .appendingPathComponent("MagicDesktop", isDirectory: true)
            .appendingPathComponent("configurations.json")

        guard let url else { return "Could not resolve Application Support directory." }
        guard let data = try? Data(contentsOf: url) else {
            return "No configurations file at \(url.path)"
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private struct DiagnosticError: LocalizedError {
    let command: String
    let status: Int32
    let output: String

    static func commandFailed(command: String, status: Int32, output: String) -> Self {
        Self(command: command, status: status, output: output)
    }

    var errorDescription: String? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "`\(command)` failed with exit code \(status)."
        }
        return "`\(command)` failed with exit code \(status): \(trimmed)"
    }
}
