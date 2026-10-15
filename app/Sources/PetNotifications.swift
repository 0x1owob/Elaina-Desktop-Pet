import Foundation

enum PetNotifications {
    static let object = ProcessInfo.processInfo.environment["ELAINA_IPC_CHANNEL"] ?? "local.elaina.desktop-pet"
    static let completion = Notification.Name("\(object).completion")
    static let acknowledgement = Notification.Name("\(object).acknowledgement")
    static let testControl = Notification.Name("\(object).test-control")
    static let testAcknowledgement = Notification.Name("\(object).test-acknowledgement")

    static func eventID(from event: [String: Any]) -> String? {
        guard event["type"] as? String == "agent-turn-complete" else { return nil }
        if let status = event["status"] as? String, status != "completed" { return nil }
        guard let thread = event["thread-id"] as? String, !thread.isEmpty,
              let turn = event["turn-id"] as? String, !turn.isEmpty,
              thread.utf8.count < 256, turn.utf8.count < 256 else { return nil }
        return "\(thread):\(turn)"
    }
}

enum PetPreferences {
    static let defaults = ProcessInfo.processInfo.environment["ELAINA_DEFAULTS_SUITE"]
        .flatMap(UserDefaults.init(suiteName:)) ?? .standard
    // Test controls and a second same-bundle process require all three isolation settings.
    static var isolated: Bool {
        let environment = ProcessInfo.processInfo.environment
        return ["ELAINA_IPC_CHANNEL", "ELAINA_DEFAULTS_SUITE", "ELAINA_DATA_DIR"]
            .allSatisfy { !(environment[$0] ?? "").isEmpty }
    }
}

struct PetDialogues: Codable {
    var greetings: [String]
    var jump: String
    var innerThoughts: [String]?
    struct ClickResponse: Codable {
        let id: String
        let text: String
        let weight: Int
    }
    var clickResponses: [ClickResponse]? = nil

    func clickLine(random: Double) -> String? {
        let lines = clickResponses ?? Self.fallback.clickResponses ?? []
        let total = lines.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return nil }
        var draw = min(total - 1, Int(min(1, max(0, random)) * Double(total)))
        for line in lines { if draw < line.weight { return line.text }; draw -= line.weight }
        return lines.last?.text
    }

    static let fallback = PetDialogues(
        greetings: ["旅途還很長呢。", "今天要去哪裡呢？", "我是魔女伊蕾娜。", "偶爾休息也不錯。", "一起去看看新的風景吧。"],
        jump: "出發吧！", innerThoughts: ["今天的我，也是一位相當可愛的魔女呢。", "今天的帽子也很完美呢。", "這麼從容的魔女是誰呢？\n嗯，是我。", "偶爾欣賞一下自己的旅途，也不錯。"],
        clickResponses: [ClickResponse(id: "C01", text: "嗯？怎麼了？", weight: 2),
                         ClickResponse(id: "C02", text: "找我有事嗎？", weight: 2),
                         ClickResponse(id: "C03", text: "呵呵，今天的我也很可愛吧？", weight: 1)])

    static var fileURL: URL {
        if let directory = ProcessInfo.processInfo.environment["ELAINA_DATA_DIR"], !directory.isEmpty {
            return URL(fileURLWithPath: directory).appendingPathComponent("dialogues.json")
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Codex/ElainaDesktopPet/dialogues.json")
    }

    static var legacyFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ElainaDesktopPet/dialogues.json")
    }

    static func addingMissingThoughts(to data: Data) throws -> Data {
        guard data.count < 64_000,
              var fields = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if fields["innerThoughts"] == nil || fields["innerThoughts"] is NSNull {
            fields["innerThoughts"] = fallback.innerThoughts ?? []
        }
        if fields["clickResponses"] == nil || fields["clickResponses"] is NSNull {
            let encoded = try JSONEncoder().encode(fallback.clickResponses ?? [])
            fields["clickResponses"] = try JSONSerialization.jsonObject(with: encoded)
        }
        let prepared = try JSONSerialization.data(withJSONObject: fields,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        let decoded = try JSONDecoder().decode(Self.self, from: prepared)
        guard isValid(decoded) else { throw CocoaError(.fileReadCorruptFile) }
        return prepared
    }

    static func prepareFile() {
        let url = fileURL
        do {
            let exists = FileManager.default.fileExists(atPath: url.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let bundled = Bundle.main.resourceURL.flatMap { try? Data(contentsOf: $0.appendingPathComponent("dialogues.json")) }
            let original: Data
            if exists {
                original = try Data(contentsOf: url)
            } else if ProcessInfo.processInfo.environment["ELAINA_DATA_DIR"]?.isEmpty != false,
                      FileManager.default.fileExists(atPath: legacyFileURL.path) {
                // Read the old location once; keep it intact as a recovery source.
                original = try Data(contentsOf: legacyFileURL)
            } else { original = try bundled ?? encoder.encode(fallback) }
            let prepared = try addingMissingThoughts(to: original)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if exists {
                let decoded = try JSONDecoder().decode(Self.self, from: original)
                if decoded.innerThoughts != nil && decoded.clickResponses != nil { return }
                let backup = url.deletingLastPathComponent().appendingPathComponent("dialogues-backup-\(UUID().uuidString).json")
                try original.write(to: backup, options: .atomic)
            }
            try prepared.write(to: url, options: .atomic)
        } catch { NSLog("Elaina: could not prepare dialogue file") }
    }

    static func load() -> PetDialogues {
        guard let data = try? Data(contentsOf: fileURL), data.count < 64_000,
              let value = try? JSONDecoder().decode(PetDialogues.self, from: data),
              isValid(value) else { return fallback }
        return value
    }

    static func isValid(_ value: Self) -> Bool {
        valid(value.jump) && !value.greetings.isEmpty && value.greetings.count <= 100 &&
            value.greetings.allSatisfy(valid) &&
            (value.innerThoughts.map { !$0.isEmpty && $0.count <= 100 && $0.allSatisfy(valid) } ?? true) &&
            (value.clickResponses.map { !$0.isEmpty && $0.count <= 100 && $0.allSatisfy {
                valid($0.id) && valid($0.text) && (1...10).contains($0.weight)
            } } ?? true)
    }

    static func valid(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && text.count <= 500
    }
}
