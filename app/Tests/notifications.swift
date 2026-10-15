import Foundation

@main
struct NotificationTests {
    static func main() throws {
        let base: [String: Any] = ["type": "agent-turn-complete", "thread-id": "thread-1", "turn-id": "turn-1"]
        assert(PetNotifications.eventID(from: base) == "thread-1:turn-1")
        for status in ["failed", "interrupted", "inProgress", "waiting_for_approval"] {
            var event = base
            event["status"] = status
            assert(PetNotifications.eventID(from: event) == nil)
        }
        for type in ["approval-requested", "agent-message", "task-started"] {
            var event = base
            event["type"] = type
            assert(PetNotifications.eventID(from: event) == nil)
        }
        for key in ["thread-id", "turn-id"] {
            var event = base
            event.removeValue(forKey: key)
            assert(PetNotifications.eventID(from: event) == nil)
        }
        for message in ["沒錯，就是我。", "That's right. It's me.", "そう、私です。"] {
            let value = PetDialogues(greetings: [message], jump: message, innerThoughts: [message])
            let decoded = try JSONDecoder().decode(PetDialogues.self, from: JSONEncoder().encode(value))
            assert(decoded.greetings == [message] && decoded.innerThoughts == [message])
        }
        let legacy = Data("{\"taskCompleted\":\"legacy ignored\",\"greetings\":[\"hello\"],\"jump\":\"jump\"}".utf8)
        let old = try JSONDecoder().decode(PetDialogues.self, from: legacy)
        assert(old.innerThoughts == nil && old.greetings == ["hello"])
        let migrated = try PetDialogues.addingMissingThoughts(to: legacy)
        let migratedFields = try JSONSerialization.jsonObject(with: migrated) as! [String: Any]
        assert(migratedFields["taskCompleted"] as? String == "legacy ignored")
        let migratedValue = try JSONDecoder().decode(PetDialogues.self, from: migrated)
        assert(migratedValue.greetings == old.greetings && migratedValue.jump == old.jump)
        assert(migratedValue.innerThoughts == PetDialogues.fallback.innerThoughts)
        assert(migratedValue.clickResponses?.map(\.id) == ["C01", "C02", "C03"])
        assert(migratedValue.clickResponses?.map(\.weight) == [2, 2, 1])
        for (draw, id) in [(0.0, "C01"), (0.3999, "C01"), (0.4, "C02"), (0.7999, "C02"), (0.8, "C03"), (0.9999, "C03")] {
            assert(migratedValue.clickLine(random: draw) == migratedValue.clickResponses?.first(where: { $0.id == id })?.text)
        }
        let custom = PetDialogues(greetings: ["custom greeting"], jump: "custom jump", innerThoughts: ["custom thought"])
        let preparedCustom = try PetDialogues.addingMissingThoughts(to: JSONEncoder().encode(custom))
        let decodedCustom = try JSONDecoder().decode(PetDialogues.self, from: preparedCustom)
        assert(decodedCustom.innerThoughts == ["custom thought"])
        do {
            _ = try PetDialogues.addingMissingThoughts(to: Data("{bad json".utf8))
            fatalError("Invalid custom JSON must not be silently replaced")
        } catch { }
        let testDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("elaina-dialogues-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
        setenv("ELAINA_DATA_DIR", testDirectory.path, 1)
        defer { unsetenv("ELAINA_DATA_DIR"); try? FileManager.default.removeItem(at: testDirectory) }
        let file = testDirectory.appendingPathComponent("dialogues.json")
        try JSONEncoder().encode(custom).write(to: file)
        let original = try Data(contentsOf: file)
        PetDialogues.prepareFile()
        let backups = try FileManager.default.contentsOfDirectory(at: testDirectory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("dialogues-backup-") }
        let backupBytes = try Data(contentsOf: backups[0])
        assert(backups.count == 1 && backupBytes == original)
        assert(PetDialogues.load().innerThoughts == ["custom thought"] && PetDialogues.load().jump == "custom jump")
        PetDialogues.prepareFile()
        let afterSecondPrepare = try FileManager.default.contentsOfDirectory(atPath: testDirectory.path)
        assert(afterSecondPrepare.count == 2)
        let broken = Data("{bad json".utf8)
        try broken.write(to: file)
        PetDialogues.prepareFile()
        let afterBrokenPrepare = try Data(contentsOf: file)
        assert(afterBrokenPrepare == broken)
        assert(!PetDialogues.valid("   "))
        assert(!PetDialogues.valid(String(repeating: "魔", count: 501)))
        print("PASS completion filtering, event identity, Chinese/English/Japanese JSON round-trip, dialogue limits")
        print("PASS missing thoughts migration preserves custom fields and existing custom thoughts")
    }
}
