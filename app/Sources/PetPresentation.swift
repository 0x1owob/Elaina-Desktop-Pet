import AppKit
import CoreText

enum PetSpeechMetrics {
    static let pointSize: CGFloat = 12
    static let bundledFont = loadFont(from: Bundle.main.resourceURL?.appendingPathComponent("Fonts/Cubic_11.ttf"))
    static let font = bundledFont ?? NSFont.systemFont(ofSize: pointSize, weight: .medium)

    /// Register only within this process; never install a font into the user's system.
    static func loadFont(from url: URL?) -> NSFont? {
        guard let url, FileManager.default.fileExists(atPath: url.path),
              let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let descriptor = descriptors.first,
              let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String else { return nil }
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        return NSFont(name: name, size: pointSize)
    }

    static func attributes(font: NSFont = font) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.lineSpacing = 3
        return [.font: font,
                .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.20, blue: 0.30, alpha: 1),
                .paragraphStyle: paragraph]
    }

    static func size(_ message: String, maximumWidth: CGFloat, maximumHeight: CGFloat) -> CGSize {
        let text = NSAttributedString(string: message, attributes: attributes())
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let natural = text.size().width
        let cap = max(40, maximumWidth - 8)
        var width = min(cap, max(60, min(280, ceil(natural) + 28)))
        func height(_ width: CGFloat) -> CGFloat {
            let measured = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, CFRange(location: 0, length: text.length),
                nil, CGSize(width: width - 24, height: .greatestFiniteMagnitude), nil)
            // The exact drawing engine includes native fallback and paragraph spacing.
            return max(32, ceil(measured.height) + 13)
        }
        while height(width) > maximumHeight - 8 && width < cap { width = min(cap, width + 40) }
        return CGSize(width: width, height: height(width))
    }

    static func frame(_ message: String, in rect: CGRect) -> CTFrame {
        let text = NSAttributedString(string: message, attributes: attributes())
        return CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(text),
            CFRange(location: 0, length: text.length), CGPath(rect: rect, transform: nil), nil)
    }
}

struct PetClickDelay {
    private(set) var deadline: TimeInterval?
    mutating func schedule(at now: TimeInterval, interval: TimeInterval) { deadline = now + max(0, interval) }
    mutating func cancel() { deadline = nil }
    mutating func take(at now: TimeInterval, eligible: Bool) -> Bool {
        guard let deadline, now >= deadline else { return false }
        self.deadline = nil
        return eligible
    }
}

/// A separate one-trip motion; its home is committed only by completed landing.
struct PetShortFlight {
    let home: CGPoint
    let destination: CGPoint
    let started: TimeInterval
    let duration: TimeInterval
    let amplitude: CGFloat
    init(home: CGPoint, size: CGSize, bounds: CGRect, height: CGFloat, speed: PetFlightSpeed, at now: TimeInterval) {
        self.home = home; started = now
        switch speed {
        case .slow: duration = 1.6
        case .normal: duration = 1.2
        case .fast: duration = 0.8
        }
        let left = max(0, home.x - bounds.minX)
        let right = max(0, bounds.maxX - size.width - home.x)
        let distance = min(4 * height, max(left, right))
        destination = CGPoint(x: min(max(home.x + (right >= left ? distance : -distance), bounds.minX),
                                       max(bounds.minX, bounds.maxX - size.width)),
                              y: min(max(home.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height)))
        amplitude = min(height * 0.45, max(0, bounds.maxY - size.height - max(home.y, destination.y)))
    }
    func origin(at now: TimeInterval) -> CGPoint {
        if now >= started + duration { return destination }
        let p = min(1, max(0, (now - started) / duration))
        if p >= 1 { return destination }
        if p <= 0 { return home }
        let eased = p * p * (3 - 2 * p)
        return CGPoint(x: home.x + (destination.x - home.x) * eased,
                       y: home.y + (destination.y - home.y) * eased + amplitude * CGFloat(sin(.pi * p)))
    }
    func isComplete(at now: TimeInterval) -> Bool { now >= started + duration }
}

struct PetThoughtSafety {
    var visible = true
    var paused = false
    var dragging = false
    var performing = false
    var flying = false
    var jumping = false
    var reacting = false
    var bubbleVisible = false
    var walking = false
    var canTest: Bool { visible && !paused && !dragging && !performing && !flying && !jumping && !reacting && !bubbleVisible }
    var stopsWalking: Bool { canTest && walking }
}

enum PetBubbleAppearance {
    static func restored(_ saved: Double?) -> Double {
        guard let saved, saved.isFinite, (0.2...1).contains(saved) else { return 0.6 }
        return saved
    }
    static func clamped(_ value: Double) -> Double { value.isFinite ? min(1, max(0.2, value)) : 0.6 }
}

enum PetBubbleGeometry {
    static func origin(character: CGRect, size: CGSize, bounds: CGRect) -> CGPoint {
        let gap: CGFloat = 7
        let candidates = [CGPoint(x: character.midX - size.width / 2, y: character.maxY + gap),
                          CGPoint(x: character.maxX + gap, y: character.midY - size.height / 2),
                          CGPoint(x: character.minX - gap - size.width, y: character.midY - size.height / 2),
                          CGPoint(x: character.midX - size.width / 2, y: character.minY - gap - size.height)]
        for point in candidates {
            let constrained = CGPoint(x: min(max(point.x, bounds.minX), max(bounds.minX, bounds.maxX - size.width)),
                                      y: min(max(point.y, bounds.minY), max(bounds.minY, bounds.maxY - size.height)))
            let rect = CGRect(origin: constrained, size: size)
            if bounds.contains(rect) && !rect.intersects(character) { return constrained }
        }
        return CGPoint(x: bounds.minX, y: max(bounds.minY, bounds.maxY - size.height))
    }
}
