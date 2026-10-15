import AppKit
import QuartzCore

final class Sprite {
    let bitmap: NSBitmapImageRep
    let source: CGRect
    // Decode/crop validation also works without registering a GUI application.
    lazy var image = NSImage(cgImage: bitmap.cgImage!, size: NSSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh))

    init?(url: URL, preserveCanvas: Bool = false) {
        guard let data = try? Data(contentsOf: url),
              let rep = NSBitmapImageRep(data: data), rep.cgImage != nil else { return nil }
        bitmap = rep
        if preserveCanvas {
            source = CGRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh)
            return
        }
        var left = rep.pixelsWide, top = rep.pixelsHigh, right = -1, bottom = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08 {
                left = min(left, x); top = min(top, y)
                right = max(right, x); bottom = max(bottom, y)
            }
        }
        guard right >= left, bottom >= top else { return nil }
        source = CGRect(x: left, y: rep.pixelsHigh - 1 - bottom,
                        width: right - left + 1, height: bottom - top + 1)
    }

    lazy var visibleBounds: CGRect = {
        if source.width != CGFloat(bitmap.pixelsWide) || source.height != CGFloat(bitmap.pixelsHigh) { return source }
        var visible = CGRect.null
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide where (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08 {
                visible = visible.union(CGRect(x: x, y: bitmap.pixelsHigh - 1 - y, width: 1, height: 1))
            }
        }
        return visible
    }()

    func contains(_ point: CGPoint, in rect: CGRect, mirrored: Bool) -> Bool {
        guard rect.contains(point) else { return false }
        var u = (point.x - rect.minX) / rect.width
        if mirrored { u = 1 - u }
        let v = (point.y - rect.minY) / rect.height
        let x = min(bitmap.pixelsWide - 1, max(0, Int(source.minX + u * source.width)))
        let y = min(bitmap.pixelsHigh - 1, max(0, Int(CGFloat(bitmap.pixelsHigh) - source.minY - v * source.height)))
        return (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08
    }
}

final class PetView: NSView {
    weak var controller: PetController?
    var sprite: Sprite?
    var mirrored = false
    var bob: CGFloat = 0
    var dragging = false
    private var pressPoint = CGPoint.zero
    private var pressOrigin = CGPoint.zero
    private var press = PetPress()
    var lifePlacement: PetSpritePlacement?
    private var fade: (sprite: Sprite, placement: PetSpritePlacement, started: TimeInterval)?
    func clearFade() { fade = nil }
    func transition(to next: Sprite, placement: PetSpritePlacement?, at now: TimeInterval) {
        if let old = sprite, old !== next {
            fade = (old, lifePlacement ?? PetSpritePlacement(rect: spriteRect, pivot: .zero, width: bounds.width, mirrored: mirrored, tilt: 0), now)
        }
        sprite = next; lifePlacement = placement
    }
    var visibleCharacterRect: CGRect {
        guard let sprite else { return .zero }
        let placement = lifePlacement ?? PetSpritePlacement(rect: spriteRect, pivot: .zero, width: bounds.width, mirrored: mirrored, tilt: 0)
        let box = sprite.visibleBounds
        let corners: [CGPoint] = [CGPoint(x: box.minX, y: box.minY), CGPoint(x: box.maxX, y: box.minY), CGPoint(x: box.minX, y: box.maxY), CGPoint(x: box.maxX, y: box.maxY)]
        var visible = CGRect.null
        for corner in corners {
            let x: CGFloat = placement.rect.minX + (corner.x - sprite.source.minX) / sprite.source.width * placement.rect.width
            let y: CGFloat = placement.rect.minY + (corner.y - sprite.source.minY) / sprite.source.height * placement.rect.height
            let point = placement.display(CGPoint(x: x, y: y))
            visible = visible.union(CGRect(origin: point, size: .zero))
        }
        return visible
    }
    override var acceptsFirstResponder: Bool { false }
    override var isOpaque: Bool { false }

    var spriteRect: CGRect {
        guard let sprite else { return .zero }
        if let placement = lifePlacement { return placement.rect }
        let height = min(controller?.petHeight ?? (bounds.height - 20), bounds.width * sprite.source.height / sprite.source.width)
        let width = height * sprite.source.width / sprite.source.height
        return CGRect(x: (bounds.width - width) / 2, y: 10 + bob, width: width, height: height)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let sprite else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        let current = lifePlacement ?? PetSpritePlacement(rect: spriteRect, pivot: .zero, width: bounds.width, mirrored: mirrored, tilt: 0)
        var fraction: CGFloat = 1
        if let fade {
            NSGraphicsContext.current?.cgContext.beginTransparencyLayer(auxiliaryInfo: nil)
            fraction = CGFloat(min(1, max(0, (CACurrentMediaTime() - fade.started) / 0.12)))
            drawSprite(fade.sprite, placement: fade.placement, fraction: 1 - fraction, operation: .plusLighter)
            drawSprite(sprite, placement: current, fraction: fraction, operation: .plusLighter)
            NSGraphicsContext.current?.cgContext.endTransparencyLayer()
            if fraction >= 1 { self.fade = nil }
            return
        }
        drawSprite(sprite, placement: current, fraction: fraction)
    }
    private func drawSprite(_ sprite: Sprite, placement: PetSpritePlacement, fraction: CGFloat, operation: NSCompositingOperation = .sourceOver) {
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(), pivot = placement.displayPivot
        transform.translateX(by: pivot.x, yBy: pivot.y)
        transform.rotate(byRadians: placement.tilt)
        transform.translateX(by: -pivot.x, yBy: -pivot.y)
        if placement.mirrored { transform.translateX(by: bounds.width, yBy: 0); transform.scaleX(by: -1, yBy: 1) }
        transform.concat()
        sprite.image.draw(in: placement.rect, from: sprite.source, operation: operation, fraction: fraction)
        NSGraphicsContext.restoreGraphicsState()
    }

    func containsCharacter(_ point: CGPoint) -> Bool {
        if let placement = lifePlacement {
            return sprite?.contains(placement.source(point), in: placement.rect, mirrored: false) ?? false
        }
        return sprite?.contains(point, in: spriteRect, mirrored: mirrored) ?? false
    }

    override func mouseDown(with event: NSEvent) {
        guard controller?.avoidance.permitsActivity == true, let window,
              containsCharacter(convert(event.locationInWindow, from: nil)) else { return }
        controller?.beginPress()
        pressPoint = NSEvent.mouseLocation
        pressOrigin = window.frame.origin
        press.begin(at: CACurrentMediaTime(), point: pressPoint)
        dragging = true
    }

    func updatePress(at now: TimeInterval) {
        guard dragging else { return }
        if press.update(at: now, point: NSEvent.mouseLocation) {
            if controller?.manualFlight != nil, let window { pressOrigin = window.frame.origin; pressPoint = NSEvent.mouseLocation }
            controller?.beginGrab(at: now)
        }
    }

    func cancelPress() { dragging = false; press.cancel() }

