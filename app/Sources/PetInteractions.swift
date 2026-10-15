import Foundation
import CoreGraphics

/// Times and random draws are inputs so the approved boundaries are deterministic in tests.
struct PetPress {
    private(set) var started: TimeInterval?
    private(set) var grabbed = false
    private var point = CGPoint.zero
    mutating func begin(at now: TimeInterval, point: CGPoint) {
        started = now; self.point = point; grabbed = false
    }
    mutating func update(at now: TimeInterval, point: CGPoint) -> Bool {
        guard let started, !grabbed else { return false }
        if now - started >= 0.25 || hypot(point.x - self.point.x, point.y - self.point.y) > 4 {
            grabbed = true; return true
        }
        return false
    }
    mutating func finish() -> Bool { let result = grabbed; cancel(); return result }
    mutating func cancel() { started = nil; grabbed = false }
}

/// Read the live jump before transient cancellation clears it; idle/drag/resume keep their origin.
enum PetPauseBaseline {
    static func destination(paused: Bool, jumpStarted: TimeInterval?, origin: CGPoint, baseY: CGFloat) -> CGPoint? {
        guard !paused, jumpStarted != nil else { return nil }
        return CGPoint(x: origin.x, y: baseY)
    }
}

/// Exact damped-spring integration keeps drag-event and display rates independent.
struct PetHeldSway {
    static let limit = Double.pi * 4 / 180
    private(set) var angle = 0.0
    private(set) var velocity = 0.0
    private var target = 0.0
    private var filteredSpeed = 0.0
    private var time: TimeInterval?
    private var lastMovement: TimeInterval?
    private var cursorTime: TimeInterval?
    private var cursorX: CGFloat = 0
    var tilt: CGFloat { CGFloat(Self.limit * tanh(angle / Self.limit)) }

    mutating func begin(at now: TimeInterval, cursorX: CGFloat) {
        self = PetHeldSway(); time = now; cursorTime = now; self.cursorX = cursorX
    }
    mutating func move(to x: CGFloat, at now: TimeInterval) {
        advance(at: now)
        if let cursorTime, now > cursorTime {
            let speed = Double(x - cursorX) / max(1.0 / 240, now - cursorTime)
            let input = max(-600, min(600, speed))
            filteredSpeed += (1 - exp(-min(0.08, now - cursorTime) / 0.04)) * (input - filteredSpeed)
            target = filteredSpeed / 600 * 2 * Self.limit
            lastMovement = now
        }
        cursorX = x; cursorTime = now
    }
    mutating func advance(at now: TimeInterval) {
        guard let previous = time, now > previous else { return }
        // An input target expires in real time, including when no drag events arrive.
        let expiry = (lastMovement ?? -Double.greatestFiniteMagnitude) + 0.04
        if target != 0 && expiry < now {
            integrate(max(0, expiry - previous), toward: target)
            target = 0
            integrate(now - max(previous, expiry), toward: 0)
        } else { integrate(now - previous, toward: target) }
        time = now
    }
    private mutating func integrate(_ dt: TimeInterval, toward target: Double) {
        guard dt > 0 else { return }
        let damping = 24.0, frequency = sqrt(26 * 26 - damping * damping)
        let displacement = angle - target
        let b = (velocity + damping * displacement) / frequency
        let phase = frequency * dt, decay = exp(-damping * dt)
        let wave = displacement * cos(phase) + b * sin(phase)
        angle = target + decay * wave
        velocity = decay * (-damping * wave + frequency * (-displacement * sin(phase) + b * cos(phase)))
    }
    mutating func reset() { self = PetHeldSway() }
}

/// Only the view moves; the placed window origin remains the player's destination.
struct PetHeldDrop {
    static let duration: TimeInterval = 0.2
    let started: TimeInterval
    let foot: CGPoint
    let tilt: CGFloat
    func distance(height: CGFloat) -> CGFloat { 12 * height / PetSizing.medium }
    func offset(at now: TimeInterval, height: CGFloat) -> CGFloat {
        let progress = CGFloat(min(1, max(0, (now - started) / Self.duration)))
        return -distance(height: height) * progress * progress
    }
    func landingPlacement(_ placement: PetSpritePlacement, elapsed: TimeInterval,
                          duration: TimeInterval, height: CGFloat) -> PetSpritePlacement {
        let progress = CGFloat(min(1, max(0, elapsed / duration)))
        let remaining = 1 - progress * progress * (3 - 2 * progress)
        let target = CGPoint(x: foot.x, y: foot.y - distance(height: height))
        let correction = CGPoint(x: (target.x - placement.displayPivot.x) * remaining,
                                 y: (target.y - placement.displayPivot.y) * remaining)
        return placement.offset(by: correction)
    }
}

/// Actions may arrive before or after didClose; consume once after every menu closes.
struct PetManualBreadRequest {
    private var menus: Set<ObjectIdentifier> = []
    private var pending = false
    mutating func open(_ menu: ObjectIdentifier) { menus.insert(menu) }
    mutating func close(_ menu: ObjectIdentifier) -> Bool { menus.remove(menu); return menus.isEmpty }
    mutating func request() { pending = true }
    mutating func take(eligible: Bool) -> Bool {
        guard menus.isEmpty, pending else { return false }
        pending = false
        return eligible
    }
    mutating func cancel() { pending = false }
}

