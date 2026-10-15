import Foundation
import CoreGraphics

/// Visible, undisturbed time counts; a due thought waits for a safe idle moment.
struct PetQuietBehavior {
    static let thoughtCooldown: TimeInterval = 200
    private(set) var target: TimeInterval
    init(random: Double = 0.5) { target = 200 + 200 * min(1, max(0, random)) }
    static let thoughtDuration: TimeInterval = 4
    private(set) var visibleTime: TimeInterval = 0

    mutating func advance(_ elapsed: TimeInterval, eligible: Bool) {
        if eligible { visibleTime = min(target, visibleTime + max(0, elapsed)) }
    }

    mutating func takeThought(random: Double = 0.5, manual: Bool = false) -> Bool {
        guard manual || visibleTime >= target else { return false }
        self = Self(random: random)
        return true
    }

    mutating func reset(random: Double = 0.5) { self = Self(random: random) }

    static func consumeFirstGreeting(in defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: "hasReceivedFirstGreeting") else { return false }
        defaults.set(true, forKey: "hasReceivedFirstGreeting")
        return true
    }
}

enum PetSizing {
    static let medium: CGFloat = 105
    static let presets: [(label: String, height: Int)] = [("小", 77), ("中", 105), ("大", 138)]

    static func height(saved: Double, migrated: Bool) -> CGFloat {
        // Apply the medium-size migration once; preserve subsequent user choices.
        guard migrated, presets.contains(where: { Double($0.height) == saved }) else { return medium }
        return CGFloat(saved)
    }
}

enum PetFlightSpeed: Int, CaseIterable {
    case slow = 1200, normal = 900, fast = 600
    var duration: TimeInterval { Double(rawValue) / 1000 }
    var label: String {
        switch self {
        case .slow: return "慢慢飛"
        case .normal: return "一般"
        case .fast: return "輕快"
        }
    }
}

/// Only the root menu reports tracking. Rebuild after it closes, never during a selection.
struct PetMenuState {
    private(set) var isOpen = false
    private var refreshPending = false

    mutating func open() { isOpen = true }
    mutating func requestRefresh() -> Bool {
        guard !isOpen else { refreshPending = true; return false }
        return true
    }
    mutating func close() -> Bool {
        isOpen = false
        let pending = refreshPending
        refreshPending = false
        return pending
    }
}

struct PetCompletionGate {
    private(set) var recent: [String]
    init(recent: [String] = []) { self.recent = Array(recent.suffix(100)) }

    mutating func consume(_ eventID: String, canReact: Bool) -> String {
        guard !recent.contains(eventID) else { return "duplicate" }
        recent.append(eventID)
        recent = Array(recent.suffix(100))
        return canReact ? "reacted" : "suppressed"
    }
}

/// A small presentation state machine; it never queues dialogue or completion events.
struct PetAvoidance {
    enum Phase { case home, departing, away, returning }
    var duration: TimeInterval = PetFlightSpeed.normal.duration
    private var activeDuration: TimeInterval = PetFlightSpeed.normal.duration
    private(set) var phase: Phase = .home
    private(set) var fullscreen = false
    private(set) var manuallyHidden = false
    private(set) var home: CGPoint?
    private(set) var escape = CGPoint.zero
    private var start = CGPoint.zero
    private var started: TimeInterval = 0

    var isFlying: Bool { phase == .departing || phase == .returning }
    var shouldPresent: Bool { !manuallyHidden && phase != .away }
    var permitsActivity: Bool { !manuallyHidden && !fullscreen && phase == .home }

    func origin(at now: TimeInterval, fallback: CGPoint) -> CGPoint {
        guard isFlying else { return phase == .away ? escape : (home ?? fallback) }
        let progress = min(1, max(0, (now - started) / activeDuration))
        let eased = progress * progress * (3 - 2 * progress)
        let target = phase == .departing ? escape : (home ?? fallback)
        return CGPoint(x: start.x + (target.x - start.x) * eased,
                       y: start.y + (target.y - start.y) * eased)
    }

    mutating func update(fullscreen: Bool?, origin: CGPoint, escape: CGPoint,
                         now: TimeInterval, initiallyHidden: Bool = false) {
        guard let fullscreen else { return }
        self.fullscreen = fullscreen
        self.escape = escape
        if manuallyHidden {
            phase = fullscreen ? .away : .home
            return
        }
        if fullscreen && (phase == .home || phase == .returning) {
            if home == nil { home = origin }
            start = origin
            started = now
            activeDuration = duration
            phase = initiallyHidden ? .away : .departing
        } else if !fullscreen && (phase == .away || phase == .departing) {
            start = origin
            started = now
            activeDuration = duration
            phase = .returning
        }
    }

    @discardableResult mutating func advance(to now: TimeInterval) -> Bool {
        guard isFlying, now - started >= activeDuration else { return false }
        phase = phase == .departing ? .away : .home
        if phase == .home { home = nil }
        return true
    }

    mutating func setManuallyHidden(_ hidden: Bool, origin: CGPoint) {
        manuallyHidden = hidden
        if home == nil { home = origin }
        phase = fullscreen ? .away : .home
    }

    mutating func recover(home: CGPoint, escape: CGPoint, now: TimeInterval, current: CGPoint) {
        self.home = home
        self.escape = escape
        if isFlying { start = current; started = now; activeDuration = duration }
    }

    mutating func releaseHome() {
        if phase == .home { home = nil }
    }

    mutating func settleBeforeSleep(fallback: CGPoint) -> CGPoint {
        let destination = phase == .departing || phase == .away ? escape : (home ?? fallback)
        if phase == .departing { phase = .away }
        else if phase == .returning { phase = .home; home = nil }
        return destination
    }
}
