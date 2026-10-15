import Foundation
import CoreGraphics

@main
struct BehaviorTests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
        print("PASS \(message)")
    }

    static func main() {
        if CommandLine.arguments.contains("--el006-only") { el006Rules(); return }
        lifeRules()
        el005Rules()
        el006Rules()
        let suite = "local.elaina.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        check(PetQuietBehavior.consumeFirstGreeting(in: defaults), "First local greeting is consumed once")
        check(!PetQuietBehavior.consumeFirstGreeting(in: UserDefaults(suiteName: suite)!), "Greeting remains consumed after loading preferences again")

        var quiet = PetQuietBehavior(random: 0)
        quiet.advance(199, eligible: true)
        check(!quiet.takeThought(random: 0), "Inner thought cannot appear before 200 visible seconds")
        quiet.advance(7200, eligible: false)
        check(quiet.visibleTime == 199, "Hidden, paused, dragging, menu, dialogue and avoidance time do not count")
        quiet.advance(1, eligible: true)
        check(quiet.takeThought(random: 0), "A due thought needs no random chance or extra delay")
        check(!quiet.takeThought(random: 0), "A displayed thought starts a fresh cooldown")
        quiet.advance(300, eligible: true)
        check(quiet.visibleTime == 200, "Waiting for an idle moment cannot build a dialogue backlog")
        check(quiet.takeThought(random: 0) && !quiet.takeThought(random: 0), "Only one thought is available after a long visible interval")
        quiet.advance(199, eligible: true)
        check(!quiet.takeThought(random: 0), "A second thought needs another 200 visible seconds")
        check(PetQuietBehavior.thoughtDuration <= 4, "Thought duration is capped at four seconds")
        quiet.reset(random: 0)
        check(quiet.visibleTime == 0, "Disabling thoughts resets eligibility")

        for _ in 0..<40 { quiet.advance(5, eligible: true) }
        check(quiet.takeThought(random: 0), "Delayed timer callbacks still count 200 real visible seconds")
        var menu = PetMenuState()
        check(menu.requestRefresh(), "A closed menu can refresh immediately")
        menu.open()
        check(!menu.requestRefresh() && menu.isOpen, "Changing a setting never replaces the actively tracked root menu")
        check(!menu.requestRefresh(), "Several selections coalesce into one deferred refresh")
        check(menu.close() && !menu.isOpen, "Closing the root menu clears suppression and requests its refresh")
        check(!menu.close() && menu.requestRefresh(), "A completed refresh cannot leave the menu gate stuck")

        check(PetSizing.medium == 140 * 0.75, "New medium is 25 percent smaller than the former 140pt size")
        check(PetSizing.height(saved: 140, migrated: false) == 105, "An existing installation selects new medium once")
        check(PetSizing.height(saved: 0, migrated: false) == 105, "A fresh installation starts at medium")
        check(PetSizing.height(saved: 77, migrated: true) == 77, "A later small choice remains selected")
        check(PetSizing.height(saved: 138, migrated: true) == 138, "A later large choice remains selected")
        check(PetSizing.height(saved: 190, migrated: true) == 105, "An invalid saved size returns to medium")
        check(PetFlightSpeed.normal.duration == 0.9, "Default flight is 33 percent slower than the former 0.6-second trip")
        check(PetFlightSpeed(rawValue: PetFlightSpeed.slow.rawValue) == .slow, "Flight preference survives serialization")

        var gate = PetCompletionGate()
        check(gate.consume("one", canReact: true) == "reacted", "Completion produces a silent reaction")
        check(gate.consume("one", canReact: true) == "duplicate", "Completion retry is deduplicated")
        check(gate.consume("hidden", canReact: false) == "suppressed", "Hidden or busy completion is consumed without presentation")
        check(gate.consume("hidden", canReact: true) == "duplicate", "Suppressed completion cannot replay after return")
        let reloaded = PetCompletionGate(recent: gate.recent)
        check(reloaded.recent == gate.recent, "Completion history supports persistence")

        let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
        check(PetFullscreenGeometry.quartzFrame(primary, primaryHeight: 900) == primary, "Primary screen converts into Quartz coordinates")
        let aboveLeft = CGRect(x: -1280, y: 200, width: 1280, height: 1024)
        let quartz = PetFullscreenGeometry.quartzFrame(aboveLeft, primaryHeight: 900)
        check(quartz == CGRect(x: -1280, y: -324, width: 1280, height: 1024), "Negative and vertically offset secondary screens convert correctly")
        check(PetFullscreenGeometry.coversScreen(quartz, screen: quartz), "Same-screen full frame matches")
        check(!PetFullscreenGeometry.coversScreen(CGRect(x: 0, y: 25, width: 1440, height: 825), screen: primary), "A visibleFrame maximized window does not count as fullscreen")
        check(!PetFullscreenGeometry.coversScreen(primary, screen: quartz), "Fullscreen on another screen does not hide this pet")
        check(!PetFullscreenGeometry.coversScreen(primary.insetBy(dx: -20, dy: -20), screen: primary), "Overlapping oversized windows do not produce a coverage match")

        let home = CGPoint(x: -1100, y: 220)
        let size = CGSize(width: 184, height: 210)
        let escape = PetFullscreenGeometry.escapeOrigin(home: home, size: size, screen: aboveLeft)
        check(escape.x + size.width < aboveLeft.minX, "Escape destination moves the full canvas beyond the nearest screen edge")
        var avoidance = PetAvoidance()
        avoidance.update(fullscreen: true, origin: home, escape: escape, now: 0)
        check(avoidance.phase == .departing && !avoidance.permitsActivity, "Fullscreen starts departure and immediately suppresses events")
        let midway = avoidance.origin(at: 0.3, fallback: home)
        avoidance.update(fullscreen: false, origin: midway, escape: escape, now: 0.3)
        check(avoidance.phase == .returning && avoidance.origin(at: 0.3, fallback: home) == midway, "Rapid exit reverses smoothly from the current position")
        let returning = avoidance.origin(at: 0.4, fallback: home)
        avoidance.update(fullscreen: true, origin: returning, escape: escape, now: 0.4)
        check(avoidance.phase == .departing && avoidance.home == home, "Rapid re-entry preserves the original home")
        check(!avoidance.advance(to: 1.01), "Slower departure remains in flight before its 0.9-second deadline")
        check(avoidance.advance(to: 1.31) && !avoidance.shouldPresent, "Departure finishes in approximately 0.9 seconds and hides the pet")
        avoidance.update(fullscreen: nil, origin: .zero, escape: .zero, now: 1.35)
        check(avoidance.phase == .away && avoidance.fullscreen && avoidance.home == home && avoidance.escape == escape,
              "Unknown fullscreen detection preserves hidden state and saved geometry")
        avoidance.update(fullscreen: false, origin: escape, escape: escape, now: 1.4)
        check(avoidance.origin(at: 2.31, fallback: .zero) == home, "Return reaches the exact saved position")
        avoidance.advance(to: 2.31)
        check(avoidance.permitsActivity && avoidance.home == nil, "Return releases the anchor without replaying events")

        avoidance.update(fullscreen: true, origin: home, escape: escape, now: 3)
        avoidance.setManuallyHidden(true, origin: home)
        avoidance.update(fullscreen: false, origin: escape, escape: escape, now: 4)
        check(!avoidance.shouldPresent && !avoidance.isFlying, "Manual hide wins over automatic fullscreen return")
        avoidance.update(fullscreen: true, origin: home, escape: escape, now: 5)
        avoidance.setManuallyHidden(false, origin: home)
        check(!avoidance.shouldPresent && avoidance.phase == .away, "Manual show during fullscreen remains hidden")
        let recovered = CGPoint(x: 400, y: 25)
        avoidance.recover(home: recovered, escape: CGPoint(x: 1456, y: 125), now: 5.5, current: escape)
        avoidance.update(fullscreen: false, origin: avoidance.escape, escape: avoidance.escape, now: 6)
        check(avoidance.origin(at: 6.91, fallback: .zero) == recovered, "Screen disconnect recovery returns to a constrained new home")

        for speed in PetFlightSpeed.allCases {
            var flight = PetAvoidance()
            flight.duration = speed.duration
            flight.update(fullscreen: true, origin: home, escape: escape, now: 0)
            check(!flight.advance(to: speed.duration - 0.001), "Selected flight speed cannot finish early: \(speed.label)")
            check(flight.origin(at: speed.duration, fallback: .zero) == escape, "Each flight speed reaches the full escape destination: \(speed.label)")
            check(flight.advance(to: speed.duration), "Each selected flight speed finishes at its deadline: \(speed.label)")
            flight.update(fullscreen: false, origin: escape, escape: escape, now: 10)
            check(flight.origin(at: 10 + speed.duration + 0.001, fallback: .zero) == home, "Each flight speed returns to the original home: \(speed.label)")
        }
        var changed = PetAvoidance()
        changed.update(fullscreen: true, origin: home, escape: escape, now: 0)
        let priorOrigin = changed.origin(at: 0.45, fallback: .zero)
        changed.duration = PetFlightSpeed.fast.duration
        check(changed.origin(at: 0.45, fallback: .zero) == priorOrigin, "Changing speed mid-flight does not jump the pet")
        check(!changed.advance(to: 0.7) && changed.advance(to: 0.91), "Current flight keeps its original duration")
        changed.update(fullscreen: false, origin: escape, escape: escape, now: 2)
        check(changed.advance(to: 2.61), "The following flight uses the newly selected speed")

        var startup = PetAvoidance()
        startup.update(fullscreen: true, origin: home, escape: escape, now: 0, initiallyHidden: true)
        check(startup.phase == .away && !startup.shouldPresent, "Starting during fullscreen does not flash the pet or greeting")
        var sleep = PetAvoidance()
        sleep.update(fullscreen: true, origin: home, escape: escape, now: 0)
        check(sleep.settleBeforeSleep(fallback: home) == escape && sleep.phase == .away,
              "Sleep during departure settles safely hidden")
        sleep.update(fullscreen: false, origin: escape, escape: escape, now: 10)
        check(sleep.settleBeforeSleep(fallback: escape) == home && sleep.phase == .home,
              "Sleep during return preserves the exact home instead of a flight position")
    }
    static func lifeRules() {
        let airborne = CGPoint(x: -1100, y: 284)
        var jumpStart: TimeInterval? = 0
        let pauseDestination = PetPauseBaseline.destination(paused: false, jumpStarted: jumpStart,
                                                           origin: airborne, baseY: 220)
        jumpStart = nil // Same subsequent transient cancellation as the controller.
        check(pauseDestination == CGPoint(x: -1100, y: 220) && jumpStart == nil,
              "Pausing an airborne jump reads its baseline before clearing the jump and preserves X")
        check(PetPauseBaseline.destination(paused: false, jumpStarted: nil, origin: airborne, baseY: 220) == nil,
              "Pausing an idle or dragged pet cannot move it to an unrelated baseline")
        check(PetPauseBaseline.destination(paused: true, jumpStarted: 0, origin: airborne, baseY: 220) == nil,
              "Resuming activity leaves the current origin unchanged")
        let grounded = CGPoint(x: 20, y: 220)
        check(PetPauseBaseline.destination(paused: false, jumpStarted: 0, origin: grounded, baseY: 220) == grounded,
              "Pausing a jump on its baseline does not shift the pet")

        var press = PetPress()
        press.begin(at: 0, point: .zero)
        check(!press.update(at: 0.249, point: CGPoint(x: 4, y: 0)), "Exactly 4pt and under 0.25s remain a click")
        check(press.update(at: 0.25, point: .zero) && press.finish(), "A stationary 0.25s hold starts a grab")
        press.begin(at: 1, point: .zero)
        check(press.update(at: 1.01, point: CGPoint(x: 4.001, y: 0)), "Movement over 4pt starts a grab immediately")
        check(!press.update(at: 2, point: .zero), "An existing grab is registered once")
        press.cancel()
        check(!press.finish(), "Suppression cancels the pointer gesture without a synthetic click")
        press.begin(at: 2, point: .zero)
        check(!press.finish(), "Quick click preserves the click and double-click path")

        var held = PetLifeBehavior()
        held.beginGrab(at: 0)
        held.advance(at: 0.199, elapsed: 0, active: true)
        check(held.activity == .grab, "Grab uses both 100ms frames before held")
        held.advance(at: 0.2, elapsed: 0, active: true)
        check(held.activity == .held, "Held loop starts at 200ms")
        held.advance(at: 3, elapsed: 0, active: true)
        check(!held.impatient, "Exactly three seconds is not a long-hold disturbance")
        held.advance(at: 3.001, elapsed: 0, active: true)
        check(held.impatient && held.activity == .held, "Long hold is impatient while retaining both hands on the hat")
        held.release(at: 4)
        held.advance(at: 4.199, elapsed: 0, active: true)
        check(held.activity == .lowering, "Release first retains the actual suspended pose for 200ms")
        held.advance(at: 4.719, elapsed: 0, active: true)
        check(held.activity == .release, "Release remains interruptible during its four frames")
        held.advance(at: 4.721, elapsed: 0, active: true)
        check(held.activity == .annoyed, "Standing annoyance follows release rather than replacing held")
        held.advance(at: 63.999, elapsed: 0, active: true)
        check(held.impatient, "Mood lasts until sixty quiet seconds after release")
        held.advance(at: 64, elapsed: 0, active: true)
        check(!held.impatient, "Sixty quiet seconds restore mood without persistence")

        var repeated = PetLifeBehavior()
        for time in [0.0, 7.0, 14.0] { repeated.beginGrab(at: time); repeated.release(at: time) }
        check(repeated.impatient, "Three grabs within the unbroken fifteen-second release chain trigger annoyance")
        repeated.beginGrab(at: 14.1)
        check(repeated.activity == .grab, "New grab immediately interrupts release or annoyance")
        var outside = PetLifeBehavior()
        for time in [0.0, 15.0, 30.0] { outside.beginGrab(at: time); outside.release(at: time) }
        check(!outside.impatient, "Fifteen quiet seconds after release restarts the chain")
        var paused = PetLifeBehavior()
        for time in [0.0, 1.0, 2.0] { paused.beginGrab(at: time, disturbance: false); paused.release(at: time) }
        paused.advance(at: 10, elapsed: 10, active: false)
        check(!paused.impatient && paused.visibleTime == 0, "Paused manual control does not accumulate mood or bread time")

        var bread = PetLifeBehavior()
        bread.advance(at: 299.999, elapsed: 299.999, active: true)
        check(!bread.takeBread(at: 299.999, safeIdle: true, random: 0), "Bread cannot start before 300 visible active seconds")
        bread.advance(at: 999, elapsed: 699.001, active: false)
        check(bread.visibleTime == 299.999, "Hidden, paused, sleep and fullscreen time do not earn bread")
        bread.advance(at: 1000, elapsed: 0.001, active: true)
        check(!bread.takeBread(at: 1000, safeIdle: false, random: 0), "Due bread waits for safe idle")
        check(bread.takeBread(at: 1000, safeIdle: true, random: 0) && bread.eatingDuration == 8, "Safe idle starts the fixed eight-second meal")
        bread.advance(at: 1005.999, elapsed: 5.999, active: true)
        check(bread.activity == .eating, "Bread remains active before its duration")
        bread.beginGrab(at: 1006)
        check(bread.activity == .grab && bread.visibleTime < 300, "Player grab interrupts bread and consumes its cooldown")
        bread.interrupt()
        check(bread.activity == .none && !bread.takeBread(at: 1007, safeIdle: true, random: 1), "Fullscreen or hide interrupts bread without replay")
        bread.advance(at: 1400, elapsed: 300, active: true)
        check(bread.takeBread(at: 1400, safeIdle: true, random: 1) && bread.eatingDuration == 8, "Bread duration reaches the approved eight-second duration")
        bread.advance(at: 1410, elapsed: 10, active: true)
        check(bread.activity == .none, "Eating ends exactly at its duration")

        var events = PetLifeBehavior()
        check(events.completion(at: 0, active: true, safe: true, random: 0.4) == .none, "Sixty percent branch including 0.4 is silent")
        check(events.completion(at: 1, active: true, safe: true, random: 0.399) == .turn, "Forty percent branch turns without dialogue")
        check(events.completion(at: 30.999, active: true, safe: true, random: 0) == .none, "Visual cooldown prevents a response before thirty seconds")
        check(events.completion(at: 31, active: true, safe: true, random: 0) == .turn, "A response is eligible exactly thirty seconds later")
        var burst = PetLifeBehavior()
        for time in [0.0, 1, 2, 3] { check(burst.completion(at: time, active: true, safe: true, random: 0.9) == .none, "First four quiet events do not force annoyance") }
        check(burst.completion(at: 60, active: true, safe: true, random: 0.9) == .annoyed, "Fifth distinct event within sixty seconds can show annoyance once")
        burst.advance(at: 61, elapsed: 0, active: true)
        check(burst.completion(at: 61, active: true, safe: true, random: 0) == .none, "Burst annoyance obeys the same thirty-second visual cooldown")
        var suppressed = PetLifeBehavior()
        for time in [0.0, 1, 2, 3, 4] { _ = suppressed.completion(at: time, active: false, safe: false, random: 0) }
        check(suppressed.completion(at: 5, active: true, safe: true, random: 0.9) == .none && !suppressed.impatient,
              "Suppressed completion events never accumulate disturbance or replay")
        var beyond = PetLifeBehavior()
        for time in [0.0, 1, 2, 3, 60.001] { _ = beyond.completion(at: time, active: true, safe: true, random: 0.9) }
        check(!beyond.impatient, "Events outside the sixty-second window are excluded")
        var dedup = PetCompletionGate()
        var distinct = PetLifeBehavior()
        for _ in 0..<5 {
            if dedup.consume("same", canReact: true) != "duplicate" { _ = distinct.completion(at: 0, active: true, safe: true, random: 0.9) }
        }
        check(!distinct.impatient, "Retries are deduplicated before the disturbance counter")

        var recovery = PetLifeBehavior()
        var recoveryGate = PetCompletionGate()
        for time in [0.0, 1, 2, 3, 4] {
            if recoveryGate.consume("burst-\(time)", canReact: true) != "duplicate" {
                _ = recovery.completion(at: time, active: true, safe: true, random: 0.9)
            }
        }
        recovery.advance(at: 5, elapsed: 0, active: true)
        check(recovery.impatient && recovery.activity == .none, "Burst presentation can finish while its short-term mood remains")
        check(recovery.completion(at: 34, active: true, safe: true, random: 0.9) == .none,
              "An active event on the no-visual branch still refreshes the disturbed mood")
        recovery.advance(at: 63, elapsed: 0, active: true)
        check(recovery.impatient, "An active event postpones recovery beyond the first burst's deadline")
        if recoveryGate.consume("latest", canReact: true) != "duplicate" {
            check(recovery.completion(at: 63, active: true, safe: false, random: 0) == .none,
                  "A distinct active busy event refreshes mood without interrupting presentation")
        }
        recovery.advance(at: 64, elapsed: 0, active: true)
        check(recovery.impatient, "Continued active disturbances prevent recovery at the original sixty-second deadline")
        if recoveryGate.consume("inactive", canReact: false) != "duplicate" {
            _ = recovery.completion(at: 90, active: false, safe: false, random: 0)
        }
        if recoveryGate.consume("latest", canReact: true) != "duplicate" {
            _ = recovery.completion(at: 120, active: true, safe: true, random: 0)
        }
        recovery.advance(at: 122.999, elapsed: 0, active: true)
        check(recovery.impatient, "Mood remains until sixty seconds after the last distinct active disturbance")
        recovery.advance(at: 123, elapsed: 0, active: true)
        check(!recovery.impatient, "Inactive events and duplicates do not postpone the exact sixty-second recovery")

        var foreground = PetLifeBehavior()
        check(!foreground.foreground(nil, ownID: "pet", at: 0, safeIdle: true, random: 0), "Unknown foreground applications are ignored")
        check(!foreground.foreground("pet", ownID: "pet", at: 0, safeIdle: true, random: 0), "The pet's own application is ignored")
        check(foreground.foreground("a", ownID: "pet", at: 0, safeIdle: true, random: 0), "A safe foreground change can turn silently")
        check(!foreground.foreground("b", ownID: "pet", at: 59.999, safeIdle: true, random: 0), "Foreground cooldown is at least sixty seconds")
        check(foreground.foreground("c", ownID: "pet", at: 60, safeIdle: true, random: 0), "Foreground reaction is eligible at sixty seconds")
        check(!foreground.foreground("d", ownID: "pet", at: 120, safeIdle: false, random: 0), "A busy or suppressed foreground event is consumed")
        check(!foreground.foreground("d", ownID: "pet", at: 121, safeIdle: true, random: 0), "Suppressed foreground changes do not replay")
        var text = PetLifeBehavior()
        check(text.takeText(at: 0) && !text.takeText(at: 2.999) && text.takeText(at: 3), "Text-only cooldown has an exact three-second boundary")
        text.beginGrab(at: 3)
        check(text.activity == .grab, "Text cooldown does not block dragging")
        check(!PetLifeBehavior().impatient, "Restart begins without persistent resentment")

        let group = PetLifeAnimation(frameWidth: 627, frameHeight: 656, displayScale: 0.1690821256,
            hanging: true, frames: [.init(file: "held-00.png", anchor: [165, 286], durationMS: 160)])
        for height in [77.0, 105, 138] {
            for mirror in [false, true] {
                for tilt in [-0.0873, 0, 0.0873] {
                    let placement = group.placement(frame: 0, size: PetLifeAnimation.canvasSize(height: height),
                        height: height, mirrored: mirror, tilt: tilt)
                    let point = CGPoint(x: placement.rect.midX, y: placement.rect.midY)
                    let roundtrip = placement.source(placement.display(point))
                    check(abs(roundtrip.x - point.x) < 0.00001 && abs(roundtrip.y - point.y) < 0.00001,
                          "Drawing and alpha hit coordinates invert at size \(height), mirror \(mirror), tilt \(tilt)")
                }
            }
        }
    }

    static func el006Rules() {
        var click = PetClickDelay()
        click.schedule(at: 0, interval: 0.5)
        check(!click.take(at: 0.499, eligible: true), "Single click waits for the system double-click deadline")
        click.cancel()
        check(!click.take(at: 0.5, eligible: true), "Second press or real grab cancels the first click before dialogue")
        click.schedule(at: 1, interval: 0.5)
        check(!click.take(at: 1.5, eligible: false) && !click.take(at: 2, eligible: true), "Suppressed click is consumed without replay")
        click.schedule(at: 3, interval: 0.5)
        check(click.take(at: 3.5, eligible: true) && !click.take(at: 3.6, eligible: true), "A normal single click presents once")

        let bounds = CGRect(x: -1200, y: 40, width: 1200, height: 850)
        let size = PetLifeAnimation.canvasSize(height: 105)
        for home in [CGPoint(x: -1195, y: 44), CGPoint(x: -183, y: 44), CGPoint(x: -650, y: 718)] {
            for speed in PetFlightSpeed.allCases {
                let flight = PetShortFlight(home: home, size: size, bounds: bounds, height: 105, speed: speed, at: 1)
                for t in [1.0, 1 + flight.duration / 2, 1 + flight.duration] {
                    check(bounds.contains(CGRect(origin: flight.origin(at: t), size: size)), "Manual flight stays on its negative-coordinate screen at each arc boundary")
                }
                let expected: [PetFlightSpeed: Double] = [.slow: 1.6, .normal: 1.2, .fast: 0.8]
                check(flight.duration == expected[speed] && flight.origin(at: 1) == home && flight.origin(at: 1 + flight.duration) == flight.destination,
                      "Manual flight uses the selected duration and lands exactly at its permanent destination")
                check(!flight.isComplete(at: 1 + flight.duration - 0.001) && flight.isComplete(at: 1 + flight.duration), "A flight cannot commit its destination early")
                check(flight.home == home, "Midair geometry retains the stable home for suppression recovery")
            }
        }
        for height: CGFloat in [77, 105, 138] {
            let canvas = PetLifeAnimation.canvasSize(height: height)
            let roomy = PetShortFlight(home: CGPoint(x: -650, y: 100), size: canvas, bounds: CGRect(x: -1200, y: 40, width: 2400, height: 850), height: height, speed: .normal, at: 0)
            check(abs(roomy.destination.x - roomy.home.x) == 4 * height,
                  "Short flight covers four character heights when space permits at \(height)pt")
            let narrow = CGRect(x: -300, y: 40, width: canvas.width + 120, height: 850)
            let limited = PetShortFlight(home: CGPoint(x: -300, y: 100), size: canvas, bounds: narrow, height: height, speed: .normal, at: 0)
            check(abs(limited.destination.x - limited.home.x - 120) < 0.000001 && narrow.contains(CGRect(origin: limited.destination, size: canvas)),
                  "Short flight uses available space rather than crossing a narrow screen")
        }
        for y in [bounds.minY - 8, bounds.maxY - size.height + 8] {
            let flight = PetShortFlight(home: CGPoint(x: -650, y: y), size: size, bounds: bounds, height: 105, speed: .normal, at: 0)
            check(bounds.contains(CGRect(origin: flight.destination, size: size)), "A slightly out-of-bounds starting home still lands wholly inside visibleFrame")
        }
        let tiny = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let short = PetShortFlight(home: .zero, size: size, bounds: tiny, height: 105, speed: .normal, at: 0)
        check(short.destination == .zero && short.amplitude == 0, "Insufficient room safely shortens the trip to zero")

        var chain = PetLifeBehavior(), press = PetPress()
        for time in [0.0, 2, 4] {
            press.begin(at: time, point: .zero)
            // Mirrors controller's real beginDrag before beginGrab, rather than bypassing interruption.
            check(press.update(at: time + 0.25, point: .zero), "The complete press path establishes a grab")
            chain.interrupt()
            chain.beginGrab(at: time + 0.25)
            check(press.finish(), "The completed pointer gesture releases one grab")
            chain.release(at: time + 0.5)
        }
        check(chain.grabCount == 3 && chain.grabImpatient, "Three real interrupted press/grab/release cycles retain their shared counter")
        press.begin(at: 5, point: .zero); _ = press.finish()
        check(chain.grabCount == 3, "A short single click cannot erase a grab chain")
        chain.advance(at: 19.499, elapsed: 0, active: true)
        check(chain.grabImpatient, "The chain remains at 14.999 seconds after final release")
        chain.advance(at: 19.5, elapsed: 0, active: true)
        check(chain.grabCount == 0 && !chain.grabImpatient, "Final release plus fifteen quiet seconds resets that source")
        chain.beginGrab(at: 20); chain.advance(at: 24, elapsed: 0, active: true); chain.release(at: 24)
        chain.advance(at: 39, elapsed: 0, active: true)
        check(chain.longHoldImpatient && !chain.grabImpatient, "Resetting the chain preserves independent long-hold impatience")
        var eventMood = PetLifeBehavior()
        for t in [0.0, 1, 2, 3, 4] { _ = eventMood.completion(at: t, active: true, safe: true, random: 0.9) }
        eventMood.advance(at: 20, elapsed: 0, active: true)
        check(eventMood.eventImpatient, "Event-source impatience remains independent from the fifteen-second grab reset")
        chain.interrupt(resetGrabs: true)
        check(chain.grabCount == 0 && chain.longHoldImpatient, "True suppression clears transient grabbing without erasing other mood sources")

        var thought = PetQuietBehavior(random: 1)
        thought.advance(399.999, eligible: true)
        check(thought.target == 400 && !thought.takeThought(random: 0), "The upper thought interval waits four hundred eligible seconds")
        thought.advance(0.001, eligible: true)
        check(thought.takeThought(random: 0) && thought.target == 200, "Every thought selects a new injected interval")
        thought.advance(999, eligible: false)
        check(thought.visibleTime == 0, "Suppression never earns thought time")
        check(thought.takeThought(random: 0.5, manual: true) && thought.target == 300 && thought.visibleTime == 0, "Manual thought bypasses time and begins a newly drawn round")

        let manualWalking = PetThoughtSafety(walking: true)
        check(manualWalking.canTest && manualWalking.stopsWalking, "Manual thought safely stops ordinary walking and remains available with automatic thoughts disabled")
        var unsafeThought = PetThoughtSafety(walking: true)
        unsafeThought.performing = true
        var thoughtRequest = PetManualBreadRequest(); thoughtRequest.request()
        check(!thoughtRequest.take(eligible: unsafeThought.canTest) && !thoughtRequest.take(eligible: manualWalking.canTest), "Busy thought tests are consumed without deferred replay")
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets")
        let groups = try! JSONDecoder().decode([String: PetLifeAnimation].self, from: Data(contentsOf: assets.appendingPathComponent("life-animation.json")))
        let meal = groups["eating"]!
        let held = groups["held"]!
        for count in [1, 2] {
            let shortHeld = PetLifeAnimation(frameWidth: held.frameWidth, frameHeight: held.frameHeight, displayScale: held.displayScale,
                hanging: true, frames: Array(held.frames.prefix(count)))
            check(shortHeld.isValid && shortHeld.stableHeldFrameIndex(elapsed: 0.33) < count,
                  "Legitimate \(count)-frame held metadata cannot index an unavailable frame")
        }
        check(held.stableHeldFrameIndex(elapsed: 0) == 0 && held.stableHeldFrameIndex(elapsed: 0.33) == 2, "Approved four-frame held selects stable frames zero and two")
        check(meal.frames.count == 10 && abs(meal.duration - 8) < 1e-10 && meal.isValid, "The approved ten-frame meal lasts eight seconds")
        var previous = -1
        for t in stride(from: 0.0, through: 9.0, by: 0.2) {
            let index = meal.frameIndex(elapsed: t, loops: false)
            check(index >= previous, "Bread consumption never rewinds within a meal")
            previous = index
        }
        check(meal.frameIndex(elapsed: 0, loops: false) == 0 && meal.frameIndex(elapsed: 7.99, loops: false) == 9, "A new meal begins full and the final phase is empty")
        check(PetBubbleAppearance.restored(nil) == 0.6 && PetBubbleAppearance.restored(.nan) == 0.6 && PetBubbleAppearance.clamped(0) == 0.2 && PetBubbleAppearance.clamped(2) == 1,
              "Bubble opacity has safe defaults and the approved twenty-to-one-hundred range")
        let suite = "local.elaina.opacity.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // A single new key is the entire persisted setting surface.
        defaults.set(77, forKey: "petHeight"); defaults.set(0.4, forKey: "bubbleBackgroundOpacity")
        check(PetBubbleAppearance.restored(defaults.double(forKey: "bubbleBackgroundOpacity")) == 0.4 && defaults.integer(forKey: "petHeight") == 77, "Saving opacity preserves size preferences")
        let shortSize = PetSpeechMetrics.size("嗯？怎麼了？", maximumWidth: 1200, maximumHeight: 850)
        let longSize = PetSpeechMetrics.size(String(repeating: "旅途還很長呢。", count: 60), maximumWidth: 1200, maximumHeight: 850)
        check(shortSize.height <= 36 && shortSize.width < 280 && longSize.height > shortSize.height && longSize.height < 850, "Short and long text use uncapped measured multiline layouts")
        for character in [CGRect(x: -1195, y: 44, width: 70, height: 105), CGRect(x: -90, y: 779, width: 70, height: 105)] {
            let origin = PetBubbleGeometry.origin(character: character, size: shortSize, bounds: bounds)
            let bubble = CGRect(origin: origin, size: shortSize)
            check(bounds.contains(bubble) && !bubble.intersects(character), "Bubble placement stays inside screen corners without covering the character")
        }
    }

    static func el005Rules() {
        func sampledSway(dt: Double) -> PetHeldSway {
            var result = PetHeldSway()
            result.begin(at: 0, cursorX: 0)
            var tick = dt
            for (time, x) in [(0.04, 24.0), (0.08, 48), (0.12, 24), (0.16, 0)] {
                while tick < time { result.advance(at: tick); tick += dt }
                result.move(to: x, at: time)
            }
            while tick < 0.41 { result.advance(at: tick); tick += dt }
            result.advance(at: 0.41)
            return result
        }
        let reference = sampledSway(dt: 1.0 / 120)
        for dt in [1.0 / 20, 1.0 / 30, 1.0 / 60] {
            let result = sampledSway(dt: dt)
            check(abs(result.angle - reference.angle) < 1e-10 && abs(result.velocity - reference.velocity) < 1e-10,
                  "Sway has the same elapsed-time result at display interval \(dt)")
        }
        check(abs(reference.tilt) < CGFloat(Double.pi / 180 * 0.2), "Stopped sway converges below 0.2 degrees in a quarter second")
        var reversed = PetHeldSway()
        reversed.begin(at: 0, cursorX: 0)
        reversed.move(to: 24, at: 0.04); reversed.move(to: 48, at: 0.08)
        reversed.advance(at: 0.10)
        let angle = reversed.angle, velocity = reversed.velocity
        reversed.move(to: 24, at: 0.10)
        check(reversed.angle == angle && reversed.velocity == velocity && velocity > 0,
              "A quick reversal retains the existing pose and angular inertia")
        reversed.advance(at: 0.101)
        check(reversed.angle > angle, "Reversed sway briefly continues before turning back")
        for i in 1...200 {
            reversed.move(to: i % 2 == 0 ? 10000 : -10000, at: 1 + Double(i) / 120)
            check(abs(reversed.tilt) <= CGFloat(PetHeldSway.limit), "Sway remains within four degrees under fast alternating input \(i)")
        }
        reversed.reset()
        check(reversed.tilt == 0 && reversed.velocity == 0, "Transient interruption clears sway inertia")

        let root = NSObject(), child = NSObject()
        var request = PetManualBreadRequest()
        request.open(ObjectIdentifier(root)); request.open(ObjectIdentifier(child)); request.request()
        check(!request.take(eligible: true), "A menu action waits while the menu is tracking")
        check(!request.close(ObjectIdentifier(root)) && !request.take(eligible: true), "Root closure cannot bypass a still-open nested menu")
        check(request.close(ObjectIdentifier(child)) && request.take(eligible: true), "The last menu closure allows immediate bread presentation")
        check(!request.take(eligible: true), "Repeated close callbacks cannot replay the consumed bread request")
        request.request()
        check(request.take(eligible: true), "An action delivered after menuDidClose is still consumed once")
        for guardName in ["hidden", "paused", "sleep", "fullscreen", "dragging", "already eating"] {
            request.request()
            check(!request.take(eligible: false) && !request.take(eligible: true), "\(guardName) consumes a rejected bread request without later replay")
        }
        request.request(); request.cancel()
        check(!request.take(eligible: true), "Transient cancellation discards pending manual bread")
        var bread = PetLifeBehavior()
        check(!bread.takeBread(at: 0, safeIdle: false, random: 0, manual: true), "Manual bread respects the caller's visibility and activity guards")
        check(bread.takeBread(at: 0, safeIdle: true, random: 0, manual: true) && bread.eatingDuration == 8,
              "Manual bread immediately bypasses the automatic 300-second wait")
        check(!bread.takeBread(at: 1, safeIdle: true, random: 1, manual: true) && bread.started == 0,
              "Manual bread does not restart an existing eating animation")
        bread.advance(at: 8, elapsed: 8, active: true)
        check(bread.activity == .none && bread.visibleTime == 0, "Eating finishes with a fresh 300-second cooldown")
        bread.advance(at: 307.999, elapsed: 299.999, active: true)
        check(!bread.takeBread(at: 307.999, safeIdle: true, random: 0), "Automatic bread cannot follow manual bread before the renewed cooldown")
        bread.advance(at: 308, elapsed: 0.001, active: true)
        check(bread.takeBread(at: 308, safeIdle: true, random: 1) && bread.eatingDuration == 8,
              "Automatic bread remains active after the renewed 300-second cooldown")
        bread.beginGrab(at: 309)
        check(bread.activity == .grab && bread.visibleTime == 0, "A grab immediately interrupts manually or automatically triggered eating")

        for interruption in ["new grab", "hide", "pause", "fullscreen", "sleep", "resize"] {
            var life = PetLifeBehavior()
            life.beginGrab(at: 0); life.release(at: 0.3)
            life.advance(at: 0.499, elapsed: 0, active: true)
            check(life.activity == .lowering, "\(interruption) can interrupt the retained held pose")
            if interruption == "new grab" { life.beginGrab(at: 0.499) }
            else { life.interrupt() }
            life.advance(at: 10, elapsed: 0, active: false)
            check(life.activity != .release && life.activity != .lowering, "\(interruption) leaves no old drop to resume")
        }
        var late = PetLifeBehavior()
        late.beginGrab(at: 0); late.release(at: 1)
        late.advance(at: 1.3, elapsed: 0, active: true)
        check(late.activity == .release && abs(late.started - 1.2) < 1e-10, "A delayed timer preserves the actual release deadline")
        late.advance(at: 1.721, elapsed: 0, active: true)
        check(late.activity == .none, "The full drop and release finish after 720ms")

        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Assets")
        let groups = try! JSONDecoder().decode([String: PetLifeAnimation].self, from: Data(contentsOf: assets.appendingPathComponent("life-animation.json")))
        // Exact alpha>.08 source bounds measured from the approved PNGs, independent of runtime anchors.
        let bounds: [String: [CGRect]] = [
            "grab": [CGRect(x: 229, y: 39, width: 578, height: 794), CGRect(x: 84, y: 39, width: 623, height: 697)],
            "held": [CGRect(x: 115, y: 54, width: 437, height: 511), CGRect(x: 60, y: 44, width: 464, height: 497),
                     CGRect(x: 117, y: 83, width: 433, height: 507), CGRect(x: 82, y: 80, width: 434, height: 502)],
            "release": [CGRect(x: 116, y: 33, width: 443, height: 500), CGRect(x: 80, y: 33, width: 441, height: 450),
                        CGRect(x: 139, y: 60, width: 389, height: 531), CGRect(x: 112, y: 60, width: 353, height: 536)]
        ]
        func fits(_ placement: PetSpritePlacement, group: PetLifeAnimation, frame: Int, size: CGSize, key: String) -> Bool {
            let box = bounds[key]![frame]
            return [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY),
                    CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)].allSatisfy {
                let point = placement.display(CGPoint(x: placement.rect.minX + $0.x / CGFloat(group.frameWidth) * placement.rect.width,
                                                     y: placement.rect.minY + $0.y / CGFloat(group.frameHeight) * placement.rect.height))
                return point.x >= 0 && point.y >= 0 && point.x <= size.width && point.y <= size.height
            }
        }
        for height in [CGFloat(77), 105, 138] {
            let size = PetLifeAnimation.canvasSize(height: height)
            for mirrored in [false, true] {
                for tilt in [-CGFloat(PetHeldSway.limit), 0, CGFloat(PetHeldSway.limit)] {
                    for key in ["grab", "held"] {
                        let group = groups[key]!
                        for frame in group.frames.indices {
                            let held = group.placement(frame: frame, size: size, height: height, mirrored: mirrored, tilt: tilt)
                            let foot = held.display(CGPoint(x: size.width / 2, y: 10 + 12 * height / PetSizing.medium))
                            let drop = PetHeldDrop(started: 0, foot: foot, tilt: tilt)
                            check(drop.offset(at: 0, height: height) == 0 && abs(drop.offset(at: 0.2, height: height) + 12 * height / 105) < 1e-10,
                                  "Drop starts at its exact held pose and travels twelve scaled points")
                            for time in [0.0, 0.1, 0.2] {
                                check(fits(held.offset(by: CGPoint(x: 0, y: drop.offset(at: time, height: height))), group: group, frame: frame, size: size, key: key),
                                      "Suspended \(key)-\(frame) stays inside canvas at size \(height), mirror \(mirrored), tilt \(tilt), drop \(time)")
                            }
                            let release = groups["release"]!
                            for (index, elapsed) in [(0, 0.0), (1, 0.13), (2, 0.26), (3, 0.39), (3, 0.52)] {
                                let normal = release.placement(frame: index, size: size, height: height, mirrored: mirrored, tilt: tilt * CGFloat(1 - elapsed / 0.52))
                                let landed = drop.landingPlacement(normal, elapsed: elapsed, duration: 0.52, height: height)
                                check(fits(landed, group: release, frame: index, size: size, key: "release"), "Landing frame \(index) stays inside canvas throughout the held-to-release correction")
                                if elapsed == 0 {
                                    check(hypot(landed.displayPivot.x - foot.x, landed.displayPivot.y - (foot.y - drop.distance(height: height))) < 1e-10,
                                          "Release starts at the exact dropped foot and body-axis reference")
                                }
                                if elapsed == 0.52 {
                                    check(landed.rect == normal.rect && landed.displayPivot == CGPoint(x: size.width / 2, y: 10),
                                          "Landing ends at the placed position with no leftover offset")
                                }
                            }
                        }
                    }
                }
            }
        }
    }

}
