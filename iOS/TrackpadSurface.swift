import UIKit
import SwiftUI

/// Adapted from the Duo GameFill template: the viewport follows live bounds in every pose.
struct TrackpadSurface: UIViewControllerRepresentable {
    @ObservedObject var model: TrackpadModel
    func makeUIViewController(context: Context) -> TrackpadController { TrackpadController(model: model) }
    func updateUIViewController(_ controller: TrackpadController, context: Context) { controller.refresh() }
}

final class TrackpadController: UIViewController {
    private let model: TrackpadModel
    private let surface = TouchSurface()
    private let status = UILabel()
    private let dot = UIView()
    private let pill = UIView()
    private let titleLabel = UILabel()
    private let subtitle = UILabel()
    private let hint = UILabel()
    private let mark = UIImageView(image: UIImage(systemName: "rectangle.and.hand.point.up.left"))
    private let gradient = CAGradientLayer()
    private let border = CAShapeLayer()
    private var touchActive = false
    private let clickFeedback = UIImpactFeedbackGenerator(style: .soft)

    init(model: TrackpadModel) { self.model = model; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("Unsupported") }
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func loadView() { view = surface }
    override func viewDidLoad() {
        super.viewDidLoad()
        gradient.colors = [UIColor(white: 0.98, alpha: 1).cgColor, UIColor(red: 0.87, green: 0.89, blue: 0.91, alpha: 1).cgColor, UIColor(white: 0.96, alpha: 1).cgColor]
        gradient.locations = [0, 0.65, 1]
        gradient.startPoint = CGPoint(x: 0, y: 0); gradient.endPoint = CGPoint(x: 1, y: 1)
        surface.layer.insertSublayer(gradient, at: 0)
        border.strokeColor = UIColor.white.withAlphaComponent(0.8).cgColor
        border.fillColor = UIColor.clear.cgColor; border.lineWidth = 1
        surface.layer.addSublayer(border)
        pill.backgroundColor = UIColor.white.withAlphaComponent(0.63)
        pill.layer.cornerRadius = 23; pill.layer.borderWidth = 0.5
        pill.layer.borderColor = UIColor.white.cgColor
        dot.layer.cornerRadius = 3
        status.font = .systemFont(ofSize: 13, weight: .medium)
        status.textColor = UIColor(white: 0.30, alpha: 1)
        titleLabel.font = .systemFont(ofSize: 28, weight: .light)
        titleLabel.text = "Duo Trackpad"; titleLabel.textColor = UIColor(white: 0.34, alpha: 1)
        subtitle.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        subtitle.textColor = UIColor(white: 0.50, alpha: 1)
        mark.tintColor = UIColor(white: 0.48, alpha: 0.75); mark.contentMode = .scaleAspectFit
        hint.font = .systemFont(ofSize: 12, weight: .regular)
        hint.textColor = UIColor(white: 0.46, alpha: 1); hint.textAlignment = .center; hint.numberOfLines = 0
        for item in [pill, titleLabel, subtitle, mark, hint] { item.isUserInteractionEnabled = false; surface.addSubview(item) }
        pill.addSubview(dot); pill.addSubview(status)
        surface.onInput = { [weak self] input in
            guard let self else { return }
            if self.model.connected {
                self.model.send(input)
                if [.leftClick, .rightClick, .dragStart].contains(input.kind), self.model.haptics {
                    self.clickFeedback.impactOccurred(intensity: 0.6)
                }
            } else if input.kind == .leftClick { self.model.showSettings = true }
        }
        surface.onControls = { [weak self] in self?.model.send(.init(.stop)); self?.model.showSettings = true }
        surface.onActivity = { [weak self] active in
            guard let self else { return }
            self.touchActive = active
            UIView.animate(withDuration: 0.3) {
                for item in [self.titleLabel, self.subtitle, self.mark, self.hint] { item.alpha = active ? 0.15 : 1 }
            }
        }
        surface.isAccessibilityElement = true
        surface.accessibilityLabel = "Duo Trackpad"
        surface.accessibilityHint = "Move with one finger, scroll with two. Four-finger tap opens controls. VoiceOver users can use the Connection settings action."
        surface.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Connection settings", actionHandler: { [weak self] _ in self?.model.showSettings = true; return true })]
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted), name: UIApplication.willResignActiveNotification, object: nil)
        refresh()
    }

    @objc private func interrupted() { surface.cancelGesture(); model.send(.init(.stop)) }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        interrupted()
        super.viewWillTransition(to: size, with: coordinator)
    }

    func refresh() {
        guard isViewLoaded else { return }
        surface.threeFingerDrag = model.threeFingerDrag
        status.text = model.connecting ? "Connecting…" : model.connected ? model.hostName : "Connect to your Mac  ↗"
        if model.connected, model.hostPermission == false { status.text = "Allow mouse control on your Mac" }
        dot.backgroundColor = model.connected ? UIColor(red: 0.25, green: 0.56, blue: 0.44, alpha: 1) : UIColor(white: 0.55, alpha: 1)
        subtitle.text = model.connected ? "ENCRYPTED · LOCAL CONNECTION" : "A LITTLE CLOSER TO YOUR MAC"
        hint.text = model.connected ? "One finger to move · Two to scroll\nFour-finger tap for controls" : "The whole surface is yours.\nTap anywhere to connect."
        if model.connected, model.hostPermission == false { hint.text = "Enable Accessibility for Duo Receiver on your Mac.\nFour-finger tap for controls" }
        surface.accessibilityValue = model.connected ? "Connected to \(model.hostName)" : "Disconnected"
        view.setNeedsLayout()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        gradient.frame = view.bounds
        border.path = UIBezierPath(roundedRect: view.bounds.insetBy(dx: 8, dy: 8), cornerRadius: 30).cgPath
        let safe = view.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 20, dy: 16)
        let reserved = view.reservedRegions(kind: .division).filter(\.isActive).map(\.frame) + view.reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        func avoid(_ rect: CGRect) -> CGRect {
            var result = rect
            for region in reserved where result.intersects(region) {
                let above = region.minY - result.height - 12
                let below = region.maxY + 12
                result.origin.y = above >= safe.minY ? above : below
                if result.maxY > safe.maxY {
                    result.origin.y = max(safe.minY, min(rect.minY, safe.maxY - rect.height))
                    result.origin.x = rect.midX < region.midX ? region.minX - result.width - 12 : region.maxX + 12
                }
                result.origin.x = min(max(result.minX, safe.minX), max(safe.minX, safe.maxX - result.width))
            }
            return result
        }
        let labelWidth = min(status.intrinsicContentSize.width, max(0, safe.width - 60))
        pill.frame = avoid(CGRect(x: safe.midX - (labelWidth + 52) / 2, y: safe.minY + 4, width: labelWidth + 52, height: 46))
        dot.frame = CGRect(x: 18, y: 20, width: 6, height: 6)
        status.frame = CGRect(x: 33, y: 0, width: labelWidth, height: 46)
        let groupWidth = min(safe.width, max(titleLabel.intrinsicContentSize.width, subtitle.intrinsicContentSize.width) + 16)
        let group = avoid(CGRect(x: safe.midX - groupWidth / 2, y: safe.midY - 60, width: groupWidth, height: 120))
        mark.frame = CGRect(x: group.midX - 20, y: group.minY, width: 40, height: 40)
        titleLabel.sizeToFit(); titleLabel.center = CGPoint(x: group.midX, y: group.minY + 73)
        subtitle.sizeToFit(); subtitle.center = CGPoint(x: group.midX, y: group.minY + 106)
        let hintWidth = min(safe.width, hint.sizeThatFits(CGSize(width: safe.width, height: .greatestFiniteMagnitude)).width + 16)
        hint.frame = avoid(CGRect(x: safe.midX - hintWidth / 2, y: safe.maxY - 50, width: hintWidth, height: 42))
        // Fold/camera exclusions come from live UIKit reserved regions, never device dimensions.
        surface.excludedRegions = reserved
    }
}