struct PetLifeBehavior {
    enum Activity: String { case none, grab, held, lowering, release, annoyed, eating }
    enum Response { case none, turn, annoyed }
    private(set) var activity: Activity = .none
    private(set) var started: TimeInterval = 0
    private(set) var eatingDuration: TimeInterval = 0
    private(set) var visibleTime: TimeInterval = 0
    private(set) var grabImpatient = false
    private(set) var longHoldImpatient = false
    private(set) var eventImpatient = false
    var impatient: Bool { grabImpatient || longHoldImpatient || eventImpatient }
    private var lastRelease: TimeInterval?
    private var lastDisturbance: TimeInterval?
    private(set) var grabCount = 0
    private var completions: [TimeInterval] = []
    private var completionBurstShown = false
    private var lastCompletionVisual: TimeInterval?
    private var lastForegroundVisual: TimeInterval?
    private var foregroundID: String?
    private var lastText: TimeInterval?
    private var holdStarted: TimeInterval?
    private var holdCountsDisturbance = true

    var isPerforming: Bool { activity != .none }
    mutating func advance(at now: TimeInterval, elapsed: TimeInterval, active: Bool) {
        if active && activity != .eating { visibleTime = min(300, visibleTime + max(0, elapsed)) }
        if let holdStarted, holdCountsDisturbance {
            lastDisturbance = now
            if now - holdStarted > 3 { longHoldImpatient = true }
        } else if let lastDisturbance, now - lastDisturbance >= 60 {
            longHoldImpatient = false; eventImpatient = false
        }
        resetGrabsIfQuiet(at: now)
        switch activity {
        case .grab: if now - started >= 0.2 { activity = .held; started += 0.2 }
        case .lowering:
            if now - started >= PetHeldDrop.duration {
                activity = .release; started += PetHeldDrop.duration
                if now - started >= 0.52 { activity = impatient ? .annoyed : .none; started += 0.52 }
            }
        case .release:
            if now - started >= 0.52 { activity = impatient ? .annoyed : .none; started = now }
        case .annoyed: if now - started >= 0.88 { activity = .none }
        case .eating: if now - started >= eatingDuration { activity = .none }
        default: break
        }
    }
    mutating func beginGrab(at now: TimeInterval, disturbance: Bool = true) {
        holdCountsDisturbance = disturbance
        if disturbance {
        resetGrabsIfQuiet(at: now)
        grabCount += 1
        lastDisturbance = now; holdStarted = now
        if grabCount >= 3 { grabImpatient = true }
        } else { holdStarted = now }
        activity = .grab; started = now
    }
    mutating func release(at now: TimeInterval) {
        guard holdStarted != nil else { return }
        if holdCountsDisturbance && now - holdStarted! > 3 { longHoldImpatient = true }
        holdStarted = nil
        if holdCountsDisturbance { lastDisturbance = now; lastRelease = now }
        activity = .lowering; started = now
    }
    /// Suppression interrupts, consumes no new disturbance, and leaves no action to replay.
    mutating func interrupt(resetGrabs: Bool = false) {
        activity = .none; holdStarted = nil
        if resetGrabs { grabCount = 0; grabImpatient = false; lastRelease = nil }
    }
    private mutating func resetGrabsIfQuiet(at now: TimeInterval) {
        if holdStarted == nil, let lastRelease, now - lastRelease >= 15 {
            grabCount = 0; grabImpatient = false; self.lastRelease = nil
        }
    }
    mutating func takeBread(at now: TimeInterval, safeIdle: Bool, random: Double, manual: Bool = false) -> Bool {
        guard safeIdle, activity == .none, manual || (!impatient && visibleTime >= 300) else { return false }
        visibleTime = 0; activity = .eating; started = now
        eatingDuration = 8
        return true
    }
    mutating func completion(at now: TimeInterval, active: Bool, safe: Bool, random: Double) -> Response {
        guard active else { return .none }
        // The caller already removed duplicate IDs. Even a visually ignored active event is a disturbance.
        if longHoldImpatient || eventImpatient { lastDisturbance = now }
        completions = completions.filter { now - $0 <= 60 }; completions.append(now)
        if completions.count < 5 { completionBurstShown = false }
        guard safe, activity == .none, lastCompletionVisual.map({ now - $0 >= 30 }) ?? true else { return .none }
        if completions.count >= 5 && !completionBurstShown {
            completionBurstShown = true; lastCompletionVisual = now
            eventImpatient = true; lastDisturbance = now
            activity = .annoyed; started = now
            return .annoyed
        }
        guard random < 0.4 else { return .none }
        lastCompletionVisual = now
        return .turn
    }
    mutating func foreground(_ identifier: String?, ownID: String, at now: TimeInterval,
                             safeIdle: Bool, random: Double) -> Bool {
        guard let identifier, !identifier.isEmpty, identifier != ownID else { return false }
        let changed = foregroundID != identifier
        foregroundID = identifier
        guard changed, safeIdle, activity == .none,
              lastForegroundVisual.map({ now - $0 >= 60 }) ?? true, random < 0.4 else { return false }
        lastForegroundVisual = now
        return true
    }
    mutating func takeText(at now: TimeInterval) -> Bool {
        guard lastText.map({ now - $0 >= 3 }) ?? true else { return false }
        lastText = now; return true
    }
    func ignoresClick(random: Double) -> Bool { impatient && random < 0.5 }
}