    override func mouseDragged(with event: NSEvent) {
        guard controller?.avoidance.permitsActivity == true, let window, dragging else { return }
        let cursor = NSEvent.mouseLocation
        let now = CACurrentMediaTime()
        updatePress(at: now)
        let delta = CGPoint(x: cursor.x - pressPoint.x, y: cursor.y - pressPoint.y)
        controller?.heldSway.move(to: cursor.x, at: now)
        window.setFrameOrigin(CGPoint(x: pressOrigin.x + delta.x, y: pressOrigin.y + delta.y))
        controller?.baseY = window.frame.minY
        controller?.presentLife(at: now)
        controller?.moveBubble()
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        updatePress(at: CACurrentMediaTime())
        let grabbed = press.finish()
        dragging = false
        guard controller?.avoidance.permitsActivity == true else { return }
        controller?.endDrag(grabbed: grabbed)
        if !grabbed {
            controller?.handleClick(count: event.clickCount)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard controller?.avoidance.permitsActivity == true, let menu = controller?.makeMenu() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
}

final class SpeechView: NSView {
    var message = ""
    var isThought = false
    var backgroundOpacity = 0.6
    override var isOpaque: Bool { false }
    var textAttributes: [NSAttributedString.Key: Any] {
        PetSpeechMetrics.attributes()
    }
    func size(for message: String, maximumWidth: CGFloat, maximumHeight: CGFloat) -> CGSize {
        PetSpeechMetrics.size(message, maximumWidth: maximumWidth, maximumHeight: maximumHeight)
    }
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 2, dy: 2)
        NSColor(calibratedRed: 0.98, green: 0.96, blue: 1, alpha: backgroundOpacity).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
        path.fill()
        NSColor(calibratedRed: 0.61, green: 0.49, blue: 0.69, alpha: backgroundOpacity).setStroke()
        path.lineWidth = 1
        path.stroke()
        if let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.textMatrix = .identity
            CTFrameDraw(PetSpeechMetrics.frame(message, in: bounds.insetBy(dx: 12, dy: 6)), context)
            context.restoreGState()
        }
    }
}

final class PetController: NSObject, NSMenuDelegate {
    let panel: NSPanel
    let petView = PetView()
    let bubble: NSPanel
    let speechView = SpeechView()
    let idle: Sprite
    var walkFrames: [Sprite] = []
    let broomFrames: [Sprite]
    let broomFrameDuration: Double
    let lifeAnimations: [String: PetLifeAnimation]
    let lifeSprites: [String: [Sprite]]
    var life = PetLifeBehavior()
    var heldSway = PetHeldSway()
    private var heldDrop: PetHeldDrop?
    private var dropSprite: Sprite?
    private var dropPlacement: PetSpritePlacement?
    private var hasCompletedInitialLayout = false
    let defaults = PetPreferences.defaults
    var statusItem: NSStatusItem?
    var timer: Timer?
    var fullscreenTimer: Timer?
    var roam = true
    var paused = false
    var onTop = true
    var petHeight: CGFloat = PetSizing.medium
    var speed: CGFloat = 30
    var flightSpeed = PetFlightSpeed.normal
    var direction: CGFloat = 1
    var walking = false
    var phaseTime = 0.0
    var nextSwitch = 4.0
    var animationTime = 0.0
    var previousTime = CACurrentMediaTime()
    var baseY: CGFloat = 0
    var jumpStarted: Double?
    var bubbleDeadline = 0.0
    var avoidance = PetAvoidance()
    var quietBehavior = PetQuietBehavior(random: Double.random(in: 0...1))
    var manualFlight: PetShortFlight?
    private var manualReturnHome: CGPoint?
    private var pendingClick = PetClickDelay()
    private var lastLifeGroup: String?
    private var manualThought = PetManualBreadRequest()
    var innerThoughtsEnabled = true
    var isVisible: Bool { avoidance.shouldPresent && !sleeping }
    var sleeping = false
    var reactionDeadline = 0.0
    var firstGreetingIssued = false
    private var testDefaultsCleared = false
    private var menuState = PetMenuState()
    private var manualBread = PetManualBreadRequest()
    var menuOpen: Bool {
        get { menuState.isOpen }
        set { if newValue { menuState.open() } else { _ = menuState.close() } }
    }
    var completionNotifications = true
    private var completionGate = PetCompletionGate()
    private var completionObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var testObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var fullscreenCheck: DispatchWorkItem?
    private var testFullscreenOverride: Bool?