final class TouchSurface: UIView {
    var onInput: ((Wire.Input) -> Void)?
    var onControls: (() -> Void)?
    var onActivity: ((Bool) -> Void)?
    var excludedRegions: [CGRect] = []
    var threeFingerDrag = false
    private var engine = GestureEngine()
    private var contacts: [UITouch: Int] = [:]
    private var nextID = 0
    private var hold: DispatchWorkItem?
    private var rings: [UITouch: CAShapeLayer] = [:]
    private var ringPool: [CAShapeLayer] = []
    private var pendingSecondaryClick: DispatchWorkItem?

    override init(frame: CGRect) {
        super.init(frame: frame); isMultipleTouchEnabled = true
        backgroundColor = .systemGray6
        for _ in 0..<5 {
            let ring = CAShapeLayer()
            ring.path = UIBezierPath(ovalIn: CGRect(x: -24, y: -24, width: 48, height: 48)).cgPath
            ring.fillColor = UIColor.white.withAlphaComponent(0.23).cgColor
            ring.strokeColor = UIColor.white.withAlphaComponent(0.7).cgColor; ring.lineWidth = 1
            ring.isHidden = true; layer.addSublayer(ring); ringPool.append(ring)
        }
        engine.onInput = { [weak self] input in self?.emit(input) }
        engine.onControls = { [weak self] in self?.onControls?() }
    }
    required init?(coder: NSCoder) { fatalError("Unsupported") }

