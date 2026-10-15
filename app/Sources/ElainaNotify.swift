import Foundation

struct BridgeConfiguration: Codable {
    var originalNotify: [String]
    var appPath: String
    var statusPath: String?
}

@main
struct ElainaNotify {
    static func argument(_ flag: String) -> String? {
        guard let index = CommandLine.arguments.firstIndex(of: flag), index + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[index + 1]
    }

    static func start(_ command: [String]) -> Process? {
        guard let executable = command.first, !executable.isEmpty else { return nil }
        let process = Process()
        let resolved: String
        if executable.contains("/") { resolved = executable }
        else {
            let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":")
            guard let found = paths.map({ "\($0)/\(executable)" }).first(where: FileManager.default.isExecutableFile) else { return nil }
            resolved = found
        }
        process.executableURL = URL(fileURLWithPath: resolved)
        process.arguments = Array(command.dropFirst())
        do { try process.run(); return process }
        catch { fputs("Elaina: could not start notification command\n", stderr); return nil }
    }

    static func deliver(_ eventID: String, appPath: String) -> [String: Any] {
        let center = DistributedNotificationCenter.default()
        var response: [String: Any]?
        let observer = center.addObserver(forName: PetNotifications.acknowledgement,
                                         object: PetNotifications.object, queue: .main) { event in
            if event.userInfo?["eventID"] as? String == eventID,
               let info = event.userInfo as? [String: Any] { response = info }
        }
        defer { center.removeObserver(observer) }
        let deadline = Date().addingTimeInterval(5)
        var nextPost = Date.distantPast
        var launched = false
        let launchAt = Date().addingTimeInterval(0.35)
        while response == nil && Date() < deadline {
            if Date() >= nextPost {
                center.postNotificationName(PetNotifications.completion, object: PetNotifications.object,
                    userInfo: ["eventID": eventID, "status": "completed"], deliverImmediately: true)
                nextPost = Date().addingTimeInterval(0.25)
            }
            if !PetPreferences.isolated && !launched && Date() >= launchAt {
                launched = true
                _ = start(["/usr/bin/open", "-g", appPath])
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        }
        return response ?? ["eventID": eventID, "result": "timeout"]
    }

    static func testControl(_ command: String) -> [String: Any] {
        guard PetPreferences.isolated else { return ["result": "isolation-required"] }
        let token = UUID().uuidString
        let center = DistributedNotificationCenter.default()
        var response: [String: Any]?
        let observer = center.addObserver(forName: PetNotifications.testAcknowledgement,
            object: PetNotifications.object, queue: .main) { event in
            if event.userInfo?["token"] as? String == token,
               let info = event.userInfo as? [String: Any] { response = info }
        }
        defer { center.removeObserver(observer) }
        let deadline = Date().addingTimeInterval(5)
        var nextPost = Date.distantPast
        while response == nil && Date() < deadline {
            if Date() >= nextPost {
                center.postNotificationName(PetNotifications.testControl, object: PetNotifications.object,
                    userInfo: ["token": token, "command": command], deliverImmediately: true)
                nextPost = Date().addingTimeInterval(0.25)
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.04))
        }
        return response ?? ["result": "timeout"]
    }

    static func main() {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        var configuration = BridgeConfiguration(originalNotify: [],
            appPath: executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().path)
        if let path = argument("--config") {
            do { configuration = try JSONDecoder().decode(BridgeConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: path))) }
            catch { fputs("Elaina: invalid bridge configuration\n", stderr); exit(1) }
        }
        if let app = argument("--app") { configuration.appPath = app }
        var original: Process?
        let originalDeadline = Date().addingTimeInterval(6)
        let eventID: String?
        if let command = argument("--test-control") {
            let result = testControl(command)
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
               let output = String(data: data, encoding: .utf8) { print(output) }
            exit(result["result"] as? String == "timeout" ? 2 : 0)
        }
        if let raw = argument("--codex") {
            // Forward the exact payload to the existing notifier, including events the pet ignores.
            if !configuration.originalNotify.isEmpty { original = start(configuration.originalNotify + [raw]) }
            let event = raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            eventID = event.flatMap(PetNotifications.eventID)
        } else {
            eventID = argument("--event-id") ?? UUID().uuidString
        }
        var result: [String: Any]
        if let eventID, !eventID.isEmpty, eventID.utf8.count < 600 {
            let preferences = UserDefaults(suiteName: ProcessInfo.processInfo.environment["ELAINA_DEFAULTS_SUITE"] ?? PetNotifications.object)
            if preferences?.object(forKey: "completionNotifications") != nil && preferences?.bool(forKey: "completionNotifications") == false {
                result = ["eventID": eventID, "result": "suppressed"]
            } else {
                result = deliver(eventID, appPath: configuration.appPath)
            }
        } else {
            result = ["result": "ignored"]
        }
        while original?.isRunning == true && Date() < originalDeadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        // A slow existing notifier may continue independently; never terminate it.
        result["timestamp"] = ISO8601DateFormatter().string(from: Date())
        if let path = configuration.statusPath {
            // Save delivery metadata only. Conversation text never enters the pet or this status file.
            var metadata = result
            metadata.removeValue(forKey: "message")
            if let data = try? JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
            }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let output = String(data: data, encoding: .utf8) { print(output) }
        if result["result"] as? String == "timeout" { exit(2) }
    }
}
