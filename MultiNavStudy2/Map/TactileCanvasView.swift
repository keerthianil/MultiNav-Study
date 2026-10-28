// TactileCanvasView.swift
// The touch surface for every map.
//
// Touches are read directly (touchesBegan/Moved/Ended) whether or not
// VoiceOver is on, so exploration behaves the same in both modes. Under
// VoiceOver the view is a direct-touch element that stays silent on touch,
// which hands every finger movement to the map instead of to VoiceOver.
//
// Gestures, each recognised once however it arrives:
//   double tap                      the information items: play or stop
//   two-finger double tap           the announcement: play again or stop
//                                   (VoiceOver: the magic tap)
//   three-finger swipe up / down    next / previous information item
//                                   (VoiceOver: three-finger scroll)
//   three-finger swipe right        finished exploring
//                                   (VoiceOver: also the escape gesture)

import UIKit

@MainActor
protocol MapScene: AnyObject {
    /// Reference drawing area in mm.
    var mapSize: CGSize { get }
    /// True when map (0, 0) is the centre of the drawing area.
    var isCentered: Bool { get }
    /// White, or black while the map is hidden.
    var fillColor: UIColor { get }
    func draw(in context: CGContext, transform: MapTransform)
}

enum CanvasTouchPhase {
    case began, moved, ended, cancelled
}

@MainActor
protocol TactileCanvasDelegate: AnyObject {
    func canvas(_ canvas: TactileCanvasView, touch phase: CanvasTouchPhase, mm: CGPoint, screen: CGPoint)
    func canvas(_ canvas: TactileCanvasView, singleTapAt mm: CGPoint, screen: CGPoint)
    func canvas(_ canvas: TactileCanvasView, doubleTapAt mm: CGPoint, screen: CGPoint)
    func canvasTwoFingerDoubleTap(_ canvas: TactileCanvasView, gesture: String)
    func canvasRequestsFinish(_ canvas: TactileCanvasView, gesture: String)
    /// Next (forward) or previous information item. Returns false when there
    /// is none that way, so VoiceOver can play its boundary sound.
    /// `voiceOverScroll` is true when VoiceOver sent the gesture as a scroll.
    func canvasRequestsItem(_ canvas: TactileCanvasView, forward: Bool, gesture: String,
                            voiceOverScroll: Bool) -> Bool
}

final class TactileCanvasView: UIView {
    weak var delegate: TactileCanvasDelegate?

    var scene: MapScene? {
        didSet { setNeedsLayout(); setNeedsDisplay() }
    }

    /// Insets of the navigation bar and home indicator, supplied by SwiftUI.
    var contentInsets: UIEdgeInsets = .zero {
        didSet {
            if contentInsets != oldValue { setNeedsLayout() }
        }
    }

    private(set) var mapTransform = MapTransform()

    // One-finger tracking.
    private var activeTouch: UITouch?
    private var touchStart: CGPoint = .zero
    private var touchStartTime: TimeInterval = 0
    private var sequenceHadExtraFingers = false
    private var lastTapTime: TimeInterval = 0
    private var lastTapPoint: CGPoint = .zero
    private var pendingSingleTap: DispatchWorkItem?

    // Multi-finger tracking, from the first finger down to the last one up.
    private var mostFingers = 0
    private var fingersStartTime: TimeInterval = 0
    private var fingersStart: CGPoint = .zero
    private var fingersMoved: CGFloat = 0
    private var lastTwoFingerTap: TimeInterval = 0
    private var lastTwoFingerDoubleTap: TimeInterval = 0
    private var threeFingerStart: CGPoint?
    private var lastThreeFingerAction: TimeInterval = 0

    private let tapMaxDisplacement: CGFloat = 28
    private let tapMaxDuration: TimeInterval = 0.45
    private let doubleTapMaxInterval: TimeInterval = 0.45
    private let doubleTapMaxDistance: CGFloat = 48
    private let twoFingerTapMaxDuration: TimeInterval = 0.4
    private let twoFingerDoubleTapInterval: TimeInterval = 0.5
    private let threeFingerSwipeDistance: CGFloat = 60

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = MapStyle.background
        isOpaque = true
        contentMode = .redraw
        isMultipleTouchEnabled = true
        applyAccessibilityTraits()

