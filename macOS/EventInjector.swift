import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Confined to PeerChannel.queue. Display topology and permission checks are cached off the motion path.
final class EventInjector: @unchecked Sendable {
    private let source = CGEventSource(stateID: .hidSystemState)
    private var dragging = false
    private var lastClickTime = 0.0
    private var lastClickPoint = CGPoint.zero
    private var lastClickWasRight = false
    private var clickCount: Int64 = 0
    private var scrollRemainder = CGPoint.zero
    private var rectangles: [CGRect] = []
    private var allowed = false
    private var momentum: DispatchSourceTimer?
    private var scrolling = false
    private var zoomRemainder = 0.0
    private var rotationRemainder = 0.0
    private var displayObserver: NSObjectProtocol?
    var onControlError: ((String) -> Void)?

    init() {
        source?.localEventsSuppressionInterval = 0
        allowed = AXIsProcessTrusted()
        refreshDisplays()
        displayObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            PeerChannel.queue.async { self?.refreshDisplays() }
        }
    }
    deinit { if let displayObserver { NotificationCenter.default.removeObserver(displayObserver) }; momentum?.cancel() }
    func setTrusted(_ value: Bool) { allowed = value; if !value { release() } }

    func consume(_ input: Wire.Input) {
        if input.kind == .stop { release(); return }
        guard allowed else { return }
        switch input.kind {
        case .move:
            guard let position = CGEvent(source: source)?.location else { return }
            let destination = constrain(CGPoint(x: position.x + input.x, y: position.y + input.y))
            let event = CGEvent(mouseEventSource: source, mouseType: dragging ? .leftMouseDragged : .mouseMoved, mouseCursorPosition: destination, mouseButton: .left)
            event?.setIntegerValueField(.mouseEventDeltaX, value: Int64(destination.x - position.x))
            event?.setIntegerValueField(.mouseEventDeltaY, value: Int64(destination.y - position.y))
            event?.post(tap: .cghidEventTap)
        case .scrollBegin:
            cancelMomentum(); scrolling = true; scrollRemainder = .zero
            scroll(x: 0, y: 0, phase: 1)
        case .scroll:
            scroll(x: input.x, y: input.y, phase: scrolling ? 2 : 0)
        case .scrollEnd:
            if scrolling { scroll(x: 0, y: 0, phase: 4); scrolling = false }
            startMomentum(x: input.x, y: input.y)
        case .leftClick, .rightClick:
            guard !dragging, let position = CGEvent(source: source)?.location else { return }
            cancelMomentum()
            let right = input.kind == .rightClick
            updateClickCount(at: position, right: right)
            post(right ? .rightMouseDown : .leftMouseDown, at: position, button: right ? .right : .left, clicks: clickCount)
            post(right ? .rightMouseUp : .leftMouseUp, at: position, button: right ? .right : .left, clicks: clickCount)
        case .dragStart:
            guard !dragging, let position = CGEvent(source: source)?.location else { return }
            cancelMomentum(); dragging = true; updateClickCount(at: position, right: false)
            post(.leftMouseDown, at: position, clicks: clickCount)
        case .dragEnd:
            if dragging, let position = CGEvent(source: source)?.location { post(.leftMouseUp, at: position, clicks: clickCount) }
            dragging = false
        case .action:
            guard input.x.rounded() == input.x, let action = MacAction(rawValue: Int(input.x)) else { return }
            release(); perform(action)
        case .zoom:
            zoomRemainder += input.x
            if abs(zoomRemainder) >= 0.10 {
                perform(zoomRemainder > 0 ? .zoomIn : .zoomOut); zoomRemainder = 0
            }
        case .rotate:
            rotationRemainder += input.x
            if abs(rotationRemainder) >= 18 {
                let clockwise = rotationRemainder > 0; rotationRemainder = 0
                DispatchQueue.main.async { [weak self] in self?.performMenuAction(clockwise ? ["rotate right", "rotate clockwise"] : ["rotate left", "rotate counterclockwise"]) }
            }
        default: break
        }
    }

    func release() {
        if dragging, let position = CGEvent(source: source)?.location { post(.leftMouseUp, at: position, clicks: clickCount) }
        dragging = false
        if scrolling { scroll(x: 0, y: 0, phase: 8); scrolling = false }
        cancelMomentum(); scrollRemainder = .zero; zoomRemainder = 0; rotationRemainder = 0
    }
    private func updateClickCount(at position: CGPoint, right: Bool) {
        let now = ProcessInfo.processInfo.systemUptime
        if right == lastClickWasRight, now - lastClickTime < NSEvent.doubleClickInterval,
           hypot(position.x - lastClickPoint.x, position.y - lastClickPoint.y) < 5 {
            clickCount = min(3, clickCount + 1)
        } else { clickCount = 1 }
        lastClickTime = now; lastClickPoint = position; lastClickWasRight = right
    }
    private func scroll(x: Double, y: Double, phase: Int64 = 0, momentumPhase: Int64 = 0) {
        scrollRemainder.x += x; scrollRemainder.y += y
        let integralX = Int32(scrollRemainder.x), integralY = Int32(scrollRemainder.y)
        scrollRemainder.x -= CGFloat(integralX); scrollRemainder.y -= CGFloat(integralY)
        guard integralX != 0 || integralY != 0 || phase != 0 || momentumPhase != 0 else { return }
        let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: integralY, wheel2: integralX, wheel3: 0)
        event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        event?.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentumPhase)
        event?.post(tap: .cghidEventTap)
    }
    private func startMomentum(x: Double, y: Double) {
        cancelMomentum()
        guard hypot(x, y) > 80 else { return }
        var vx = x, vy = y, first = true
        var previous = ProcessInfo.processInfo.systemUptime
        let timer = DispatchSource.makeTimerSource(queue: PeerChannel.queue)
        timer.schedule(deadline: .now() + 1.0 / 120, repeating: 1.0 / 120, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let now = ProcessInfo.processInfo.systemUptime, dt = min(0.04, now - previous); previous = now
            self.scroll(x: vx * dt, y: vy * dt, momentumPhase: first ? 1 : 2); first = false
            let damping = exp(-7.5 * dt); vx *= damping; vy *= damping
            if hypot(vx, vy) < 10 { self.cancelMomentum() }
        }
        momentum = timer; timer.resume()
    }
    private func cancelMomentum() {
        if let momentum { momentum.cancel(); self.momentum = nil; scroll(x: 0, y: 0, momentumPhase: 3) }
    }
    private func post(_ type: CGEventType, at point: CGPoint, button: CGMouseButton = .left, clicks: Int64 = 1) {
        let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
        event?.setIntegerValueField(.mouseEventClickState, value: clicks); event?.post(tap: .cghidEventTap)
    }
    private func key(_ code: Int, flags: CGEventFlags = []) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(code), keyDown: down)
            event?.flags = flags; event?.post(tap: .cghidEventTap)
        }
    }
    private func perform(_ action: MacAction) {
        switch action {
        case .missionControl: key(kVK_UpArrow, flags: .maskControl)
        case .appExpose: key(kVK_DownArrow, flags: .maskControl)
        case .previousSpace: key(kVK_LeftArrow, flags: .maskControl)
        case .nextSpace: key(kVK_RightArrow, flags: .maskControl)
        case .showDesktop: key(kVK_F11)
        case .apps: DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Apps.app")) }
        case .spotlight: key(kVK_Space, flags: .maskCommand)
        case .back: key(kVK_ANSI_LeftBracket, flags: .maskCommand)
        case .forward: key(kVK_ANSI_RightBracket, flags: .maskCommand)
        case .zoomIn: key(kVK_ANSI_Equal, flags: .maskCommand)
        case .zoomOut: key(kVK_ANSI_Minus, flags: .maskCommand)
        case .resetZoom: key(kVK_ANSI_0, flags: .maskCommand)
        case .lookUp: key(kVK_ANSI_D, flags: [.maskCommand, .maskControl])
        case .appSwitcher: key(kVK_Tab, flags: .maskCommand)
        case .notificationCenter: DispatchQueue.main.async { [weak self] in self?.openNotificationCenter() }
        }
    }
    /// Menu actions are app-provided operations, not synthetic native rotation events.
    private func performMenuAction(_ titles: [String]) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXMenuBarAttribute as CFString, &value) == .success, let value else { return }
        var remaining = 512
        if let item = findElement(value as! AXUIElement, depth: 0, remaining: &remaining, match: { title, _ in titles.contains(title.lowercased().replacingOccurrences(of: "…", with: "")) }) {
            AXUIElementPerformAction(item, kAXPressAction as CFString)
        } else { onControlError?("This app does not expose a Rotate menu command. Rotation is available in apps such as Preview.") }
    }
    private func openNotificationCenter() {
        for name in ["com.apple.controlcenter", "com.apple.SystemUIServer"] {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: name).first else { continue }
            let element = AXUIElementCreateApplication(app.processIdentifier)
            var remaining = 256
            if let clock = findElement(element, depth: 0, remaining: &remaining, match: { title, identifier in
                title.lowercased().contains("notification center") || identifier.lowercased().contains("clock")
            }) {
                AXUIElementPerformAction(clock, kAXPressAction as CFString); return
            }
        }
        onControlError?("Notification Center's menu-bar control is unavailable on this Mac.")
    }
    private func findElement(_ element: AXUIElement, depth: Int, remaining: inout Int, match: (String, String) -> Bool) -> AXUIElement? {
        guard depth < 10, remaining > 0 else { return nil }; remaining -= 1
        func string(_ attribute: String) -> String {
            var value: CFTypeRef?; AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            return value as? String ?? ""
        }
        if match(string(kAXTitleAttribute), string(kAXIdentifierAttribute)) { return element }
        for attribute in [kAXChildrenAttribute, kAXMenuBarAttribute, kAXExtrasMenuBarAttribute] {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { continue }
            let children: [AXUIElement]
            if let array = value as? [AXUIElement] { children = array }
            else if let value, CFGetTypeID(value) == AXUIElementGetTypeID() { children = [value as! AXUIElement] }
            else { continue }
            for child in children { if let result = findElement(child, depth: depth + 1, remaining: &remaining, match: match) { return result } }
        }
        return nil
    }
    private func refreshDisplays() {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return }
        rectangles = displays.prefix(Int(count)).map { CGDisplayBounds($0) }
    }
    private func constrain(_ point: CGPoint) -> CGPoint {
        var nearest = point, best = Double.infinity
        for rect in rectangles {
            if rect.contains(point) { return point }
            let candidate = CGPoint(x: min(max(point.x, rect.minX), rect.maxX - 1), y: min(max(point.y, rect.minY), rect.maxY - 1))
            let distance = (candidate.x - point.x) * (candidate.x - point.x) + (candidate.y - point.y) * (candidate.y - point.y)
            if distance < best { best = distance; nearest = candidate }
        }
        return nearest
    }
}
