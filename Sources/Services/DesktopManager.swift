import AppKit
import Foundation
import OSLog

typealias CGSConnectionID = UInt32
typealias CGSSpaceID = UInt64
typealias CGSSpaceSelector = Int32

@MainActor
final class DesktopManager {
    struct ManagedDesktop: Identifiable, Equatable {
        let id: CGSSpaceID
        let index: Int
        let name: String
        let displayIdentifier: String
    }

    enum DesktopError: LocalizedError {
        case separateSpacesEnabled
        case unavailableDesktopData
        case insufficientDesktops(required: Int, available: Int)
        case switchFailed(target: String)

        var errorDescription: String? {
            switch self {
            case .separateSpacesEnabled:
                "MagicDesktop currently supports only the shared global desktop stack. Turn off 'Displays have separate Spaces' in Desktop & Dock settings and try again."
            case .unavailableDesktopData:
                "MagicDesktop could not read the current macOS desktop stack."
            case let .insufficientDesktops(required, available):
                "This configuration needs \(required) desktops, but macOS currently has \(available) user desktop(s). Create more desktops in Mission Control and try again."
            case let .switchFailed(target):
                "MagicDesktop could not switch to \(target)."
            }
        }
    }

    private enum CGSSpaceConstants {
        static let allSpaces: CGSSpaceSelector = 7
        static let userSpaceType = 0
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MagicDesktop",
        category: "DesktopManager"
    )

    private let spacesPreferencesURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Preferences/com.apple.spaces.plist")

    func validateEnvironment() throws {
        if displaysHaveSeparateSpacesEnabled() {
            throw DesktopError.separateSpacesEnabled
        }
    }

    func currentDesktopStack() throws -> [ManagedDesktop] {
        guard let entries = CGSCopyManagedDisplaySpaces(CGSMainConnectionID()) as? [[String: Any]],
              let entry = entries.first,
              let displayIdentifier = entry["Display Identifier"] as? String,
              let spaces = entry["Spaces"] as? [[String: Any]] else {
            throw DesktopError.unavailableDesktopData
        }

        let desktops = spaces.compactMap { space -> CGSSpaceID? in
            guard (space["type"] as? Int) == CGSSpaceConstants.userSpaceType else { return nil }
            return (space["id64"] as? NSNumber)?.uint64Value
                ?? (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
        }

        guard !desktops.isEmpty else {
            throw DesktopError.unavailableDesktopData
        }

        return desktops.enumerated().map { index, spaceID in
            ManagedDesktop(
                id: spaceID,
                index: index,
                name: desktopName(for: spaceID, fallbackIndex: index),
                displayIdentifier: displayIdentifier
            )
        }
    }

    func ensureDesktopCount(_ required: Int) throws -> [ManagedDesktop] {
        let desktops = try currentDesktopStack()
        guard desktops.count >= required else {
            throw DesktopError.insufficientDesktops(required: required, available: desktops.count)
        }
        return Array(desktops.prefix(required))
    }

    func activeDesktopID() throws -> CGSSpaceID {
        let desktops = try currentDesktopStack()
        guard let displayIdentifier = desktops.first?.displayIdentifier else {
            throw DesktopError.unavailableDesktopData
        }

        let currentSpace = CGSManagedDisplayGetCurrentSpace(
            CGSMainConnectionID(),
            displayIdentifier as CFString
        )

        guard currentSpace != 0 else {
            throw DesktopError.unavailableDesktopData
        }

        return currentSpace
    }

    func renameDesktop(_ desktop: ManagedDesktop, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        logger.debug("Renaming desktop \(desktop.index + 1) spaceID=\(desktop.id) to '\(trimmed)'")
        CGSSpaceSetName(CGSMainConnectionID(), desktop.id, trimmed as CFString)
    }

    func switchToDesktop(_ desktop: ManagedDesktop, timeout: Duration = .seconds(4)) async throws {
        logger.debug("Switching to desktop \(desktop.index + 1) spaceID=\(desktop.id) display=\(desktop.displayIdentifier)")
        CGSManagedDisplaySetCurrentSpace(
            CGSMainConnectionID(),
            desktop.displayIdentifier as CFString,
            desktop.id
        )

        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            let currentSpace = CGSManagedDisplayGetCurrentSpace(
                CGSMainConnectionID(),
                desktop.displayIdentifier as CFString
            )

            if currentSpace == desktop.id,
               !CGSManagedDisplayIsAnimating(CGSMainConnectionID(), desktop.displayIdentifier as CFString) {
                return
            }

            try? await Task.sleep(for: .milliseconds(100))
        }

        throw DesktopError.switchFailed(target: desktop.name)
    }