        for direction in [UISwipeGestureRecognizer.Direction.right, .up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleThreeFingerSwipe(_:)))
            swipe.direction = direction
            swipe.numberOfTouchesRequired = 3
            addGestureRecognizer(swipe)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(voiceOverChanged),
                                               name: UIAccessibility.voiceOverStatusDidChangeNotification,
                                               object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // MARK: Layout and drawing

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let scene else { return }
        let padding = MapStyle.contentPadding
        let rect = bounds.inset(by: UIEdgeInsets(
            top: contentInsets.top + padding.top,
            left: contentInsets.left + padding.left,
            bottom: contentInsets.bottom + padding.bottom,
            right: contentInsets.right + padding.right))
        mapTransform = MapTransform(mapSize: scene.mapSize, centered: scene.isCentered, in: rect)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor((scene?.fillColor ?? MapStyle.background).cgColor)
        context.fill(bounds)
        // Roads run on past the map's edge; keep them out from under the top
        // bar and the home indicator.
        context.saveGState()
        context.clip(to: bounds.inset(by: contentInsets))
        scene?.draw(in: context, transform: mapTransform)
        context.restoreGState()
    }

    // MARK: Accessibility

    func configureAccessibility(label: String) {
        accessibilityLabel = label
        accessibilityHint = nil
        applyAccessibilityTraits()
    }

    private func applyAccessibilityTraits() {
        isAccessibilityElement = true
        accessibilityTraits = [.allowsDirectInteraction]
        // Pass touches straight to the map with no activation step and no
        // VoiceOver speech on touch; the map speaks for itself.
        accessibilityDirectTouchOptions = [.silentOnTouch]
    }

    @objc private func voiceOverChanged() {
        applyAccessibilityTraits()
        cancelPendingTap()
        if let touch = activeTouch {
            activeTouch = nil
            report(.cancelled, touch.location(in: self))
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        threeFingerAction(.finish, gesture: "VoiceOver escape")
        return true
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        switch direction {
        case .right:
            return threeFingerAction(.finish, gesture: "VoiceOver three-finger swipe right")
        case .up:
            return threeFingerAction(.next, gesture: "VoiceOver three-finger swipe up", voiceOverScroll: true)
        case .down:
            return threeFingerAction(.previous, gesture: "VoiceOver three-finger swipe down", voiceOverScroll: true)
        default:
            return false
        }
    }

    override func accessibilityPerformMagicTap() -> Bool {
        twoFingerDoubleTap(gesture: "VoiceOver magic tap")
        return true
    }

    @objc private func handleThreeFingerSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .recognized else { return }
        switch gesture.direction {
        case .up: threeFingerAction(.next, gesture: "Three-finger swipe up")
        case .down: threeFingerAction(.previous, gesture: "Three-finger swipe down")
        default: threeFingerAction(.finish, gesture: "Three-finger swipe right")
        }
    }

    private enum ThreeFingerAction { case finish, next, previous }

    /// Runs a three-finger gesture once. The swipe recogniser and the raw
    /// touch check can both see the same swipe; the second is ignored.
    @discardableResult
    private func threeFingerAction(_ action: ThreeFingerAction, gesture: String, voiceOverScroll: Bool = false) -> Bool {
        let now = CACurrentMediaTime()
        guard now - lastThreeFingerAction > 0.5 else { return true }
        lastThreeFingerAction = now
        switch action {
        case .finish:
            delegate?.canvasRequestsFinish(self, gesture: gesture)
            return true
        case .next:
            return delegate?.canvasRequestsItem(self, forward: true, gesture: gesture,
                                                voiceOverScroll: voiceOverScroll) ?? false
        case .previous:
            return delegate?.canvasRequestsItem(self, forward: false, gesture: gesture,
                                                voiceOverScroll: voiceOverScroll) ?? false
        }
    }

    /// The two-finger double tap, once, whether VoiceOver sends it as a
    /// magic tap or passes the touches through.
    private func twoFingerDoubleTap(gesture: String) {
        let now = CACurrentMediaTime()
        guard now - lastTwoFingerDoubleTap > 0.6 else { return }
        lastTwoFingerDoubleTap = now
        delegate?.canvasTwoFingerDoubleTap(self, gesture: gesture)
    }

    // MARK: Touches

    private func liveTouches(_ event: UIEvent?) -> Set<UITouch> {
        event?.allTouches?.filter { $0.phase != .ended && $0.phase != .cancelled } ?? []
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let live = liveTouches(event)
        let fingers = max(live.count, touches.count)
        if mostFingers == 0 {
            fingersStartTime = touches.first?.timestamp ?? CACurrentMediaTime()
            fingersMoved = 0
        }
        if fingers > mostFingers {
            mostFingers = fingers
            fingersStart = centroid(of: live.isEmpty ? touches : live)
            fingersMoved = 0
        }
        if fingers > 1 {
            // A multi-finger gesture: stop exploring so it does not buzz or speak.
            sequenceHadExtraFingers = true
            cancelPendingTap()
            if let touch = activeTouch {
                activeTouch = nil
                report(.cancelled, touch.location(in: self))
            }
            if fingers >= 3 {
                threeFingerStart = centroid(of: live)
            }
            return
        }
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        sequenceHadExtraFingers = false
        threeFingerStart = nil
        touchStart = touch.location(in: self)
        touchStartTime = touch.timestamp
        report(.began, touchStart)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        let live = liveTouches(event)
        if live.count >= 2, live.count == mostFingers {
            let now = centroid(of: live)
            fingersMoved = max(fingersMoved, hypot(now.x - fingersStart.x, now.y - fingersStart.y))
        }
        if let start = threeFingerStart, live.count >= 3 {
            let now = centroid(of: live)
            let dx = now.x - start.x
            let dy = now.y - start.y
            if dx > threeFingerSwipeDistance, abs(dy) < threeFingerSwipeDistance {
                threeFingerStart = nil
                threeFingerAction(.finish, gesture: "Three-finger swipe right")
            } else if -dy > threeFingerSwipeDistance, abs(dx) < threeFingerSwipeDistance {
                threeFingerStart = nil
                threeFingerAction(.next, gesture: "Three-finger swipe up")
            } else if dy > threeFingerSwipeDistance, abs(dx) < threeFingerSwipeDistance {
                threeFingerStart = nil
                threeFingerAction(.previous, gesture: "Three-finger swipe down")
            }
            return
        }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self)
        if hypot(point.x - touchStart.x, point.y - touchStart.y) > tapMaxDisplacement {
            cancelPendingTap()
        }
        report(.moved, point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if liveTouches(event).isEmpty {
            fingersLifted(at: touches.first?.timestamp ?? CACurrentMediaTime())
        }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        let point = touch.location(in: self)
        report(.ended, point)
        guard !sequenceHadExtraFingers else { return }

        let duration = touch.timestamp - touchStartTime
        let displacement = hypot(point.x - touchStart.x, point.y - touchStart.y)
        guard displacement < tapMaxDisplacement, duration < tapMaxDuration else { return }

        let now = CACurrentMediaTime()
        let isDouble = now - lastTapTime < doubleTapMaxInterval
            && hypot(point.x - lastTapPoint.x, point.y - lastTapPoint.y) < doubleTapMaxDistance
        if isDouble {
            cancelPendingTap()
            lastTapTime = 0
            delegate?.canvas(self, doubleTapAt: mapTransform.mm(point), screen: point)
        } else {
            lastTapTime = now
            lastTapPoint = point
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingSingleTap = nil
                self.lastTapTime = 0
                self.delegate?.canvas(self, singleTapAt: self.mapTransform.mm(point), screen: point)
            }
            pendingSingleTap = work
            DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapMaxInterval, execute: work)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if liveTouches(event).isEmpty {
            mostFingers = 0
            threeFingerStart = nil
        }
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        cancelPendingTap()
        report(.cancelled, touch.location(in: self))
    }

    /// The last finger is up: a quick, still touch of exactly two fingers is
    /// a two-finger tap, and two of them close together a double tap.
    private func fingersLifted(at time: TimeInterval) {
        defer {
            mostFingers = 0
            threeFingerStart = nil
        }
        guard mostFingers == 2, time - fingersStartTime < twoFingerTapMaxDuration,
              fingersMoved < tapMaxDisplacement else { return }
        let now = CACurrentMediaTime()
        if now - lastTwoFingerTap < twoFingerDoubleTapInterval {
            lastTwoFingerTap = 0
            twoFingerDoubleTap(gesture: "Two-finger double tap")
        } else {
            lastTwoFingerTap = now
        }
    }

    /// Stops any touch in progress, for example when the screen is leaving.
    func reset() {
        cancelPendingTap()
        lastTapTime = 0
        lastTwoFingerTap = 0
        mostFingers = 0
        threeFingerStart = nil
        if let touch = activeTouch {
            activeTouch = nil
            report(.cancelled, touch.location(in: self))
        }
    }

    private func report(_ phase: CanvasTouchPhase, _ point: CGPoint) {
        delegate?.canvas(self, touch: phase, mm: mapTransform.mm(point), screen: point)
    }

    private func cancelPendingTap() {
        pendingSingleTap?.cancel()
        pendingSingleTap = nil
    }

    private func centroid(of touches: Set<UITouch>) -> CGPoint {
        let points = touches.map { $0.location(in: self) }
        let x = points.reduce(0) { $0 + $1.x } / CGFloat(max(points.count, 1))
        let y = points.reduce(0) { $0 + $1.y } / CGFloat(max(points.count, 1))
        return CGPoint(x: x, y: y)
    }
}