    private func emit(_ input: Wire.Input) {
        if input.kind == .rightClick {
            pendingSecondaryClick?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.onInput?(input); self?.pendingSecondaryClick = nil }
            pendingSecondaryClick = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
        } else {
            if input.kind == .action, input.x == Double(MacAction.resetZoom.rawValue) {
                pendingSecondaryClick?.cancel(); pendingSecondaryClick = nil
            } else if [.move, .dragStart, .scrollBegin, .action].contains(input.kind) {
                flushSecondaryClick()
            }
            onInput?(input)
        }
    }

    private func flushSecondaryClick() {
        guard let pendingSecondaryClick else { return }
        pendingSecondaryClick.perform(); pendingSecondaryClick.cancel(); self.pendingSecondaryClick = nil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let wasEmpty = contacts.isEmpty
        var additions: [(Int, TouchPoint)] = []
        for touch in touches where contacts.count < 5 {
            let point = touch.location(in: self)
            guard !excludedRegions.contains(where: { $0.contains(point) }) else { continue }
            nextID &+= 1; contacts[touch] = nextID
            additions.append((nextID, .init(x: point.x, y: point.y)))
            if let ring = ringPool.popLast() { rings[touch] = ring; ring.isHidden = false; drawRing(touch, at: point) }
        }
        guard !additions.isEmpty else { return }
        if wasEmpty, additions.count != 2 { flushSecondaryClick() }
        if wasEmpty { onActivity?(true); onInput?(.init(.stop)) }
        engine.threeFingerDrag = threeFingerDrag
        let time = touches.map(\.timestamp).max() ?? ProcessInfo.processInfo.systemUptime
        engine.began(additions, time: time, rightEdge: bounds.maxX)
        hold?.cancel()
        if contacts.count == 1 {
            let work = DispatchWorkItem { [weak self] in self?.engine.hold(time: ProcessInfo.processInfo.systemUptime) }
            hold = work; DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        var updates: [(Int, TouchPoint)] = []
        var timestamp = 0.0
        for touch in touches {
            guard let id = contacts[touch] else { continue }
            // The newest coalesced sample minimizes age. Do not replay historical samples into a live cursor.
            let newest = event?.coalescedTouches(for: touch)?.last ?? touch
            let point = newest.location(in: self)
            timestamp = max(timestamp, newest.timestamp)
            updates.append((id, .init(x: point.x, y: point.y)))
            drawRing(touch, at: point)
        }
        guard !updates.isEmpty else { return }
        // A crossing cancels this gesture, preventing a jump across an active fold/camera exclusion.
        if updates.contains(where: { sample in excludedRegions.contains { $0.contains(CGPoint(x: sample.1.x, y: sample.1.y)) } }) {
            engine.cancel(); hold?.cancel(); return
        }
        engine.move(updates, time: timestamp)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: false) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { end(touches, cancelled: true) }
    private func end(_ touches: Set<UITouch>, cancelled: Bool) {
        hold?.cancel()
        let ids = touches.compactMap { contacts[$0] }
        engine.ended(ids, time: touches.map(\.timestamp).max() ?? ProcessInfo.processInfo.systemUptime, cancelled: cancelled)
        for touch in touches {
            contacts.removeValue(forKey: touch)
            if let ring = rings.removeValue(forKey: touch) { ring.isHidden = true; ringPool.append(ring) }
        }
        if contacts.isEmpty { onActivity?(false) }
    }
    func cancelGesture() {
        hold?.cancel(); pendingSecondaryClick?.cancel(); pendingSecondaryClick = nil; engine.cancel()
        contacts.removeAll(keepingCapacity: true)
        for ring in rings.values { ring.isHidden = true; ringPool.append(ring) }
        rings.removeAll(keepingCapacity: true); onActivity?(false)
    }
    private func drawRing(_ touch: UITouch, at point: CGPoint) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        rings[touch]?.position = point
        CATransaction.commit()
    }
    override func didMoveToWindow() { super.didMoveToWindow(); if window == nil { cancelGesture() } }
}
