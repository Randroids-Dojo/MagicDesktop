import AppKit
import ApplicationServices
import CoreGraphics
import OSLog

enum WindowManager {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MagicDesktop",
        category: "WindowManager"
    )
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )

    // MARK: - Position & Capture

    @discardableResult
    static func ensureAccessibilityAccess(prompt: Bool) -> Bool {
        let trusted: Bool
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }

        if !trusted {
            logger.error("Accessibility permission is not granted for MagicDesktop. prompt=\(prompt)")
            if prompt, let accessibilitySettingsURL {
                NSWorkspace.shared.open(accessibilitySettingsURL)
            }
        }

        return trusted
    }

    static func positionAndRaiseWindow(
        for app: NSRunningApplication,
        frame targetFrame: WindowFrame,
        attempts: Int = 5
    ) async {
        let appRef = applicationElement(for: app.processIdentifier)
        logger.debug(
            "Starting move for pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "unknown") target=\(describe(targetFrame)) attempts=\(attempts)"
        )

        for attempt in 0..<attempts {
            _ = app.activate()
            let frontmostResult = setBooleanAttribute(true, for: appRef, attribute: kAXFrontmostAttribute as CFString)
            logger.debug("Attempt \(attempt + 1): activate requested; set frontmost result=\(frontmostResult.rawValue)")

            guard let window = targetWindow(for: app.processIdentifier) else {
                let summaries = windowSummaries(for: app.processIdentifier).joined(separator: " | ")
                logger.error("Attempt \(attempt + 1): no target window for pid=\(app.processIdentifier). windows=\(summaries)")
                if attempt < attempts - 1 {
                    try? await Task.sleep(for: .milliseconds(120))
                }
                continue
            }

            logger.debug("Attempt \(attempt + 1): selected window \(windowSummary(window))")

            let minimizedResult = setBooleanAttribute(false, for: window, attribute: kAXMinimizedAttribute as CFString)
            let mainResult = setBooleanAttribute(true, for: window, attribute: kAXMainAttribute as CFString)
            let focusedResult = setBooleanAttribute(true, for: window, attribute: kAXFocusedAttribute as CFString)
            let frameResults = setFrame(targetFrame, for: window)
            let raiseResult = AXUIElementPerformAction(window, kAXRaiseAction as CFString)

            logger.debug(
                "Attempt \(attempt + 1): AX results minimized=\(minimizedResult.rawValue) main=\(mainResult.rawValue) focused=\(focusedResult.rawValue) position=\(frameResults.position.rawValue) size=\(frameResults.size.rawValue) raise=\(raiseResult.rawValue)"
            )

            let actualFrame = currentFrame(for: window)
            logger.debug("Attempt \(attempt + 1): observed frame \(actualFrame.map(describe) ?? "unavailable")")

            if frameMatches(targetFrame, actual: actualFrame) {
                logger.debug("Attempt \(attempt + 1): frame matched target")
                return
            }

            if attempt < attempts - 1 {
                try? await Task.sleep(for: .milliseconds(120))
            }
        }

        logger.error(
            "Failed to move pid=\(app.processIdentifier) bundle=\(app.bundleIdentifier ?? "unknown") to target=\(describe(targetFrame)) after \(attempts) attempts"
        )
    }

    static func hasWindow(for app: NSRunningApplication) -> Bool {
        targetWindow(for: app.processIdentifier) != nil
    }

    static func captureCurrentFrame(for app: NSRunningApplication) -> WindowFrame? {
        guard let window = targetWindow(for: app.processIdentifier) else { return nil }
        return currentFrame(for: window)
    }

    private static func currentFrame(for window: AXUIElement) -> WindowFrame? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?

        AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &positionRef)
        AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)

        var position = CGPoint.zero
        var size = CGSize.zero

        if let positionRef {
            AXValueGetValue(positionRef as! AXValue, .cgPoint, &position)
        }

        if let sizeRef {
            AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        }

        return WindowFrame(
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }

    private static func frameMatches(_ expected: WindowFrame, actual: WindowFrame?, tolerance: Double = 8) -> Bool {
        guard let actual else { return false }

        return abs(expected.x - actual.x) <= tolerance
            && abs(expected.y - actual.y) <= tolerance
            && abs(expected.width - actual.width) <= tolerance
            && abs(expected.height - actual.height) <= tolerance
    }

    private static func setFrame(_ frame: WindowFrame, for window: AXUIElement) -> (position: AXError, size: AXError) {
        var position = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        var positionResult: AXError = .failure
        var sizeResult: AXError = .failure

        if let posValue = AXValueCreate(.cgPoint, &position) {
            positionResult = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }

        if let sizeValue = AXValueCreate(.cgSize, &size) {
            sizeResult = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }

        return (positionResult, sizeResult)
    }

    private static func setBooleanAttribute(
        _ value: Bool,
        for element: AXUIElement,
        attribute: CFString
    ) -> AXError {
        AXUIElementSetAttributeValue(element, attribute, value ? kCFBooleanTrue : kCFBooleanFalse)
    }

    // MARK: - Display-Aware Capture

    /// Captures a window's frame as coordinates relative to its display, plus display info.
    static func captureDisplayRelativeLayout(
        for app: NSRunningApplication
    ) -> (relativeFrame: WindowFrame, display: DisplayInfo, absoluteFrame: WindowFrame)? {
        guard let absoluteFrame = captureCurrentFrame(for: app) else { return nil }
        let windowRect = cgRect(for: absoluteFrame)

        guard let screen = screen(bestMatchingAXFrame: windowRect) else { return nil }
        let screenRect = axFrame(for: screen)
        let info = displayInfo(for: screen)

        let relativeFrame = WindowFrame(
            x: absoluteFrame.x - screenRect.origin.x,
            y: absoluteFrame.y - screenRect.origin.y,
            width: absoluteFrame.width,
            height: absoluteFrame.height
        )

        return (relativeFrame, info, absoluteFrame)
    }

    /// Converts a display-relative frame back to absolute AX coordinates for positioning.
    static func absoluteFrame(for frame: WindowFrame, on display: DisplayInfo) -> WindowFrame {
        guard let screen = findMatchingScreen(for: display) else {
            logger.error("Could not find matching screen for display=\(display.displayString); using stored frame \(describe(frame)) as absolute")
            return frame
        }

        let screenRect = axFrame(for: screen)
        logger.debug(
            "Mapping display=\(display.displayString) to screen='\(screen.localizedName)' cocoaFrame=\(NSStringFromRect(screen.frame)) axFrame=\(NSStringFromRect(screenRect))"
        )

        return WindowFrame(
            x: screenRect.origin.x + frame.x,
            y: screenRect.origin.y + frame.y,
            width: frame.width,
            height: frame.height
        )
    }

    // MARK: - Display Helpers

    static func displayInfo(for screen: NSScreen) -> DisplayInfo {
        DisplayInfo(
            uuid: displayUUID(for: screen),
            name: screen.localizedName,
            width: screen.frame.width,
            height: screen.frame.height,
            originX: screen.frame.origin.x,
            originY: screen.frame.origin.y,
            isBuiltIn: displayIdentifier(for: screen).map { CGDisplayIsBuiltin($0) != 0 }
        )
    }

    static func currentDisplays() -> [DisplayInfo] {
        sortedScreens().map(displayInfo(for:))
    }

    static func connectedDisplayInfo(for display: DisplayInfo) -> DisplayInfo? {
        strongMatchingScreen(for: display).map(displayInfo(for:))
    }

    static func isDisplayConnected(_ display: DisplayInfo) -> Bool {
        connectedDisplayInfo(for: display) != nil
    }

    /// Finds the best matching current screen for a stored DisplayInfo.
    static func findMatchingScreen(for display: DisplayInfo) -> NSScreen? {
        if let match = strongMatchingScreen(for: display) {
            return match
        }

        let screens = sortedScreens()

        if display.isBuiltIn == true,
           let builtInMatch = screens.first(where: { displayInfo(for: $0).isBuiltIn == true }) {
            return builtInMatch
        }

        if let namedMatch = screens.first(where: {
            $0.localizedName == display.name
                && roughlyMatchesSize($0.frame.size, display: display)
        }) {
            return namedMatch
        }

        if let nameOnlyMatch = screens.first(where: { $0.localizedName == display.name }) {
            return nameOnlyMatch
        }

        if let sizeMatch = screens.first(where: {
            roughlyMatchesSize($0.frame.size, display: display)
        }) {
            return sizeMatch
        }

        return screens.first
    }

    // MARK: - Coordinate Conversion

    /// Converts an NSScreen frame (Cocoa coords, bottom-left origin) to AX screen coords (top-left origin).
    private static func axFrame(for screen: NSScreen) -> CGRect {
        guard let main = NSScreen.screens.first else { return screen.frame }
        let mainHeight = main.frame.height
        return CGRect(
            x: screen.frame.origin.x,
            y: mainHeight - screen.frame.origin.y - screen.frame.height,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    /// Picks the screen that owns the largest share of a window, which is more reliable than
    /// using the top-left corner for wide or spanning windows.
    private static func screen(bestMatchingAXFrame windowRect: CGRect) -> NSScreen? {
        let screens = sortedScreens()
        var bestScreen: NSScreen?
        var bestIntersectionArea: CGFloat = 0

        for screen in screens {
            let intersection = axFrame(for: screen).intersection(windowRect)
            let area = intersection.isNull ? 0 : intersection.width * intersection.height
            if area > bestIntersectionArea {
                bestIntersectionArea = area
                bestScreen = screen
            }
        }

        if let bestScreen, bestIntersectionArea > 0 {
            return bestScreen
        }

        let center = CGPoint(x: windowRect.midX, y: windowRect.midY)
        if let containingCenter = screen(containingAXPoint: center) {
            return containingCenter
        }

        let topLeft = CGPoint(x: windowRect.minX, y: windowRect.minY)
        return nearestScreen(to: topLeft)
    }

    /// Finds which NSScreen contains the given point in AX screen coordinates.
    private static func screen(containingAXPoint point: CGPoint) -> NSScreen? {
        for screen in sortedScreens() {
            let rect = axFrame(for: screen)
            if rect.contains(point) {
                return screen
            }
        }

        return nearestScreen(to: point)
    }

    private static func nearestScreen(to point: CGPoint) -> NSScreen? {
        var best: NSScreen?
        var bestDistance = Double.infinity

        for screen in sortedScreens() {
            let rect = axFrame(for: screen)
            let clamped = CGPoint(
                x: max(rect.minX, min(point.x, rect.maxX)),
                y: max(rect.minY, min(point.y, rect.maxY))
            )
            let dx = point.x - clamped.x
            let dy = point.y - clamped.y
            let dist = dx * dx + dy * dy
            if dist < bestDistance {
                bestDistance = dist
                best = screen
            }
        }

        return best
    }

    private static func sortedScreens() -> [NSScreen] {
        NSScreen.screens.sorted {
            if $0.frame.origin.x != $1.frame.origin.x {
                return $0.frame.origin.x < $1.frame.origin.x
            }

            if $0.frame.origin.y != $1.frame.origin.y {
                return $0.frame.origin.y > $1.frame.origin.y
            }

            return $0.localizedName < $1.localizedName
        }
    }

    private static func strongMatchingScreen(for display: DisplayInfo) -> NSScreen? {
        let screens = sortedScreens()

        if let uuid = display.uuid,
           let uuidMatch = screens.first(where: { displayUUID(for: $0) == uuid }) {
            return uuidMatch
        }

        if let originX = display.originX,
           let originY = display.originY,
           let positionMatch = screens.first(where: {
               roughlyEqual($0.frame.origin.x, originX)
                   && roughlyEqual($0.frame.origin.y, originY)
                   && roughlyMatchesSize($0.frame.size, display: display)
           }) {
            return positionMatch
        }

        if display.isBuiltIn == true,
           let builtInMatch = screens.first(where: {
               displayInfo(for: $0).isBuiltIn == true
                   && roughlyMatchesSize($0.frame.size, display: display)
           }) {
            return builtInMatch
        }

        let namedMatches = screens.filter {
            $0.localizedName == display.name
                && roughlyMatchesSize($0.frame.size, display: display)
        }

        if namedMatches.count == 1 {
            return namedMatches[0]
        }

        return nil
    }

    private static func displayIdentifier(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(number.uint32Value)
    }

    private static func displayUUID(for screen: NSScreen) -> String? {
        guard let displayID = displayIdentifier(for: screen),
              let uuidRef = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }

        return CFUUIDCreateString(nil, uuidRef) as String?
    }

    private static func cgRect(for frame: WindowFrame) -> CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
    }

    private static func roughlyMatchesSize(_ size: CGSize, display: DisplayInfo, tolerance: Double = 1) -> Bool {
        roughlyEqual(size.width, display.width, tolerance: tolerance)
            && roughlyEqual(size.height, display.height, tolerance: tolerance)
    }

    private static func roughlyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 1) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    // MARK: - AX Window

    private static func applicationElement(for pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    private static func targetWindow(for pid: pid_t) -> AXUIElement? {
        let appRef = applicationElement(for: pid)

        if let focusedWindow = window(for: appRef, attribute: kAXFocusedWindowAttribute as CFString) {
            return focusedWindow
        }

        if let mainWindow = window(for: appRef, attribute: kAXMainWindowAttribute as CFString) {
            return mainWindow
        }

        return firstStandardWindow(for: appRef)
    }

    private static func window(for appRef: AXUIElement, attribute: CFString) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, attribute, &value)
        guard result == .success, let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return unsafeBitCast(value, to: AXUIElement.self)
    }

    private static func firstStandardWindow(for appRef: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return nil
        }

        let windows = axWindows(from: unsafeBitCast(value, to: CFArray.self))
        return windows.first(where: isStandardWindow) ?? windows.first
    }

    private static func axWindows(from array: CFArray) -> [AXUIElement] {
        (0..<CFArrayGetCount(array)).compactMap { index in
            let value = CFArrayGetValueAtIndex(array, index)
            let window = unsafeBitCast(value, to: CFTypeRef.self)
            guard CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
            return unsafeBitCast(window, to: AXUIElement.self)
        }
    }

    private static func isStandardWindow(_ window: AXUIElement) -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &value)
        guard result == .success, let subrole = value as? String else { return true }
        return subrole == kAXStandardWindowSubrole as String
    }

    private static func windowSummaries(for pid: pid_t) -> [String] {
        let appRef = applicationElement(for: pid)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &value)
        guard result == .success,
              let value,
              CFGetTypeID(value) == CFArrayGetTypeID() else {
            return []
        }

        return axWindows(from: unsafeBitCast(value, to: CFArray.self)).map(windowSummary)
    }

    private static func windowSummary(_ window: AXUIElement) -> String {
        let title = stringAttribute(kAXTitleAttribute as CFString, from: window) ?? "<no-title>"
        let role = stringAttribute(kAXRoleAttribute as CFString, from: window) ?? "<no-role>"
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: window) ?? "<no-subrole>"
        let frame = currentFrame(for: window).map(describe) ?? "unavailable"
        return "title='\(title)' role=\(role) subrole=\(subrole) frame=\(frame)"
    }

    private static func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let string = value as? String else { return nil }
        return string
    }

    private static func describe(_ frame: WindowFrame) -> String {
        "(x: \(Int(frame.x)), y: \(Int(frame.y)), w: \(Int(frame.width)), h: \(Int(frame.height)))"
    }
}
