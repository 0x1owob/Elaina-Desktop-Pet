import AppKit
import CoreText

@main
struct SpeechTests {
    static var results: [String] = []
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        results.append(message); print("PASS \(message)")
    }
    static func main() throws {
        guard let resources = Bundle.main.resourceURL, let font = PetSpeechMetrics.bundledFont else {
            fatalError("Test bundle failed to load the actual packaged font")
        }
        check(font.fontName == "Cubic_11" && font.pointSize == 12, "Official Cubic 11 loads at 12pt in the test process")
        let attributes = PetSpeechMetrics.attributes()
        check((attributes[.font] as? NSFont)?.fontName == font.fontName, "Drawing and measurement share the loaded face")
        check(attributes[.strokeWidth] == nil && attributes[.strokeColor] == nil && attributes[.shadow] == nil,
              "Text has no outline or shadow and remains opaque")
        check((attributes[.foregroundColor] as? NSColor)?.alphaComponent == 1, "Text opacity is independent of the bubble background")
        check(PetSpeechMetrics.loadFont(from: resources.appendingPathComponent("missing.ttf")) == nil,
              "Missing font safely permits the system-font fallback")
        let data = try Data(contentsOf: resources.appendingPathComponent("dialogues.json"))
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let thoughts = json["innerThoughts"] as! [String]
        let lines = thoughts + (json["greetings"] as! [String]) + [json["jump"] as! String]
            + (json["clickResponses"] as! [[String: Any]]).map { $0["text"] as! String }
        let ctFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        for line in lines {
            let characters = Array(line.replacingOccurrences(of: "\n", with: "").utf16)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            check(CTFontGetGlyphsForCharacters(ctFont, characters, &glyphs, characters.count),
                  "Bundled dialogue glyphs exist: \(line.replacingOccurrences(of: "\n", with: " / "))")
        }
        let fallbackSample = "𠮷𩸽😊👍🙂"
        let fallbackLine = CTLineCreateWithAttributedString(NSAttributedString(string: fallbackSample, attributes: attributes))
        var fallbackFonts: Set<String> = []
        for run in CTLineGetGlyphRuns(fallbackLine) as! [CTRun] {
            var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            check(!glyphs.isEmpty && !glyphs.contains(0), "System-supported rare CJK and emoji resolve without missing glyphs")
            let runFont = (CTRunGetAttributes(run) as NSDictionary)[kCTFontAttributeName] as! CTFont
            fallbackFonts.insert(CTFontCopyPostScriptName(runFont) as String)
        }
        check(fallbackFonts.contains(where: { $0 != font.fontName }), "Absent Cubic glyphs use the native font cascade")
        let custom = "旅途，還很長呢。！？「伊蕾娜」\n𠮷𩸽 😊👍🙂"
        let long = String(repeating: "旅途還很長呢。「伊蕾娜」🙂 ", count: 35)
        var layouts: [[String: Any]] = []
        for text in lines + [custom, long, String(repeating: "Elaina", count: 60)] {
            for screen in [CGSize(width: 390, height: 650), CGSize(width: 1200, height: 850)] {
                let size = PetSpeechMetrics.size(text, maximumWidth: screen.width, maximumHeight: screen.height)
                let frame = PetSpeechMetrics.frame(text, in: CGRect(origin: .zero, size: size).insetBy(dx: 12, dy: 6))
                check(size.width <= screen.width - 8 && size.height <= screen.height - 8,
                      "Wrapped text fits its bubble and screen at \(Int(screen.width))pt")
                let range = CTFrameGetVisibleStringRange(frame)
                check(range.location + range.length == text.utf16.count, "Actual drawing frame includes all text without truncation")
                layouts.append(["text": text, "screenWidth": screen.width, "width": size.width, "height": size.height])
            }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render"), CommandLine.arguments.count > index + 1 {
            let output = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for scale in [1, 2] { try render(thoughts + [custom], scale: scale, output: output) }
            let evidence: [String: Any] = ["fontName": font.fontName, "pointSize": font.pointSize,
                "fallbackFonts": fallbackFonts.sorted(), "layouts": layouts, "checks": results,
                "renderedScales": [1, 2], "physicalDisplayValidation": "not performed"]
            try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
                .write(to: output.appendingPathComponent("speech-validation.json"))
        }
        print("PASS speech tests: \(results.count) checks")
    }
    static func render(_ samples: [String], scale: Int, output: URL) throws {
        let width = 1050, height = samples.count * 86 * 2 + 40
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)).fill()
        for (backgroundIndex, background) in [NSColor(calibratedWhite: 0.95, alpha: 1), NSColor(calibratedWhite: 0.12, alpha: 1)].enumerated() {
            let bottom = CGFloat((1 - backgroundIndex) * samples.count * 86)
            background.setFill(); NSRect(x: 0, y: bottom, width: CGFloat(width), height: CGFloat(samples.count * 86)).fill()
            for (row, sample) in samples.enumerated() {
                for (column, opacity) in [0.2, 0.6, 1.0].enumerated() {
                    let view = SpeechView()
                    view.message = sample; view.backgroundOpacity = opacity
                    let size = view.size(for: sample, maximumWidth: 342, maximumHeight: 80)
                    view.frame = CGRect(origin: .zero, size: size)
                    context.cgContext.saveGState()
                    context.cgContext.translateBy(x: CGFloat(column * 350) + (350 - size.width) / 2,
                                                  y: bottom + CGFloat((samples.count - 1 - row) * 86) + (86 - size.height) / 2)
                    view.draw(view.bounds)
                    context.cgContext.restoreGState()
                }
            }
        }
        let label = "Cubic 11 / 12pt — actual SpeechView — 20% / 60% / 100% — \(scale)x raster"
        (label as NSString).draw(at: CGPoint(x: 12, y: CGFloat(height - 28)),
            withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("bubble-\(scale)x.png"))
    }
}