struct PetLifeAnimation: Codable {
    struct Frame: Codable {
        let file: String
        let anchor: [Double] // Top-left source pixels: body-axis proxy and foot baseline.
        let durationMS: Int
    }
    let frameWidth: Int
    let frameHeight: Int
    let displayScale: Double // Artist's 105px preview scale, never a per-frame crop.
    let hanging: Bool
    let frames: [Frame]
    var duration: Double { frames.reduce(0) { $0 + Double($1.durationMS) / 1000 } }
    var isValid: Bool {
        frameWidth > 0 && frameHeight > 0 && displayScale > 0 && displayScale.isFinite &&
        !frames.isEmpty && frames.count <= 12 && frames.allSatisfy {
            $0.file.range(of: "^[a-z]+(?:-[a-z]+)?-[0-9]{2}\\.png$", options: .regularExpression) != nil &&
            $0.anchor.count == 2 && $0.anchor.allSatisfy { $0.isFinite && $0 >= 0 } &&
            $0.anchor[0] <= Double(frameWidth) && $0.anchor[1] <= Double(frameHeight) && $0.durationMS > 0
        }
    }
    func frameIndex(elapsed: TimeInterval, loops: Bool) -> Int {
        var time = loops ? max(0, elapsed).truncatingRemainder(dividingBy: duration) : max(0, elapsed)
        for (index, frame) in frames.enumerated() {
            time -= Double(frame.durationMS) / 1000
            if time < 0 { return index }
        }
        return frames.count - 1
    }
    func stableHeldFrameIndex(elapsed: TimeInterval) -> Int {
        let indices = frames.count > 2 ? [0, 2] : Array(frames.indices)
        guard !indices.isEmpty else { return 0 }
        return indices[Int(max(0, elapsed) / 0.32) % indices.count]
    }
    func placement(frame index: Int, size: CGSize, height: CGFloat, mirrored: Bool, tilt: CGFloat) -> PetSpritePlacement {
        let scale = CGFloat(displayScale) * height / PetSizing.medium
        let baseline = 10 + (hanging ? 12 * height / PetSizing.medium : 0)
        let pivot = CGPoint(x: size.width / 2, y: baseline + (hanging ? 70 * height / PetSizing.medium : 0))
        let anchor = frames[index].anchor
        let rect = CGRect(x: pivot.x - CGFloat(anchor[0]) * scale,
                          y: baseline - (CGFloat(frameHeight) - CGFloat(anchor[1])) * scale,
                          width: CGFloat(frameWidth) * scale, height: CGFloat(frameHeight) * scale)
        return PetSpritePlacement(rect: rect, pivot: pivot, width: size.width, mirrored: mirrored, tilt: tilt)
    }
    static func canvasSize(height: CGFloat) -> CGSize {
        CGSize(width: ceil(height * 1.5 + 20), height: ceil(height * 1.35 + 30))
    }
}

/// Drawing and alpha hit testing apply mirror then rotation, with an exact inverse.
struct PetSpritePlacement {
    let rect: CGRect
    let pivot: CGPoint
    let width: CGFloat
    let mirrored: Bool
    let tilt: CGFloat
    var displayPivot: CGPoint { CGPoint(x: mirrored ? width - pivot.x : pivot.x, y: pivot.y) }
    func offset(by offset: CGPoint) -> PetSpritePlacement {
        // Offset is in displayed coordinates, after mirroring.
        PetSpritePlacement(rect: rect.offsetBy(dx: mirrored ? -offset.x : offset.x, dy: offset.y),
            pivot: CGPoint(x: pivot.x + (mirrored ? -offset.x : offset.x), y: pivot.y + offset.y),
            width: width, mirrored: mirrored, tilt: tilt)
    }
    func display(_ point: CGPoint) -> CGPoint {
        let p = CGPoint(x: mirrored ? width - point.x : point.x, y: point.y)
        return rotate(p, angle: tilt)
    }
    func source(_ point: CGPoint) -> CGPoint {
        let p = rotate(point, angle: -tilt)
        return CGPoint(x: mirrored ? width - p.x : p.x, y: p.y)
    }
    private func rotate(_ point: CGPoint, angle: CGFloat) -> CGPoint {
        let p = displayPivot, x = point.x - p.x, y = point.y - p.y
        return CGPoint(x: p.x + x * cos(angle) - y * sin(angle), y: p.y + x * sin(angle) + y * cos(angle))
    }
}