    init(idle: Sprite, walkFrames: [Sprite], broomFrames: [Sprite], broomFrameDuration: Double,
         lifeAnimations: [String: PetLifeAnimation], lifeSprites: [String: [Sprite]]) {
        self.idle = idle
        self.walkFrames = walkFrames
        self.broomFrames = broomFrames
        self.broomFrameDuration = broomFrameDuration
        self.lifeAnimations = lifeAnimations
        self.lifeSprites = lifeSprites
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubble = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 212, height: 50),
                         styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        paused = PetPreferences.isolated && (CommandLine.arguments.contains("--start-paused") ||
            ProcessInfo.processInfo.environment["ELAINA_START_PAUSED"] == "1")
        if defaults.object(forKey: "roam") != nil { roam = defaults.bool(forKey: "roam") }
        if defaults.object(forKey: "onTop") != nil { onTop = defaults.bool(forKey: "onTop") }
        if defaults.object(forKey: "completionNotifications") != nil {
            completionNotifications = defaults.bool(forKey: "completionNotifications")
        }
        if defaults.object(forKey: "innerThoughtsEnabled") != nil {
            innerThoughtsEnabled = defaults.bool(forKey: "innerThoughtsEnabled")
        }
        completionGate = PetCompletionGate(recent: defaults.stringArray(forKey: "recentCompletions") ?? [])
        PetDialogues.prepareFile()
        let savedSize = defaults.double(forKey: "petHeight")
        petHeight = PetSizing.height(saved: savedSize, migrated: defaults.bool(forKey: "hasAppliedEL003Sizing"))
        defaults.set(true, forKey: "hasAppliedEL003Sizing")
        let savedSpeed = defaults.double(forKey: "speed")
        if [18.0, 30.0, 48.0].contains(savedSpeed) { speed = savedSpeed }
        flightSpeed = PetFlightSpeed(rawValue: defaults.integer(forKey: "flightSpeed")) ?? .normal
        avoidance.duration = flightSpeed.duration
        for window in [panel, bubble] {
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isFloatingPanel = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.animationBehavior = .none
            window.isReleasedWhenClosed = false
        }
        panel.level = onTop ? .floating : .normal
        panel.isMovableByWindowBackground = false
        panel.title = "伊蕾娜桌寵"
        panel.contentView = petView
        petView.controller = self
        petView.sprite = idle
        bubble.level = .floating
        bubble.ignoresMouseEvents = true
        bubble.contentView = speechView
        speechView.backgroundOpacity = PetBubbleAppearance.restored(defaults.object(forKey: "bubbleBackgroundOpacity").map { _ in defaults.double(forKey: "bubbleBackgroundOpacity") })
        resize(to: petHeight)
        restorePosition()
        checkFullscreen(initial: true)
        if isVisible { panel.orderFrontRegardless() }
        configureStatusItem()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            self?.recoverPosition()
            self?.scheduleFullscreenCheck()
        }
        completionObserver = DistributedNotificationCenter.default().addObserver(
            forName: PetNotifications.completion, object: PetNotifications.object, queue: .main) { [weak self] event in
                self?.receiveCompletion(event)
            }
        let newTimer = Timer(timeInterval: 1.0 / 30.0, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
        configureFullscreenMonitoring()
        if PetPreferences.isolated {
            testObserver = DistributedNotificationCenter.default().addObserver(
                forName: PetNotifications.testControl, object: PetNotifications.object, queue: .main) { [weak self] event in
                    self?.receiveTestControl(event)
                }
        }
        // If the first launch is covered, defer introduction until a normal launch; return stays silent.
        firstGreetingIssued = avoidance.permitsActivity && PetQuietBehavior.consumeFirstGreeting(in: defaults)
        if firstGreetingIssued { say("旅途還很長呢。") }
    }

    deinit {
        timer?.invalidate()
        fullscreenTimer?.invalidate()
        fullscreenCheck?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let completionObserver { DistributedNotificationCenter.default().removeObserver(completionObserver) }
        if let testObserver { DistributedNotificationCenter.default().removeObserver(testObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }

    func currentScreen() -> NSScreen? {
        let home = avoidance.home ?? manualReturnHome ?? panel.frame.origin
        let center = CGPoint(x: home.x + panel.frame.width / 2, y: home.y + positioningSize.height / 2)
        return NSScreen.screens.first(where: { $0.frame.contains(center) }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    // Extra transparent headroom must not migrate an existing saved destination.
    var positioningSize: CGSize { CGSize(width: panel.frame.width, height: petHeight + 30) }

    func resize(to height: CGFloat) {
        if hasCompletedInitialLayout { cancelTransientActivity() }
        petHeight = height
        let size = PetLifeAnimation.canvasSize(height: height) // Full approved canvas and ±8° sway.
        let anchor = avoidance.home ?? panel.frame.origin
        let oldFeet = CGPoint(x: anchor.x + panel.frame.width / 2, y: baseY)
        panel.setContentSize(size)
        if oldFeet != .zero {
            let origin = CGPoint(x: oldFeet.x - size.width / 2, y: oldFeet.y)
            if avoidance.home != nil {
                avoidance.recover(home: origin, escape: avoidance.escape,
                                  now: CACurrentMediaTime(), current: panel.frame.origin)
            } else { panel.setFrameOrigin(origin) }
            recoverPosition()
        }
        defaults.set(Double(height), forKey: "petHeight")
        petView.needsDisplay = true
        hasCompletedInitialLayout = true
    }

    func restorePosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let bounds = screen.visibleFrame
        var origin = CGPoint(x: bounds.maxX - panel.frame.width - 48, y: bounds.minY + 4)
        if defaults.object(forKey: "x") != nil, defaults.object(forKey: "y") != nil {
            let oldWidth = ceil(petHeight * 0.86 + 20)
            let migration = defaults.bool(forKey: "hasAppliedEL004Canvas") ? 0 : (oldWidth - panel.frame.width) / 2
            let stored = CGPoint(x: defaults.double(forKey: "x") + migration, y: defaults.double(forKey: "y"))
            if let storedScreen = NSScreen.screens.first(where: { $0.frame.contains(stored) }) {
                origin = PetGeometry.constrainedOrigin(stored, size: positioningSize, bounds: storedScreen.visibleFrame)
            }
        }
        panel.setFrameOrigin(origin)
        baseY = origin.y
        defaults.set(true, forKey: "hasAppliedEL004Canvas")
        savePosition()
    }

    func savePosition() {
        if PetPreferences.isolated && testDefaultsCleared { return }
        let home = avoidance.home ?? manualReturnHome ?? CGPoint(x: panel.frame.minX, y: baseY)
        defaults.set(Double(home.x), forKey: "x")
        defaults.set(Double(home.y), forKey: "y")
    }

    func recoverPosition() {
        cancelTransientActivity()
        guard let screen = currentScreen() else { return }
        jumpStarted = nil
        let home = avoidance.home ?? manualReturnHome ?? panel.frame.origin
        let origin = PetGeometry.constrainedOrigin(home, size: positioningSize, bounds: screen.visibleFrame)
        if avoidance.phase != .home || avoidance.manuallyHidden {
            avoidance.recover(home: origin,
                escape: PetFullscreenGeometry.escapeOrigin(home: origin, size: panel.frame.size, screen: screen.frame),
                now: CACurrentMediaTime(), current: panel.frame.origin)
        } else {
            panel.setFrameOrigin(origin)
            avoidance.releaseHome()
        }
        baseY = origin.y
        moveBubble()
        savePosition()
    }

    @objc func tick() {
        let now = CACurrentMediaTime()
        let thoughtElapsed = max(0, now - previousTime)
        let elapsed = min(thoughtElapsed, 0.1)
        previousTime = now
        if sleeping { return }
        let active = avoidance.permitsActivity && !paused && !menuOpen
        life.advance(at: now, elapsed: thoughtElapsed, active: active)
        if avoidance.isFlying { animateFlight(at: now); return }
        if !isVisible { return }
        if pendingClick.take(at: now, eligible: !paused && !petView.dragging && !menuOpen && !life.isPerforming && manualFlight == nil) { playerClick() }
        if let flight = manualFlight {
            panel.setFrameOrigin(flight.origin(at: now))
            petView.sprite = broomFrames[Int(now / broomFrameDuration) % broomFrames.count]
            petView.lifePlacement = nil; petView.bob = 0
            petView.mirrored = flight.destination.x < flight.home.x; petView.needsDisplay = true
            petView.updatePress(at: now)
            if manualFlight != nil && flight.isComplete(at: now) {
                manualFlight = nil; manualReturnHome = nil
                panel.setFrameOrigin(flight.destination); baseY = flight.destination.y
                petView.sprite = idle; savePosition()
            }
            updatePointerPassthrough()
            return
        }
        petView.updatePress(at: now)
        heldSway.advance(at: now)
        let performing = life.isPerforming
        if !performing && petView.lifePlacement != nil {
            clearHeldVisuals()
            petView.transition(to: idle, placement: nil, at: now); lastLifeGroup = nil; petView.needsDisplay = true
        }
        if performing { presentLife(at: now) }
        let reacting = reactionDeadline > now
        if reacting && !performing {
            petView.lifePlacement = nil
            petView.sprite = idle
            petView.mirrored = direction < 0
            petView.bob = 0
            petView.needsDisplay = true
        }
        if !performing && !reacting && !paused && !petView.dragging && !menuOpen {
            petView.lifePlacement = nil
            animationTime += elapsed
            phaseTime += elapsed
            if phaseTime >= nextSwitch {
                walking.toggle()
                phaseTime = 0
                nextSwitch = walking ? Double.random(in: 3...7) : Double.random(in: 3...6)
                if walking && Bool.random() { direction *= -1 }
            }
            if let started = jumpStarted {
                let progress = (now - started) / 0.8
                let available = max(0, (currentScreen()?.visibleFrame.maxY ?? panel.frame.maxY) - baseY - panel.frame.height)
                let offset = PetGeometry.jumpHeight(progress: progress, amplitude: min(64, available))
                panel.setFrameOrigin(CGPoint(x: panel.frame.minX, y: baseY + offset))
                if progress >= 1 { jumpStarted = nil }
            } else if roam && walking, let screen = currentScreen() {
                let step = PetGeometry.walk(x: panel.frame.minX, width: panel.frame.width,
                                            bounds: screen.visibleFrame, direction: direction,
                                            speed: speed, elapsed: elapsed)
                direction = step.direction
                panel.setFrameOrigin(CGPoint(x: step.x, y: baseY))
            }
            let moving = roam && walking && jumpStarted == nil
            petView.sprite = moving && !walkFrames.isEmpty ? walkFrames[Int(animationTime * 7) % walkFrames.count] : idle
            petView.mirrored = moving && direction < 0
            petView.bob = jumpStarted != nil ? 0 : (moving ? 0 : CGFloat((sin(animationTime * 2.2) * 1.3).rounded()))
            petView.needsDisplay = true
        }
        if !performing && life.takeBread(at: now, safeIdle: safeIdle && !reacting,
                                        random: Double.random(in: 0..<1)) {
            bubble.orderOut(nil)
            presentLife(at: now)
        }
        // Poll only the sprite's alpha at the pointer. Transparent margins pass clicks through.
        updatePointerPassthrough()
        if bubble.isVisible {
            moveBubble()
            if now >= bubbleDeadline { bubble.orderOut(nil) }
        }
        let eligible = innerThoughtsEnabled && avoidance.permitsActivity && !paused && !petView.dragging &&
            !menuOpen && !bubble.isVisible && jumpStarted == nil && !reacting && !life.isPerforming
        quietBehavior.advance(thoughtElapsed, eligible: eligible)
        if eligible && !(roam && walking) && quietBehavior.takeThought(random: Double.random(in: 0...1)) {
            let thoughts = PetDialogues.load().innerThoughts ?? PetDialogues.fallback.innerThoughts ?? []
            if let thought = thoughts.randomElement() { say(thought, duration: PetQuietBehavior.thoughtDuration, thought: true) }
        }
    }

    func updatePointerPassthrough() {
        let local = petView.convert(panel.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        panel.ignoresMouseEvents = !petView.dragging && !petView.containsCharacter(local)
    }

    func configureFullscreenMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                guard let self else { return }
                self.scheduleFullscreenCheck()
                if name == NSWorkspace.didActivateApplicationNotification {
                    self.receiveForeground(event)
                }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            if self.avoidance.isFlying {
                let destination = self.avoidance.settleBeforeSleep(fallback: self.panel.frame.origin)
                self.panel.setFrameOrigin(destination)
                if self.avoidance.phase == .home { self.baseY = destination.y }
            }
            self.sleeping = true
            self.cancelTransientActivity()
            self.panel.orderOut(nil)
        })
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didWakeNotification,
                                                     object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.sleeping = false
            self.previousTime = CACurrentMediaTime()
            self.recoverPosition()
            self.checkFullscreen(initial: true)
            if self.isVisible { self.panel.orderFrontRegardless() }
            self.scheduleFullscreenCheck()
        })
        let monitor = Timer(timeInterval: 2, target: self, selector: #selector(pollFullscreen), userInfo: nil, repeats: true)
        RunLoop.main.add(monitor, forMode: .common)
        fullscreenTimer = monitor
    }

    func scheduleFullscreenCheck() {
        checkFullscreen()
        fullscreenCheck?.cancel()
        let followup = DispatchWorkItem { [weak self] in self?.checkFullscreen() }
        fullscreenCheck = followup
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: followup)
    }

    @objc func pollFullscreen() { checkFullscreen() }

    func checkFullscreen(initial: Bool = false) {
        guard !sleeping, let screen = currentScreen() else { return }
        guard let covered = testFullscreenOverride ?? PetFullscreenDetector.covers(screen) else { return }
        let now = CACurrentMediaTime()
        var current = avoidance.origin(at: now, fallback: panel.frame.origin)
        let home = avoidance.home ?? manualReturnHome ?? CGPoint(x: panel.frame.minX, y: baseY)
        let escape = PetFullscreenGeometry.escapeOrigin(home: home, size: panel.frame.size, screen: screen.frame)
        if covered != avoidance.fullscreen {
            cancelTransientActivity()
            if avoidance.phase == .home { current = home; panel.setFrameOrigin(home) }
            avoidance.update(fullscreen: covered, origin: current, escape: escape, now: now, initiallyHidden: initial)
            if avoidance.isFlying {
                panel.ignoresMouseEvents = true
                panel.orderFrontRegardless()
                animateFlight(at: now)
            } else if !isVisible { panel.orderOut(nil) }
            refreshMenu()
        }
    }

    func animateFlight(at now: TimeInterval) {
        let origin = avoidance.origin(at: now, fallback: panel.frame.origin)
        let departure = avoidance.phase == .departing
        let home = avoidance.home ?? manualReturnHome ?? panel.frame.origin
        let heading = avoidance.escape.x >= home.x ? CGFloat(1) : -1
        petView.lifePlacement = nil
        petView.sprite = broomFrames[Int(now / broomFrameDuration) % broomFrames.count]
        petView.mirrored = departure ? heading < 0 : heading > 0
        petView.bob = 0
        petView.needsDisplay = true
        panel.ignoresMouseEvents = true
        panel.setFrameOrigin(origin)
        if avoidance.advance(to: now) {
            if !isVisible { panel.orderOut(nil) }
            else {
                baseY = origin.y
                petView.sprite = idle
                petView.mirrored = direction < 0
                petView.needsDisplay = true
                savePosition()
            }
            refreshMenu()
        }
    }

    func cancelShortFlight(restoring: Bool) {
        manualFlight = nil
        if restoring, let home = manualReturnHome {
            panel.setFrameOrigin(home); baseY = home.y; manualReturnHome = nil
        }
    }
    func cancelTransientActivity(resetGrabChain: Bool = true) {
        cancelShortFlight(restoring: true)
        pendingClick.cancel()
        manualThought.cancel()
        petView.clearFade(); lastLifeGroup = nil
        if bubble.isVisible { bubble.orderOut(nil) }
        speechView.message = ""
        speechView.isThought = false
        reactionDeadline = 0
        jumpStarted = nil
        life.interrupt(resetGrabs: resetGrabChain)
        clearHeldVisuals()
        manualBread.cancel()
        petView.cancelPress()
        petView.lifePlacement = nil
        petView.sprite = idle
        petView.bob = 0
        petView.needsDisplay = true
    }

    func clearHeldVisuals() {
        heldSway.reset()
        heldDrop = nil; dropSprite = nil; dropPlacement = nil
    }

    func cancelThought() {
        if speechView.isThought { bubble.orderOut(nil); speechView.message = ""; speechView.isThought = false }
        reactionDeadline = 0
    }

    func beginPress() {
        pendingClick.cancel()
        cancelThought()
    }
    func handleClick(count: Int) {
        if count >= 2 { pendingClick.cancel(); shortFlight() }
        else if isVisible && !paused && !life.isPerforming && manualFlight == nil {
            pendingClick.schedule(at: CACurrentMediaTime(), interval: NSEvent.doubleClickInterval)
        }
    }
    @objc func shortFlight() {
        guard isVisible, !paused, !sleeping, avoidance.permitsActivity, manualFlight == nil, manualReturnHome == nil, !petView.dragging, let screen = currentScreen() else { return }
        if jumpStarted != nil { panel.setFrameOrigin(CGPoint(x: panel.frame.minX, y: baseY)) }
        cancelTransientActivity(resetGrabChain: false)
        walking = false; phaseTime = 0
        let home = panel.frame.origin
        manualReturnHome = home
        manualFlight = PetShortFlight(home: home, size: panel.frame.size, bounds: screen.visibleFrame, height: petHeight, speed: flightSpeed, at: CACurrentMediaTime())
    }
    func beginDrag() {
        pendingClick.cancel()
        cancelShortFlight(restoring: false)
        petView.clearFade(); lastLifeGroup = nil
        cancelThought()
        if jumpStarted != nil {
            panel.setFrameOrigin(CGPoint(x: panel.frame.minX, y: baseY))
            jumpStarted = nil
        }
        life.interrupt()
        clearHeldVisuals()
        manualBread.cancel()
        heldSway.begin(at: CACurrentMediaTime(), cursorX: NSEvent.mouseLocation.x)
        petView.lifePlacement = nil
        petView.sprite = idle
        petView.bob = 0
        petView.needsDisplay = true
    }

    func beginGrab(at now: TimeInterval) {
        beginDrag()
        bubble.orderOut(nil)
        reactionDeadline = 0
        life.beginGrab(at: now, disturbance: !paused)
        presentLife(at: now)
    }

    func endDrag(grabbed: Bool) {
        let now = CACurrentMediaTime()
        guard grabbed || (manualFlight == nil && manualReturnHome == nil && jumpStarted == nil && !life.isPerforming) else { return }
        if grabbed {
            manualReturnHome = nil
            heldSway.advance(at: now)
            presentLife(at: now)
            petView.clearFade()
            dropSprite = petView.sprite
            dropPlacement = petView.lifePlacement
            if let placement = dropPlacement {
                let foot = placement.display(CGPoint(x: petView.bounds.width / 2,
                    y: 10 + 12 * petHeight / PetSizing.medium))
                heldDrop = PetHeldDrop(started: now, foot: foot, tilt: placement.tilt)
            }
            life.release(at: now)
            presentLife(at: now)
        } else { clearHeldVisuals() }
        baseY = panel.frame.minY
        savePosition()
    }

    var safeIdle: Bool {
        avoidance.permitsActivity && !sleeping && !paused && !petView.dragging && !menuOpen &&
            !bubble.isVisible && jumpStarted == nil && manualFlight == nil && !(roam && walking) && !life.isPerforming
    }

    func presentLife(at now: TimeInterval) {
        if life.activity == .lowering, let drop = heldDrop,
           let sprite = dropSprite, let placement = dropPlacement {
            petView.sprite = sprite
            petView.lifePlacement = placement.offset(by: CGPoint(x: 0, y: drop.offset(at: now, height: petHeight)))
            petView.needsDisplay = true
            return
        }
        let key = life.activity.rawValue
        guard let animation = lifeAnimations[key], let frames = lifeSprites[key] else { return }
        let loops = life.activity == .held || life.activity == .annoyed
        let index = life.activity == .held ? animation.stableHeldFrameIndex(elapsed: now - life.started) : animation.frameIndex(elapsed: now - life.started, loops: loops)
        petView.bob = 0
        let releaseProgress = CGFloat(min(1, max(0, (now - life.started) / animation.duration)))
        let tilt = animation.hanging ? heldSway.tilt :
            (life.activity == .release ? (heldDrop?.tilt ?? 0) * (1 - releaseProgress) : 0)
        var placement = animation.placement(frame: index, size: petView.bounds.size, height: petHeight,
            mirrored: life.activity == .eating ? false : direction < 0, tilt: tilt)
        if life.activity == .release, let drop = heldDrop {
            placement = drop.landingPlacement(placement, elapsed: now - life.started,
                duration: animation.duration, height: petHeight)
        }
        if lastLifeGroup != key {
            if key == "release", let drop = heldDrop, let old = dropPlacement, let sprite = dropSprite {
                petView.sprite = sprite
                petView.lifePlacement = old.offset(by: CGPoint(x: 0, y: -drop.distance(height: petHeight)))
            }
            petView.transition(to: frames[index], placement: placement, at: now); lastLifeGroup = key
        }
        else { petView.sprite = frames[index]; petView.lifePlacement = placement }
        petView.needsDisplay = true
    }

    func receiveForeground(_ notification: Notification) {
        let identifier = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
        let now = CACurrentMediaTime()
        if life.foreground(identifier, ownID: Bundle.main.bundleIdentifier ?? PetNotifications.object,
                           at: now, safeIdle: safeIdle && reactionDeadline <= now,
                           random: Double.random(in: 0..<1)) {
            direction *= -1
            reactionDeadline = now + 0.8
        }
    }

    func playerClick() {
        guard avoidance.permitsActivity && !sleeping else { return }
        let now = CACurrentMediaTime()
        guard !life.ignoresClick(random: Double.random(in: 0..<1)), life.takeText(at: now) else { return }
        if let line = PetDialogues.load().clickLine(random: Double.random(in: 0..<1)) {
            say(line, duration: 4)
        }
    }

    @objc func jump() {
        guard avoidance.permitsActivity && !sleeping else { return }
        if paused { paused = false; refreshMenu() }
        cancelTransientActivity(resetGrabChain: false)
        jumpStarted = CACurrentMediaTime()
        if life.takeText(at: CACurrentMediaTime()) { say(PetDialogues.load().jump, duration: 4) }
    }

    @objc func greet() {
        guard avoidance.permitsActivity && !sleeping else { return }
        guard life.takeText(at: CACurrentMediaTime()) else { return }
        say(PetDialogues.load().greetings.randomElement() ?? "旅途還很長呢。", duration: 4)
    }

    func say(_ message: String, duration: Double? = nil, thought: Bool = false) {
        guard avoidance.permitsActivity && !sleeping && !life.isPerforming && manualFlight == nil else { return }
        cancelThought()
        let screen = currentScreen()?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        bubble.setContentSize(speechView.size(for: message, maximumWidth: screen.width,
                                            maximumHeight: screen.height))
        speechView.message = message
        speechView.isThought = thought
        speechView.needsDisplay = true
        bubbleDeadline = CACurrentMediaTime() + (duration ?? max(3.4, min(12, Double(message.count) * 0.18)))
        moveBubble()
        bubble.orderFrontRegardless()
    }

    func receiveCompletion(_ notification: Notification) {
        guard let info = notification.userInfo,
              info["status"] as? String == "completed",
              let eventID = info["eventID"] as? String, !eventID.isEmpty, eventID.utf8.count < 600 else { return }
        let now = CACurrentMediaTime()
        let active = completionNotifications && avoidance.permitsActivity && !sleeping && !paused
        let safe = active && !petView.dragging && !menuOpen && !bubble.isVisible &&
            jumpStarted == nil && manualFlight == nil && reactionDeadline <= now && !life.isPerforming
        var result = completionGate.consume(eventID, canReact: active)
        defaults.set(completionGate.recent, forKey: "recentCompletions")
        if result != "duplicate" {
            let response = life.completion(at: now, active: active, safe: safe, random: Double.random(in: 0..<1))
            switch response {
            case .turn: direction *= -1; reactionDeadline = now + 0.8; result = "reacted"
            case .annoyed: presentLife(at: now); result = "reacted"
            case .none: result = active ? "ignored" : "suppressed"
            }
        }
        DistributedNotificationCenter.default().postNotificationName(
            PetNotifications.acknowledgement, object: PetNotifications.object,
            userInfo: ["eventID": eventID, "result": result, "bubbleVisible": bubble.isVisible,
                       "reactionActive": reactionDeadline > CACurrentMediaTime()], deliverImmediately: true)
    }

    @objc func testCompletion() {
        receiveCompletion(Notification(name: PetNotifications.completion,
            userInfo: ["status": "completed", "eventID": "manual-\(UUID().uuidString)"]))
    }
    @objc func testBread() {
        manualBread.request()
        DispatchQueue.main.async { [weak self] in self?.performPendingBread() }
    }
    func performPendingBread() {
        guard !menuOpen else { return }
        let eligible = isVisible && panel.isVisible && avoidance.permitsActivity && !sleeping &&
            !paused && !petView.dragging && manualFlight == nil && life.activity != .eating
        guard manualBread.take(eligible: eligible) else { return }
        if jumpStarted != nil { panel.setFrameOrigin(CGPoint(x: panel.frame.minX, y: baseY)) }
        cancelTransientActivity(resetGrabChain: false)
        walking = false; phaseTime = 0
        let now = CACurrentMediaTime()
        if life.takeBread(at: now, safeIdle: true, random: Double.random(in: 0..<1), manual: true) {
            presentLife(at: now)
        }
    }
    @objc func testThought() {
        manualThought.request()
        DispatchQueue.main.async { [weak self] in self?.performPendingThought() }
    }
    func performPendingThought() {
        guard !menuOpen else { return }
        let context = PetThoughtSafety(visible: isVisible && panel.isVisible && avoidance.permitsActivity,
            paused: paused, dragging: petView.dragging, performing: life.isPerforming,
            flying: manualFlight != nil, jumping: jumpStarted != nil,
            reacting: reactionDeadline > CACurrentMediaTime(), bubbleVisible: bubble.isVisible, walking: roam && walking)
        guard manualThought.take(eligible: context.canTest) else { return }
        walking = false; phaseTime = 0
        let thoughts = PetDialogues.load().innerThoughts ?? PetDialogues.fallback.innerThoughts ?? []
        if let thought = thoughts.randomElement(), quietBehavior.takeThought(random: Double.random(in: 0...1), manual: true) {
            say(thought, duration: PetQuietBehavior.thoughtDuration, thought: true)
        }
    }
    @objc func changeBubbleOpacity(_ sender: NSSlider) {
        let value = PetBubbleAppearance.clamped(sender.doubleValue / 100)
        defaults.set(value, forKey: "bubbleBackgroundOpacity")
        speechView.backgroundOpacity = value; speechView.needsDisplay = true
        (sender.superview?.subviews.first { $0 is NSTextField } as? NSTextField)?.stringValue = "背景不透明度 \(Int(value * 100))%"
    }
    @objc func toggleCompletionNotifications() {
        completionNotifications.toggle()
        defaults.set(completionNotifications, forKey: "completionNotifications")
        refreshMenu()
    }
    @objc func toggleInnerThoughts() {
        innerThoughtsEnabled.toggle()
        defaults.set(innerThoughtsEnabled, forKey: "innerThoughtsEnabled")
        cancelThought()
        quietBehavior.reset(random: Double.random(in: 0...1))
        refreshMenu()
    }
    @objc func editDialogues() {
        PetDialogues.prepareFile()
        let editor = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([PetDialogues.fileURL], withApplicationAt: editor,
                                configuration: NSWorkspace.OpenConfiguration()) { _, _ in }
    }

    func moveBubble() {
        guard let screen = currentScreen() else { return }
        let character = petView.visibleCharacterRect.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
        bubble.setFrameOrigin(PetBubbleGeometry.origin(character: character, size: bubble.frame.size, bounds: screen.visibleFrame))
    }

    func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "伊蕾娜桌寵")
            button.toolTip = "伊蕾娜桌寵 — 點此調整或結束"
        }
        refreshMenu()
    }

    func refreshMenu() {
        guard menuState.requestRefresh() else { return }
        statusItem?.menu = makeMenu()
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        let title = NSMenuItem(title: "伊蕾娜 · 魔女之旅", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        func item(_ label: String, _ action: Selector, checked: Bool? = nil, tag: Int = 0) -> NSMenuItem {
            let result = NSMenuItem(title: label, action: action, keyEquivalent: "")
            result.target = self
            result.tag = tag
            if let checked { result.state = checked ? .on : .off }
            return result
        }
        func group(_ label: String, in parent: NSMenu) -> NSMenu {
            let submenu = NSMenu(title: label)
            submenu.delegate = self
            let entry = NSMenuItem(title: label, action: nil, keyEquivalent: "")
            entry.submenu = submenu
            parent.addItem(entry)
            return submenu
        }
        let interaction = group("互動", in: menu)
        interaction.addItem(item("打聲招呼", #selector(greet)))
        interaction.addItem(item("跳一下", #selector(jump)))
        interaction.addItem(item("測試吃麵包", #selector(testBread)))
        interaction.addItem(item("測試內心戲", #selector(testThought)))
        interaction.addItem(.separator())
        interaction.addItem(item("修改台詞…", #selector(editDialogues)))

        let behavior = group("行為", in: menu)
        behavior.addItem(item("自動散步", #selector(toggleRoam), checked: roam))
        let speeds = group("散步速度", in: behavior)
        for (label, value) in [("慢慢走", 18), ("一般", 30), ("輕快", 48)] {
            speeds.addItem(item(label, #selector(changeSpeed(_:)), checked: Int(speed) == value, tag: value))
        }
        let flights = group("飛行速度", in: behavior)
        for value in PetFlightSpeed.allCases {
            flights.addItem(item(value.label, #selector(changeFlightSpeed(_:)), checked: flightSpeed == value, tag: value.rawValue))
        }
        behavior.addItem(.separator())
        behavior.addItem(item("偶爾顯示內心戲", #selector(toggleInnerThoughts), checked: innerThoughtsEnabled))
        behavior.addItem(item("回應 Codex 回合結束", #selector(toggleCompletionNotifications), checked: completionNotifications))
        behavior.addItem(item("測試安靜回應", #selector(testCompletion)))

        let appearance = group("外觀", in: menu)
        let sizes = group("角色大小", in: appearance)
        for (label, height) in PetSizing.presets {
            sizes.addItem(item(label, #selector(changeSize(_:)), checked: Int(petHeight) == height, tag: height))
        }
        let opacity = NSMenuItem(title: "對話框透明度", action: nil, keyEquivalent: "")
        let opacityView = NSView(frame: CGRect(x: 0, y: 0, width: 218, height: 54))
        let label = NSTextField(labelWithString: "背景不透明度 \(Int(speechView.backgroundOpacity * 100))%")
        label.frame = CGRect(x: 12, y: 30, width: 194, height: 18); label.font = .systemFont(ofSize: 11)
        let slider = NSSlider(value: speechView.backgroundOpacity * 100, minValue: 20, maxValue: 100, target: self, action: #selector(changeBubbleOpacity(_:)))
        slider.frame = CGRect(x: 12, y: 6, width: 194, height: 20); slider.isContinuous = true
        slider.setAccessibilityLabel("對話框透明度")
        opacityView.addSubview(label); opacityView.addSubview(slider); opacity.view = opacityView; appearance.addItem(opacity)
        appearance.addItem(item("保持在視窗最上層", #selector(toggleOnTop), checked: onTop))
        appearance.addItem(item("帶回主螢幕下方", #selector(showPet)))
        menu.addItem(.separator())
        menu.addItem(item(paused ? "繼續活動" : "暫停活動", #selector(togglePause), checked: paused))
        menu.addItem(item(avoidance.manuallyHidden ? "顯示伊蕾娜" : "隱藏伊蕾娜", #selector(toggleVisible)))
        menu.addItem(item("使用說明", #selector(showHelp)))
        menu.addItem(item("結束伊蕾娜桌寵", #selector(quit)))
        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        pendingClick.cancel()
        manualBread.open(ObjectIdentifier(menu))
        manualThought.open(ObjectIdentifier(menu))
        menuState.open()
        cancelThought()
    }
    func menuDidClose(_ menu: NSMenu) {
        _ = manualThought.close(ObjectIdentifier(menu))
        guard manualBread.close(ObjectIdentifier(menu)) else { return }
        if menuState.close() {
            DispatchQueue.main.async { [weak self] in self?.refreshMenu() }
        }
        DispatchQueue.main.async { [weak self] in self?.performPendingBread(); self?.performPendingThought() }
    }

    @objc func toggleRoam() {
        roam.toggle()
        defaults.set(roam, forKey: "roam")
        walking = false
        refreshMenu()
    }
    @objc func togglePause() {
        if let destination = PetPauseBaseline.destination(paused: paused, jumpStarted: jumpStarted,
                                                         origin: panel.frame.origin, baseY: baseY) {
            panel.setFrameOrigin(destination)
        }
        cancelTransientActivity()
        paused.toggle()
        refreshMenu()
    }
    @objc func toggleOnTop() {
        onTop.toggle()
        panel.level = onTop ? .floating : .normal
        defaults.set(onTop, forKey: "onTop")
        if isVisible { panel.orderFrontRegardless() }
        refreshMenu()
    }
    @objc func changeSize(_ sender: NSMenuItem) { resize(to: CGFloat(sender.tag)); refreshMenu() }
    @objc func changeSpeed(_ sender: NSMenuItem) {
        speed = CGFloat(sender.tag)
        defaults.set(Double(speed), forKey: "speed")
        refreshMenu()
    }
    @objc func changeFlightSpeed(_ sender: NSMenuItem) {
        guard let value = PetFlightSpeed(rawValue: sender.tag) else { return }
        flightSpeed = value
        avoidance.duration = value.duration
        defaults.set(value.rawValue, forKey: "flightSpeed")
        refreshMenu()
    }
    @objc func toggleVisible() {
        cancelTransientActivity()
        let home = avoidance.home ?? manualReturnHome ?? CGPoint(x: panel.frame.minX, y: baseY)
        avoidance.setManuallyHidden(!avoidance.manuallyHidden, origin: home)
        panel.setFrameOrigin(home)
        baseY = home.y
        if !avoidance.manuallyHidden {
            checkFullscreen()
            if avoidance.permitsActivity {
                avoidance.releaseHome()
                petView.sprite = idle
                panel.orderFrontRegardless()
            } else { panel.orderOut(nil) }
        } else { panel.orderOut(nil) }
        refreshMenu()
    }
    @objc func showPet() {
        cancelTransientActivity()
        if avoidance.fullscreen {
            avoidance.setManuallyHidden(false, origin: avoidance.home ?? panel.frame.origin)
            panel.orderOut(nil)
            refreshMenu()
            return
        }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        avoidance = PetAvoidance()
        avoidance.duration = flightSpeed.duration
        panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.maxX - panel.frame.width - 48, y: screen.visibleFrame.minY + 4))
        baseY = panel.frame.minY
        petView.sprite = idle
        checkFullscreen(initial: true)
        if isVisible { panel.orderFrontRegardless() }
        savePosition()
        refreshMenu()
    }
    @objc func showHelp() {
        let alert = NSAlert()
        alert.messageText = "伊蕾娜桌寵"
        alert.informativeText = "拖曳角色：移動位置\n點一下：打招呼\n雙擊：掃帚短飛到新位置\n右鍵或選單列 ✦：調整大小、散步、暫停、隱藏或結束\n\n位置、大小與散步設定會自動記住。"
        alert.addButton(withTitle: "知道了")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    @objc func quit() { savePosition(); NSApp.terminate(nil) }

    // Available only in a fully isolated test process; no production IPC control surface.
    func receiveTestControl(_ notification: Notification) {
        guard PetPreferences.isolated, let info = notification.userInfo,
              let token = info["token"] as? String, let command = info["command"] as? String else { return }
        switch command {
        case "dismiss": cancelTransientActivity()
        case "hide": if !avoidance.manuallyHidden { toggleVisible() }
        case "unhide": if avoidance.manuallyHidden { toggleVisible() }
        case "show": showPet()
        case "pause": if !paused { togglePause() }
        case "resume": if paused { togglePause() }
        case "fullscreen-on": testFullscreenOverride = true; checkFullscreen()
        case "fullscreen-off": testFullscreenOverride = false; checkFullscreen()
        case "greet": greet()
        case "jump": jump()
        case "menu-open": menuOpen = true; cancelThought()
        case "menu-close": menuOpen = false
        case "clear-defaults":
            if let suite = ProcessInfo.processInfo.environment["ELAINA_DEFAULTS_SUITE"] {
                defaults.removePersistentDomain(forName: suite)
                testDefaultsCleared = true
            }
        default: break
        }
        DistributedNotificationCenter.default().postNotificationName(PetNotifications.testAcknowledgement,
            object: PetNotifications.object,
            userInfo: ["token": token, "screens": NSScreen.screens.count, "firstGreetingIssued": firstGreetingIssued,
                       "bubbleVisible": bubble.isVisible, "reactionActive": reactionDeadline > CACurrentMediaTime(),
                       "phase": String(describing: avoidance.phase), "manuallyHidden": avoidance.manuallyHidden,
                       "panelVisible": panel.isVisible, "paused": paused, "jumping": jumpStarted != nil,
                       "x": panel.frame.minX, "y": panel.frame.minY,
                       "homeX": avoidance.home?.x ?? panel.frame.minX, "homeY": avoidance.home?.y ?? baseY],
            deliverImmediately: true)
        if command == "quit" { DispatchQueue.main.async { self.quit() } }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var pet: PetController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep only one copy so repeated double-clicks cannot create invisible duplicate pets.
        let identifier = Bundle.main.bundleIdentifier ?? "local.elaina.desktop-pet"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if PetPreferences.isolated {
            // The IPC namespace, defaults suite and dialogue directory are all separate.
        } else if CommandLine.arguments.contains("--replace-running"), !others.isEmpty {
            for running in others { running.terminate() }
            let deadline = Date().addingTimeInterval(4)
            while others.contains(where: { !$0.isTerminated }) && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            if others.contains(where: { !$0.isTerminated }) { NSApp.terminate(nil); return }
        } else if let running = others.first {
            running.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
            return
        }
        guard let root = Bundle.main.resourceURL,
              let idle = Sprite(url: root.appendingPathComponent("idle.png")) else {
            let alert = NSAlert()
            alert.messageText = "無法載入伊蕾娜的角色素材"
            alert.informativeText = "請保留完整的 Elaina.app，或使用 build.sh 重新建立程式。"
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        let walkFrames = (0..<4).compactMap { Sprite(url: root.appendingPathComponent("walk_\($0).png")) }
        guard let data = try? Data(contentsOf: root.appendingPathComponent("broom-animation.json")),
              let animation = try? JSONDecoder().decode(PetBroomAnimation.self, from: data), animation.isValid else {
            fputs("Invalid broom animation metadata\n", stderr); NSApp.terminate(nil); return
        }
        let broomFrames = animation.order.compactMap { Sprite(url: root.appendingPathComponent("broom_\($0).png"), preserveCanvas: true) }
        guard broomFrames.count == animation.frameCount,
              broomFrames.allSatisfy({ $0.bitmap.hasAlpha && $0.bitmap.pixelsWide == animation.frameWidth && $0.bitmap.pixelsHigh == animation.frameHeight }) else {
            fputs("Invalid broom frames\n", stderr); NSApp.terminate(nil); return
        }
        guard let lifeData = try? Data(contentsOf: root.appendingPathComponent("life-animation.json")),
              let lifeAnimations = try? JSONDecoder().decode([String: PetLifeAnimation].self, from: lifeData),
              Set(lifeAnimations.keys) == Set(["grab", "held", "release", "annoyed", "eating"]),
              lifeAnimations.values.allSatisfy({ $0.isValid }) else {
            fputs("Invalid life animation metadata\n", stderr); NSApp.terminate(nil); return
        }
        var lifeSprites: [String: [Sprite]] = [:]
        for (key, animation) in lifeAnimations {
            let frames = animation.frames.compactMap { Sprite(url: root.appendingPathComponent($0.file), preserveCanvas: true) }
            guard frames.count == animation.frames.count,
                  frames.allSatisfy({ $0.bitmap.hasAlpha && $0.bitmap.pixelsWide == animation.frameWidth &&
                    $0.bitmap.pixelsHigh == animation.frameHeight }) else {
                fputs("Invalid life animation frames\n", stderr); NSApp.terminate(nil); return
            }
            lifeSprites[key] = frames
        }
        pet = PetController(idle: idle, walkFrames: walkFrames, broomFrames: broomFrames,
                            broomFrameDuration: Double(animation.frameDurationMs) / 1000,
                            lifeAnimations: lifeAnimations, lifeSprites: lifeSprites)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        pet?.showPet()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) { pet?.savePosition() }
}

#if !ELAINA_SPEECH_TEST
@main
struct ElainaMain {
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            guard let root = Bundle.main.resourceURL else { fputs("Missing bundle resources\n", stderr); exit(1) }
            guard let font = PetSpeechMetrics.bundledFont, font.fontName == "Cubic_11",
                  FileManager.default.fileExists(atPath: root.appendingPathComponent("Fonts/OFL.txt").path) else {
                fputs("Missing pixel font or license\n", stderr); exit(1)
            }
            print("PASS bundled Cubic 11 and complete license, process-only font loading")
            for filename in ["idle.png", "walk_0.png", "walk_1.png", "walk_2.png", "walk_3.png"] {
                guard let sprite = Sprite(url: root.appendingPathComponent(filename)), sprite.bitmap.hasAlpha else {
                    fputs("Invalid sprite: \(filename)\n", stderr); exit(1)
                }
                print("PASS \(filename): \(sprite.bitmap.pixelsWide)x\(sprite.bitmap.pixelsHigh), alpha present")
            }
            guard let data = try? Data(contentsOf: root.appendingPathComponent("broom-animation.json")),
                  let animation = try? JSONDecoder().decode(PetBroomAnimation.self, from: data), animation.isValid else {
                fputs("Invalid broom animation metadata\n", stderr); exit(1)
            }
            for index in animation.order {
                let filename = "broom_\(index).png"
                guard let sprite = Sprite(url: root.appendingPathComponent(filename), preserveCanvas: true),
                      sprite.bitmap.hasAlpha, sprite.bitmap.pixelsWide == animation.frameWidth,
                      sprite.bitmap.pixelsHigh == animation.frameHeight,
                      sprite.source == CGRect(x: 0, y: 0, width: animation.frameWidth, height: animation.frameHeight) else {
                    fputs("Invalid fixed-canvas sprite: \(filename)\n", stderr); exit(1)
                }
                print("PASS \(filename): common \(animation.frameWidth)x\(animation.frameHeight) canvas")
            }
            print("PASS broom order, 180ms timing, nearest interpolation and mirroring metadata")
            guard let lifeData = try? Data(contentsOf: root.appendingPathComponent("life-animation.json")),
                  let groups = try? JSONDecoder().decode([String: PetLifeAnimation].self, from: lifeData),
                  Set(groups.keys) == Set(["grab", "held", "release", "annoyed", "eating"]),
                  groups.values.allSatisfy({ $0.isValid }) else {
                fputs("Invalid life metadata\n", stderr); exit(1)
            }
            for (key, group) in groups.sorted(by: { $0.key < $1.key }) {
                for (index, frame) in group.frames.enumerated() {
                    guard let sprite = Sprite(url: root.appendingPathComponent(frame.file), preserveCanvas: true),
                          sprite.bitmap.hasAlpha, sprite.bitmap.pixelsWide == group.frameWidth,
                          sprite.bitmap.pixelsHigh == group.frameHeight,
                          sprite.source == CGRect(x: 0, y: 0, width: group.frameWidth, height: group.frameHeight) else {
                        fputs("Invalid life sprite\n", stderr); exit(1)
                    }
                    var visible = CGRect.null
                    for y in stride(from: 0, to: group.frameHeight, by: 4) {
                        for x in stride(from: 0, to: group.frameWidth, by: 4) where
                            (sprite.bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.08 {
                            visible = visible.union(CGRect(x: x, y: group.frameHeight - 1 - y, width: 1, height: 1))
                        }
                    }
                    guard !visible.isNull else { fputs("Empty life sprite\n", stderr); exit(1) }
                    for height in PetSizing.presets.map({ CGFloat($0.height) }) + [70, 140] {
                        let size = PetLifeAnimation.canvasSize(height: height)
                        for mirrored in [false, true] {
                            for tilt in (group.hanging ? [-PetHeldSway.limit, 0, PetHeldSway.limit] : [0]) {
                                let placement = group.placement(frame: index, size: size, height: height,
                                    mirrored: mirrored, tilt: CGFloat(tilt))
                                let affine = NSAffineTransform()
                                let pivot = placement.displayPivot
                                affine.translateX(by: pivot.x, yBy: pivot.y)
                                affine.rotate(byRadians: placement.tilt)
                                affine.translateX(by: -pivot.x, yBy: -pivot.y)
                                if mirrored { affine.translateX(by: size.width, yBy: 0); affine.scaleX(by: -1, yBy: 1) }
                                for source in [CGPoint(x: visible.minX, y: visible.minY), CGPoint(x: visible.maxX, y: visible.minY),
                                               CGPoint(x: visible.minX, y: visible.maxY), CGPoint(x: visible.maxX, y: visible.maxY)] {
                                    let point = CGPoint(x: placement.rect.minX + source.x / CGFloat(group.frameWidth) * placement.rect.width,
                                                        y: placement.rect.minY + source.y / CGFloat(group.frameHeight) * placement.rect.height)
                                    let displayed = placement.display(point)
                                    let actual = affine.transform(point)
                                    let inverse = placement.source(displayed)
                                    guard displayed.x >= 0 && displayed.y >= 0 && displayed.x <= size.width && displayed.y <= size.height,
                                          hypot(actual.x - displayed.x, actual.y - displayed.y) < 0.0001,
                                          hypot(inverse.x - point.x, inverse.y - point.y) < 0.0001 else {
                                        fputs("Life placement clips or mismatches at \(frame.file) / \(height) / \(tilt)\n", stderr); exit(1)
                                    }
                                }
                                let opaque = CGPoint(x: placement.rect.minX + visible.midX / CGFloat(group.frameWidth) * placement.rect.width,
                                    y: placement.rect.minY + visible.midY / CGFloat(group.frameHeight) * placement.rect.height)
                                let recovered = placement.source(placement.display(opaque))
                                guard sprite.contains(opaque, in: placement.rect, mirrored: false) ==
                                      sprite.contains(recovered, in: placement.rect, mirrored: false) else {
                                    fputs("Alpha hit inverse mismatches\n", stderr); exit(1)
                                }
                            }
                        }
                    }
                }
                print("PASS \(key): fixed canvas, timing, all sizes, mirror, tilt and alpha inverse")
            }
            print("PASS bundle resources")
            exit(0)
        }
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
#endif
