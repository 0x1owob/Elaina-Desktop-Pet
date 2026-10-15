import AppKit
import CoreGraphics

struct PetBroomAnimation: Decodable {
    var frameWidth: Int
    var frameHeight: Int
    var frameCount: Int
    var order: [Int]
    var frameDurationMs: Int
    var interpolation: String
    var horizontalMirrorForLeft: Bool
    var isValid: Bool {
        frameWidth == 693 && frameHeight == 693 && frameCount == 4 && order == [0, 1, 2, 3] &&
            frameDurationMs == 180 && interpolation == "nearest" && horizontalMirrorForLeft
    }
}

enum PetFullscreenGeometry {
    /// CGWindow bounds use a top-left origin; AppKit screens use a bottom-left origin.
    static func quartzFrame(_ appKitFrame: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: appKitFrame.minX, y: primaryHeight - appKitFrame.maxY,
               width: appKitFrame.width, height: appKitFrame.height)
    }

    static func coversScreen(_ window: CGRect, screen: CGRect, tolerance: CGFloat = 2) -> Bool {
        guard !window.isEmpty, !screen.isEmpty else { return false }
        // Deliberately conservative: a visibleFrame maximization should not match the full frame.
        return abs(window.minX - screen.minX) <= tolerance &&
            abs(window.minY - screen.minY) <= tolerance &&
            abs(window.maxX - screen.maxX) <= tolerance &&
            abs(window.maxY - screen.maxY) <= tolerance
    }

    static func escapeOrigin(home: CGPoint, size: CGSize, screen: CGRect) -> CGPoint {
        let left = home.x + size.width / 2 < screen.midX
        return CGPoint(x: left ? screen.minX - size.width - 16 : screen.maxX + 16,
                       y: min(screen.maxY - size.height, home.y + 100))
    }
}

/// A coverage heuristic, not a guaranteed API for fullscreen state in every application.
/// It reads owner PID, layer, alpha and geometry only; never window names or content.
enum PetFullscreenDetector {
    static func covers(_ screen: NSScreen) -> Bool? {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return nil }
        let frame = PetFullscreenGeometry.quartzFrame(screen.frame,
                          primaryHeight: CGDisplayBounds(CGMainDisplayID()).height)
        return windows.contains { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) == front.processIdentifier,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return false }
            return PetFullscreenGeometry.coversScreen(rect, screen: frame)
        }
    }
}
