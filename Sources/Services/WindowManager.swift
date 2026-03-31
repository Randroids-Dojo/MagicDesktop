import AppKit
import ApplicationServices

enum WindowManager {

    // MARK: - Position & Capture

    static func positionWindow(for app: NSRunningApplication, frame: WindowFrame) {
        guard let window = targetWindow(for: app.processIdentifier) else { return }

        var position = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)

        if let posValue = AXValueCreate(.cgPoint, &position) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, posValue)
        }

        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
    }

    static func raiseWindow(for app: NSRunningApplication) {
        guard let window = targetWindow(for: app.processIdentifier) else { return }

        _ = AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        _ = AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }

    static func hasWindow(for app: NSRunningApplication) -> Bool {
        targetWindow(for: app.processIdentifier) != nil
    }

    static func captureCurrentFrame(for app: NSRunningApplication) -> WindowFrame? {
        guard let window = targetWindow(for: app.processIdentifier) else { return nil }

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

    // MARK: - Display-Aware Capture

    /// Captures a window's frame as coordinates relative to its display, plus display info.
    static func captureDisplayRelativeLayout(
        for app: NSRunningApplication
    ) -> (frame: WindowFrame, display: DisplayInfo)? {
        guard let absoluteFrame = captureCurrentFrame(for: app) else { return nil }
        let point = CGPoint(x: absoluteFrame.x, y: absoluteFrame.y)

        guard let screen = screen(containingAXPoint: point) else { return nil }
        let screenRect = axFrame(for: screen)
        let info = displayInfo(for: screen)

        let relativeFrame = WindowFrame(
            x: absoluteFrame.x - screenRect.origin.x,
            y: absoluteFrame.y - screenRect.origin.y,
            width: absoluteFrame.width,
            height: absoluteFrame.height
        )

        return (relativeFrame, info)
    }

    /// Converts a display-relative frame back to absolute AX coordinates for positioning.
    static func absoluteFrame(for frame: WindowFrame, on display: DisplayInfo) -> WindowFrame {
        guard let screen = findMatchingScreen(for: display) else { return frame }
        let screenRect = axFrame(for: screen)

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
            name: screen.localizedName,
            width: screen.frame.width,
            height: screen.frame.height
        )
    }

    static func currentDisplays() -> [DisplayInfo] {
        NSScreen.screens.map { displayInfo(for: $0) }
    }

    /// Finds the best matching current screen for a stored DisplayInfo.
    static func findMatchingScreen(for display: DisplayInfo) -> NSScreen? {
        let screens = NSScreen.screens

        // Exact match: same name and resolution
        if let match = screens.first(where: {
            $0.localizedName == display.name
                && $0.frame.width == display.width
                && $0.frame.height == display.height
        }) {
            return match
        }

        // Name match (resolution may have changed)
        if let match = screens.first(where: { $0.localizedName == display.name }) {
            return match
        }

        // Resolution match
        if let match = screens.first(where: {
            $0.frame.width == display.width && $0.frame.height == display.height
        }) {
            return match
        }

        // Fallback to main screen
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

    /// Finds which NSScreen contains the given point in AX screen coordinates.
    private static func screen(containingAXPoint point: CGPoint) -> NSScreen? {
        for screen in NSScreen.screens {
            let rect = axFrame(for: screen)
            if rect.contains(point) {
                return screen
            }
        }
        // Window center might be off-screen; find nearest screen
        return nearestScreen(to: point)
    }

    private static func nearestScreen(to point: CGPoint) -> NSScreen? {
        var best: NSScreen?
        var bestDistance = Double.infinity

        for screen in NSScreen.screens {
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

    // MARK: - AX Window

    private static func targetWindow(for pid: pid_t) -> AXUIElement? {
        let appRef = AXUIElementCreateApplication(pid)

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
}