    func moveWindow(_ windowID: CGWindowID, to desktop: ManagedDesktop) {
        let currentSpaces = windowSpaces(for: windowID)
        if currentSpaces.contains(desktop.id) {
            return
        }

        let userDesktopIDs = Set((try? currentDesktopStack().map(\.id)) ?? [])
        let removableSpaces = currentSpaces.filter { userDesktopIDs.contains($0) && $0 != desktop.id }
        let currentSpaceSummary = currentSpaces.map { String($0) }.joined(separator: ",")

        logger.debug(
            "Moving window \(windowID) to desktop \(desktop.index + 1) spaceID=\(desktop.id); currentSpaces=\(currentSpaceSummary)"
        )

        if !removableSpaces.isEmpty {
            CGSRemoveWindowsFromSpaces(
                CGSMainConnectionID(),
                [windowID] as CFArray,
                removableSpaces.map(NSNumber.init(value:)) as CFArray
            )
        }

        CGSAddWindowsToSpaces(
            CGSMainConnectionID(),
            [windowID] as CFArray,
            [NSNumber(value: desktop.id)] as CFArray
        )
    }

    func isWindow(_ windowID: CGWindowID, onDesktop desktopID: CGSSpaceID) -> Bool {
        windowSpaces(for: windowID).contains(desktopID)
    }

    private func windowSpaces(for windowID: CGWindowID) -> [CGSSpaceID] {
        guard let spaces = CGSCopySpacesForWindows(
            CGSMainConnectionID(),
            CGSSpaceConstants.allSpaces,
            [windowID] as CFArray
        ) as? [NSNumber] else {
            return []
        }

        return spaces.map(\.uint64Value)
    }

    private func desktopName(for spaceID: CGSSpaceID, fallbackIndex: Int) -> String {
        if let name = CGSSpaceCopyName(CGSMainConnectionID(), spaceID) as String? {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return DesktopLayout.defaultName(for: fallbackIndex)
    }

    private func displaysHaveSeparateSpacesEnabled() -> Bool {
        guard let data = try? Data(contentsOf: spacesPreferencesURL),
              let rawValue = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = rawValue as? [String: Any],
              let displayConfiguration = root["SpacesDisplayConfiguration"] as? [String: Any],
              let managementData = displayConfiguration["Management Data"] as? [String: Any],
              let monitors = managementData["Monitors"] as? [[String: Any]] else {
            return false
        }

        let monitorsWithDesktopStacks = monitors.filter { monitor in
            monitor["Spaces"] != nil || monitor["Current Space"] != nil
        }

        return monitorsWithDesktopStacks.count > 1
    }
}

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

@_silgen_name("CGSCopySpacesForWindows")
private func CGSCopySpacesForWindows(
    _ cid: CGSConnectionID,
    _ selector: CGSSpaceSelector,
    _ windows: CFArray
) -> CFArray?

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
private func CGSManagedDisplayGetCurrentSpace(
    _ cid: CGSConnectionID,
    _ display: CFString
) -> CGSSpaceID

@_silgen_name("CGSManagedDisplayIsAnimating")
private func CGSManagedDisplayIsAnimating(
    _ cid: CGSConnectionID,
    _ display: CFString
) -> Bool

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
private func CGSManagedDisplaySetCurrentSpace(
    _ cid: CGSConnectionID,
    _ display: CFString,
    _ space: CGSSpaceID
)

@_silgen_name("CGSSpaceCopyName")
private func CGSSpaceCopyName(
    _ cid: CGSConnectionID,
    _ space: CGSSpaceID
) -> CFString?

@_silgen_name("CGSSpaceSetName")
private func CGSSpaceSetName(
    _ cid: CGSConnectionID,
    _ space: CGSSpaceID,
    _ name: CFString
)

@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(
    _ cid: CGSConnectionID,
    _ windows: CFArray,
    _ spaces: CFArray
)

@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(
    _ cid: CGSConnectionID,
    _ windows: CFArray,
    _ spaces: CFArray
)
