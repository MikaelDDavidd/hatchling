import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Hatch, the app's own mascot
//
// The app icon come to life: a dark rounded block with the notch cut into its top and two
// big glowing eyes. The notch is its speech bubble — three dots while it works, a "!" when
// it needs you, a "?" when it has a question.
//
// Every part is a vector layer and every movement is a Core Animation animation, so the
// character never asks SwiftUI to redraw: the window server plays the breath, the blinks
// and the glances on its own, and the app stays asleep while it does. The old per-agent mascots
// redrew through a `TimelineView`, which kept the panel's CPU above zero.
//
// The eyes glow in the colour of the agent the session runs on, so a row of them still
// tells Claude from Codex at a glance.

enum MascotMood: Equatable {
    case resting
    case working
    case needsYou

    init(_ status: AgentStatus) {
        switch status {
        case .idle:                               self = .resting
        case .processing, .running:               self = .working
        case .waitingApproval, .waitingQuestion:  self = .needsYou
        }
    }

    var glowColor: NSColor {
        switch self {
        case .resting:  return NSColor(white: 1, alpha: 1)
        case .working:  return NSColor(red: 0.36, green: 0.85, blue: 0.50, alpha: 1)
        case .needsYou: return NSColor(red: 1.0, green: 0.65, blue: 0.25, alpha: 1)
        }
    }
}

struct HatchlingMascotView: NSViewRepresentable {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27
    var global: Bool = false
    var celebrates: Bool = false

    func makeNSView(context: Context) -> HatchlingMascotLayerView {
        let view = HatchlingMascotLayerView()
        view.reactsToEveryRun = global
        view.celebratesOnAppear = celebrates
        return view
    }

    func updateNSView(_ view: HatchlingMascotLayerView, context: Context) {
        view.configure(eyes: Self.eyeColor(for: source), status: status)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HatchlingMascotLayerView, context: Context) -> CGSize? {
        CGSize(width: size, height: size)
    }

    static func eyeColor(for source: String) -> NSColor {
        switch source {
        case "claude":                         return NSColor(red: 1.0, green: 0.56, blue: 0.36, alpha: 1)
        case "codex":                          return NSColor(red: 0.42, green: 0.66, blue: 1.0, alpha: 1)
        case "gemini":                         return NSColor(red: 0.55, green: 0.55, blue: 1.0, alpha: 1)
        case "cursor", "trae", "traecn":       return NSColor(red: 1.0, green: 0.48, blue: 0.24, alpha: 1)
        case "copilot":                        return NSColor(red: 0.40, green: 0.84, blue: 1.0, alpha: 1)
        case "qwen", "codebuddy", "codybuddycn", "stepfun", "antigravity", "workbuddy", "hermes":
                                               return NSColor(red: 0.70, green: 0.52, blue: 1.0, alpha: 1)
        default:                               return NSColor(red: 0.30, green: 0.92, blue: 0.45, alpha: 1)
        }
    }
}

final class HatchlingMascotLayerView: NSView {
    private let figure = CALayer()
    private let body = CAGradientLayer()
    private let bodyMask = CAShapeLayer()
    private let rim = CAShapeLayer()
    private let sheen = CAGradientLayer()
    private let sheenMask = CAShapeLayer()
    private let slot = CALayer()
    private let dots = CAReplicatorLayer()
    private let dot = CAShapeLayer()
    private let sign = CATextLayer()
    private let face = CALayer()
    private var eyes: [Eye] = [Eye(), Eye()]
    private let happy = CALayer()
    private let happyLeft = CAShapeLayer()
    private let happyRight = CAShapeLayer()

    /// One eye: a glowing iris with a dark pupil that moves inside it to look around.
    private final class Eye {
        let container = CALayer()
        let iris = CAGradientLayer()
        let irisMask = CAShapeLayer()
        let pupilGroup = CALayer()
        let pupil = CAGradientLayer()
        let pupilMask = CAShapeLayer()
        let shine = CAShapeLayer()
        var all: [CALayer] { [container, iris, irisMask, pupilGroup, pupil, pupilMask, shine] }
    }

    private var status: AgentStatus?
    private var eyeColor: NSColor = .clear
    private var builtSize: CGSize = .zero
    /// When the mascot last had something to do. Long enough at rest and it dozes off.
    private var restingSince = Date()
    private var sleepy = false
    /// Drives the little things a resting mascot does on its own. Fires every few seconds,
    /// starts one Core Animation and goes back to sleep, so it costs a wake-up, not a redraw.
    private var idleTimer: Timer?
    private var hasAppeared = false
    var reactsToEveryRun = false {
        didSet {
            NotificationCenter.default.removeObserver(self, name: .hatchCelebrate, object: nil)
            guard reactsToEveryRun else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(runFinished), name: .hatchCelebrate, object: nil)
        }
    }
    var celebratesOnAppear = false

    @objc private func runFinished() {
        celebrate()
    }
    private static let dozeAfter: TimeInterval = 180

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        assemble()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }

    private var mood: MascotMood? { status.map(MascotMood.init) }

    func configure(eyes color: NSColor, status newStatus: AgentStatus) {
        let previousMood = mood
        if color != eyeColor {
            eyeColor = color
            paintEyes()
        }
        let changed = status != newStatus
        status = newStatus
        guard changed else { return }
        restingSince = Date()
        sleepy = false
        animate()
        // After `animate`, which clears the eyes' animations and would cut the smile short.
        if previousMood == .working && mood == .resting { celebrate() }
    }

    override func layout() {
        super.layout()
        rebuildIfResized()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rebuildIfResized()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else {
            idleTimer?.invalidate()
            idleTimer = nil
            return
        }
        if let scale = window?.backingScaleFactor {
            for sub in allLayers { sub.contentsScale = scale }
        }
        animate()
        if !hasAppeared {
            hasAppeared = true
            if celebratesOnAppear { celebrate() } else { popIn() }
        }
        scheduleIdleBehaviour()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// Notices the cursor: a quick widening of the eyes and a little jump. Wakes it if it dozed.
    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        if sleepy {
            sleepy = false
            restingSince = Date()
            animate()
        }
        notice()
    }

    // MARK: Build

    private var allLayers: [CALayer] {
        [figure, body, bodyMask, rim, sheen, sheenMask, slot, dots, dot, sign, face, happy, happyLeft, happyRight]
            + eyes.flatMap(\.all)
    }

    private static let noActions: [String: CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "path": NSNull(),
        "fillColor": NSNull(), "strokeColor": NSNull(), "transform": NSNull(), "opacity": NSNull(),
        "contents": NSNull(), "colors": NSNull(), "anchorPoint": NSNull(), "string": NSNull(),
        "instanceTransform": NSNull(), "shadowColor": NSNull(), "shadowOpacity": NSNull(),
    ]

    private func assemble() {
        guard let root = layer else { return }
        root.addSublayer(figure)
        body.mask = bodyMask
        figure.addSublayer(body)
        sheen.mask = sheenMask
        figure.addSublayer(sheen)
        figure.addSublayer(rim)
        slot.addSublayer(dots)
        dots.addSublayer(dot)
        slot.addSublayer(sign)
        figure.addSublayer(slot)
        for eye in eyes {
            eye.iris.mask = eye.irisMask
            eye.container.addSublayer(eye.iris)
            eye.pupil.mask = eye.pupilMask
            eye.pupilGroup.addSublayer(eye.pupil)
            eye.pupilGroup.addSublayer(eye.shine)
            eye.container.addSublayer(eye.pupilGroup)
            face.addSublayer(eye.container)
        }
        happy.addSublayer(happyLeft)
        happy.addSublayer(happyRight)
        face.addSublayer(happy)
        figure.addSublayer(face)

        body.colors = [
            NSColor(red: 0.16, green: 0.17, blue: 0.20, alpha: 1).cgColor,
            NSColor(red: 0.06, green: 0.065, blue: 0.08, alpha: 1).cgColor,
        ]
        sheen.colors = [NSColor(white: 1, alpha: 0.10).cgColor, NSColor(white: 1, alpha: 0).cgColor]
        rim.fillColor = nil
        rim.strokeColor = NSColor(red: 0.36, green: 0.38, blue: 0.43, alpha: 1).cgColor
        sign.alignmentMode = .center
        sign.opacity = 0
        dots.opacity = 0
        happy.opacity = 0
        for arc in [happyLeft, happyRight] {
            arc.fillColor = nil
            arc.lineCap = .round
            arc.lineJoin = .round
        }
        for eye in eyes {
            eye.pupil.colors = [
                NSColor(red: 0.10, green: 0.16, blue: 0.22, alpha: 1).cgColor,
                NSColor(red: 0.01, green: 0.02, blue: 0.03, alpha: 1).cgColor,
            ]
            eye.pupil.type = .radial
            eye.pupil.startPoint = CGPoint(x: 0.4, y: 0.3)
            eye.pupil.endPoint = CGPoint(x: 1.1, y: 1.1)
            eye.shine.fillColor = NSColor.white.withAlphaComponent(0.92).cgColor
        }
        face.shadowOffset = .zero
        figure.shadowOffset = .zero
        figure.shadowOpacity = 0
        for sub in allLayers { sub.actions = Self.noActions }
    }

    private func rebuildIfResized() {
        guard bounds.width > 0, bounds.size != builtSize else { return }
        builtSize = bounds.size
        build(size: min(bounds.width, bounds.height))
        animate()
    }

    /// Lays every part out on a 100×100 grid, scaled to the view.
    private func build(size: CGFloat) {
        let s = size / 100
        let scale = CGAffineTransform(scaleX: s, y: s)
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: x * s, y: y * s, width: w * s, height: h * s)
        }
        let full = CGRect(x: 0, y: 0, width: size, height: size)

        // The figure pivots at its base, so breathing grows it upward and a squash flattens it.
        figure.anchorPoint = CGPoint(x: 0.5, y: 0.9)
        figure.bounds = full
        figure.position = CGPoint(x: size / 2, y: size * 0.9)

        // The block: a rounded rectangle with the notch cut into the middle of its top edge.
        let block = CGMutablePath()
        let (l, t, r, b, cr) = (CGFloat(5), CGFloat(20), CGFloat(95), CGFloat(88), CGFloat(20))
        let (nl, nr, nd) = (CGFloat(35), CGFloat(65), CGFloat(8))
        block.move(to: CGPoint(x: l + cr, y: t))
        block.addLine(to: CGPoint(x: nl - 3, y: t))
        block.addCurve(to: CGPoint(x: nl + 4, y: t + nd), control1: CGPoint(x: nl + 1.5, y: t), control2: CGPoint(x: nl + 1, y: t + nd))
        block.addLine(to: CGPoint(x: nr - 4, y: t + nd))
        block.addCurve(to: CGPoint(x: nr + 3, y: t), control1: CGPoint(x: nr - 1, y: t + nd), control2: CGPoint(x: nr - 1.5, y: t))
        block.addLine(to: CGPoint(x: r - cr, y: t))
        block.addCurve(to: CGPoint(x: r, y: t + cr), control1: CGPoint(x: r - cr * 0.38, y: t), control2: CGPoint(x: r, y: t + cr * 0.38))
        block.addLine(to: CGPoint(x: r, y: b - cr))
        block.addCurve(to: CGPoint(x: r - cr, y: b), control1: CGPoint(x: r, y: b - cr * 0.38), control2: CGPoint(x: r - cr * 0.38, y: b))
        block.addLine(to: CGPoint(x: l + cr, y: b))
        block.addCurve(to: CGPoint(x: l, y: b - cr), control1: CGPoint(x: l + cr * 0.38, y: b), control2: CGPoint(x: l, y: b - cr * 0.38))
        block.addLine(to: CGPoint(x: l, y: t + cr))
        block.addCurve(to: CGPoint(x: l + cr, y: t), control1: CGPoint(x: l, y: t + cr * 0.38), control2: CGPoint(x: l + cr * 0.38, y: t))
        block.closeSubpath()
        let blockPath = block.copy(using: [scale])

        body.frame = full
        bodyMask.frame = full
        bodyMask.path = blockPath
        sheen.frame = full
        sheenMask.frame = full
        sheenMask.path = blockPath
        sheen.startPoint = CGPoint(x: 0.5, y: 0.15)
        sheen.endPoint = CGPoint(x: 0.5, y: 0.55)
        rim.frame = full
        rim.path = blockPath
        rim.lineWidth = max(1, 2.4 * s)

        // The notch doubles as the speech bubble.
        slot.frame = rect(nl + 4, t, nr - nl - 8, nd)
        let dotRadius = 1.9 * s
        dot.frame = CGRect(x: 0, y: 0, width: dotRadius * 2, height: dotRadius * 2)
        dot.path = CGPath(ellipseIn: dot.bounds, transform: nil)
        let gap = 6 * s
        dots.instanceCount = 3
        dots.instanceTransform = CATransform3DMakeTranslation(gap, 0, 0)
        dots.instanceDelay = 0.13
        dots.frame = CGRect(x: slot.bounds.midX - gap - dotRadius, y: slot.bounds.midY - dotRadius,
                            width: gap * 2 + dotRadius * 2, height: dotRadius * 2)
        // The sign is taller than the notch is deep, so it pokes out above the head like a
        // little flag — readable even at the size of the notch strip.
        sign.frame = CGRect(x: 0, y: -12 * s, width: slot.bounds.width, height: 22 * s)
        sign.fontSize = 17 * s
        sign.font = NSFont.systemFont(ofSize: 17, weight: .heavy)

        // The eyes.
        face.frame = full
        let centres = [CGPoint(x: 33, y: 55), CGPoint(x: 67, y: 55)]
        let irisRadius: CGFloat = 14.5
        for (eye, c) in zip(eyes, centres) {
            eye.container.frame = rect(c.x - irisRadius, c.y - irisRadius, irisRadius * 2, irisRadius * 2)
            let box = eye.container.bounds
            eye.iris.frame = box
            eye.irisMask.frame = box
            eye.irisMask.path = CGPath(ellipseIn: box, transform: nil)
            eye.iris.type = .radial
            eye.iris.startPoint = CGPoint(x: 0.3, y: 0.75)
            eye.iris.endPoint = CGPoint(x: 1.2, y: 1.2)
            // The pupil sits up and to the right, leaving a lit crescent below, as on the icon.
            let pr = 11.2 * s
            eye.pupilGroup.frame = box
            eye.pupil.frame = CGRect(x: box.midX - pr + 2.2 * s, y: box.midY - pr - 2.4 * s, width: pr * 2, height: pr * 2)
            eye.pupilMask.frame = eye.pupil.bounds
            eye.pupilMask.path = CGPath(ellipseIn: eye.pupil.bounds, transform: nil)
            let shine = CGRect(x: eye.pupil.frame.minX + pr * 0.95, y: eye.pupil.frame.minY + pr * 0.35,
                               width: pr * 0.62, height: pr * 0.44)
            eye.shine.frame = shine
            eye.shine.path = CGPath(ellipseIn: CGRect(origin: .zero, size: shine.size), transform: nil)
        }

        // Closed, smiling eyes for the moment a run finishes: two little arches.
        happy.frame = full
        for (arc, c) in zip([happyLeft, happyRight], centres) {
            arc.frame = full
            let p = CGMutablePath()
            p.move(to: CGPoint(x: c.x - 9, y: c.y + 4))
            p.addQuadCurve(to: CGPoint(x: c.x + 9, y: c.y + 4), control: CGPoint(x: c.x, y: c.y - 9))
            arc.path = p.copy(using: [scale])
            arc.lineWidth = max(1.2, 4.2 * s)
        }

        face.shadowRadius = 5 * s
        figure.shadowRadius = 9 * s
        paintEyes()
    }

    private func paintEyes() {
        let light = eyeColor.blended(withFraction: 0.45, of: .white) ?? eyeColor
        for eye in eyes {
            eye.iris.colors = [light.cgColor, eyeColor.cgColor]
        }
        happyLeft.strokeColor = eyeColor.cgColor
        happyRight.strokeColor = eyeColor.cgColor
        dot.fillColor = eyeColor.cgColor
        face.shadowColor = eyeColor.cgColor
        face.shadowOpacity = 0.55
    }

    // MARK: Motion

    private enum Key {
        static let figure = "hatch.figure"
        static let blink = "hatch.blink"
        static let look = "hatch.look"
        static let glow = "hatch.glow"
        static let dots = "hatch.dots"
        static let sign = "hatch.sign"
        static let hop = "hatch.hop"
        static let happy = "hatch.happy"
        static let idle = "hatch.idle"
        static let notice = "hatch.notice"
        static let pop = "hatch.pop"
    }

    private func animate() {
        guard let status, let mood, builtSize != .zero else { return }
        figure.removeAllAnimations()
        face.removeAnimation(forKey: Key.glow)
        dot.removeAllAnimations()
        sign.removeAllAnimations()
        for eye in eyes {
            eye.container.removeAllAnimations()
            eye.pupilGroup.removeAllAnimations()
            eye.container.transform = CATransform3DIdentity
            eye.pupilGroup.transform = CATransform3DIdentity
        }

        // What the notch says.
        dots.opacity = mood == .working ? 1 : 0
        let amber = NSColor(red: 1.0, green: 0.72, blue: 0.30, alpha: 1)
        switch status {
        case .waitingApproval: showSign("!", color: amber)
        case .waitingQuestion: showSign("?", color: amber)
        default:
            if sleepy { showSign("z", color: NSColor(white: 0.75, alpha: 1)) } else { sign.opacity = 0 }
        }
        figure.shadowOpacity = 0
        face.shadowOpacity = mood == .resting ? 0.35 : 0.6

        guard !Motion.isReduced else { return }
        let s = builtSize.width / 100
        let phase = CACurrentMediaTime() - Double.random(in: 0...3)

        switch mood {
        case .resting where sleepy:
            // Dozing: eyes half shut, slow deep breaths, a "z" drifting out of the notch.
            figure.add(breathe(phase: phase, duration: 5.2, depth: 1.07), forKey: Key.figure)
            for eye in eyes { eye.container.transform = CATransform3DMakeScale(1, 0.28, 1) }
            face.shadowOpacity = 0.15
            let drift = CAKeyframeAnimation(keyPath: "transform")
            drift.values = [
                CATransform3DMakeTranslation(0, 2 * s, 0), CATransform3DMakeTranslation(2 * s, -4 * s, 0),
                CATransform3DMakeTranslation(4 * s, -9 * s, 0),
            ].map { NSValue(caTransform3D: $0) }
            drift.duration = 2.6
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0]
            fade.keyTimes = [0, 0.3, 1]
            fade.duration = 2.6
            let float = CAAnimationGroup()
            float.animations = [drift, fade]
            float.duration = 2.6
            sign.add(repeating(float), forKey: Key.sign)
        case .resting:
            figure.add(breathe(phase: phase), forKey: Key.figure)
            blink(every: 5.2, phase: phase)
            for eye in eyes { eye.pupilGroup.add(lookAround(s: s, phase: phase), forKey: Key.look) }
        case .working where status == .processing:
            // Thinking: eyes up and to the side, a slow sway, the dots in no hurry.
            figure.add(sway(s: s), forKey: Key.figure)
            blink(every: 4.0, phase: phase)
            for eye in eyes { eye.pupilGroup.add(ponder(s: s, phase: phase), forKey: Key.look) }
            face.add(pulse(from: 0.3, to: 0.7, duration: 2.0), forKey: Key.glow)
        case .working:
            figure.add(bob(s: s), forKey: Key.figure)
            blink(every: 3.1, phase: phase)
            // Eyes on the work: down and to the side, where the terminal would be.
            for eye in eyes { eye.pupilGroup.transform = CATransform3DMakeTranslation(1.8 * s, 2.4 * s, 0) }
            face.add(pulse(from: 0.35, to: 0.85, duration: 1.4), forKey: Key.glow)
            let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
            hop.values = [0, -2.4 * s, 0, 0]
            hop.keyTimes = [0, 0.2, 0.42, 1]
            hop.duration = 0.9
            dot.add(repeating(hop), forKey: Key.dots)
        case .needsYou:
            figure.add(fidget(), forKey: Key.figure)
            for eye in eyes { eye.container.transform = CATransform3DMakeScale(1.14, 1.14, 1) }
            face.add(pulse(from: 0.4, to: 1.0, duration: 0.8), forKey: Key.glow)
            let flash = CABasicAnimation(keyPath: "opacity")
            flash.fromValue = 1
            flash.toValue = 0.35
            flash.duration = 0.55
            flash.autoreverses = true
            sign.add(repeating(flash), forKey: Key.sign)
        }
    }

    private func showSign(_ text: String, color: NSColor) {
        sign.string = text
        sign.foregroundColor = color.cgColor
        sign.opacity = 1
    }

    private func repeating(_ animation: CAAnimation, phase: CFTimeInterval? = nil) -> CAAnimation {
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        if let phase { animation.beginTime = phase }
        return animation
    }

    private func breathe(phase: CFTimeInterval, duration: CFTimeInterval = 3.4, depth: CGFloat = 1.045) -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [
            CATransform3DIdentity,
            CATransform3DMakeScale(1 + (depth - 1) * 0.45, depth, 1),
            CATransform3DIdentity,
        ].map { NSValue(caTransform3D: $0) }
        a.keyTimes = [0, 0.45, 1]
        a.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        a.duration = duration
        return repeating(a, phase: phase)
    }

    private func sway(s: CGFloat) -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        a.values = [0, 0.06, 0, -0.06, 0]
        a.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        a.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 4)
        a.duration = 3.0
        return repeating(a)
    }

    private func ponder(s: CGFloat, phase: CFTimeInterval) -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "transform.translation")
        let points: [CGSize] = [
            CGSize(width: -3.2, height: -3.0), CGSize(width: -3.2, height: -3.0),
            CGSize(width: 2.6, height: -3.4), CGSize(width: 2.6, height: -3.4), CGSize(width: -3.2, height: -3.0),
        ]
        a.values = points.map { NSValue(size: NSSize(width: $0.width * s, height: $0.height * s)) }
        a.keyTimes = [0, 0.4, 0.5, 0.9, 1]
        a.duration = 5.0
        a.calculationMode = .cubic
        return repeating(a, phase: phase)
    }

    private func bob(s: CGFloat) -> CAAnimation {
        let squash = CATransform3DMakeScale(1.05, 0.94, 1)
        var up = CATransform3DMakeTranslation(0, -4 * s, 0)
        up = CATransform3DScale(up, 0.98, 1.04, 1)
        let a = CAKeyframeAnimation(keyPath: "transform")
        a.values = [CATransform3DIdentity, squash, up, CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
        a.keyTimes = [0, 0.18, 0.55, 1]
        a.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
        ]
        a.duration = 0.6
        return repeating(a)
    }

    /// A quick shiver, then stillness: catches the eye without vibrating for minutes.
    private func fidget() -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        a.values = [0, 0.13, -0.13, 0.09, -0.05, 0, 0]
        a.keyTimes = [0, 0.05, 0.11, 0.17, 0.23, 0.29, 1]
        a.duration = 2.2
        return repeating(a)
    }

    private func pulse(from: Float, to: Float, duration: CFTimeInterval) -> CAAnimation {
        let a = CABasicAnimation(keyPath: "shadowOpacity")
        a.fromValue = from
        a.toValue = to
        a.duration = duration
        a.autoreverses = true
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return repeating(a)
    }

    private func blink(every period: CFTimeInterval, phase: CFTimeInterval) {
        // A single blink, and now and then a double one, at fixed points inside the period.
        let a = CAKeyframeAnimation(keyPath: "transform.scale.y")
        a.values = [1, 1, 0.08, 1, 1, 0.08, 1, 0.08, 1]
        let length = 0.13 / (period * 2)
        a.keyTimes = [0, 0.42, NSNumber(value: 0.42 + length / 2), NSNumber(value: 0.42 + length),
                      0.86, NSNumber(value: 0.86 + length / 2), NSNumber(value: 0.86 + length),
                      NSNumber(value: 0.86 + length * 1.6), NSNumber(value: min(0.86 + length * 2.2, 1))]
        a.duration = period * 2
        for eye in eyes { eye.container.add(repeating(a, phase: phase), forKey: Key.blink) }
    }

    private func lookAround(s: CGFloat, phase: CFTimeInterval) -> CAAnimation {
        let a = CAKeyframeAnimation(keyPath: "transform.translation")
        let points: [CGSize] = [
            .zero, .zero, CGSize(width: -4.2, height: 0.8), CGSize(width: -4.2, height: 0.8),
            .zero, .zero, CGSize(width: 3.6, height: -1.6), CGSize(width: 3.6, height: -1.6), .zero, .zero,
        ]
        a.values = points.map { NSValue(size: NSSize(width: $0.width * s, height: $0.height * s)) }
        a.keyTimes = [0, 0.12, 0.17, 0.33, 0.38, 0.55, 0.6, 0.74, 0.79, 1]
        a.duration = 9.5
        a.calculationMode = .cubic
        return repeating(a, phase: phase)
    }

    // MARK: Things it does on its own

    private func scheduleIdleBehaviour() {
        idleTimer?.invalidate()
        guard window != nil, !Motion.isReduced else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: .random(in: 6...13), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.idleBehaviour()
                self.scheduleIdleBehaviour()
            }
        }
        idleTimer?.tolerance = 2
    }

    private func idleBehaviour() {
        guard mood == .resting, builtSize != .zero else { return }
        if !sleepy, Date().timeIntervalSince(restingSince) > Self.dozeAfter {
            sleepy = true
            animate()
            return
        }
        guard !sleepy else { return }
        let s = builtSize.width / 100
        switch Int.random(in: 0..<5) {
        case 0: // a stretch: tall and thin, then back with a little wobble
            let a = CAKeyframeAnimation(keyPath: "sublayerTransform")
            a.values = [
                CATransform3DIdentity, CATransform3DMakeScale(0.94, 1.12, 1), CATransform3DMakeScale(1.05, 0.95, 1),
                CATransform3DMakeScale(0.99, 1.01, 1), CATransform3DIdentity,
            ].map { NSValue(caTransform3D: $0) }
            a.keyTimes = [0, 0.35, 0.6, 0.8, 1]
            a.duration = 1.1
            figure.add(a, forKey: Key.idle)
        case 1: // a happy squint
            flashHappyEyes(duration: 1.2)
        case 2: // a double take to the side
            let a = CAKeyframeAnimation(keyPath: "transform.translation.x")
            a.values = [0, 4.5 * s, 4.5 * s, 0, 4.5 * s, 0]
            a.keyTimes = [0, 0.12, 0.4, 0.5, 0.62, 1]
            a.duration = 1.6
            a.isAdditive = true
            for eye in eyes { eye.pupilGroup.add(a, forKey: Key.idle) }
        case 3: // a wiggle
            let a = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            a.values = [0, 0.1, -0.08, 0.05, 0]
            a.duration = 0.7
            a.isAdditive = true
            figure.add(a, forKey: Key.idle)
        default: // a little hop for no reason
            notice()
        }
    }

    private func notice() {
        guard !Motion.isReduced, builtSize != .zero, let root = layer else { return }
        let s = builtSize.width / 100
        let hop = CAKeyframeAnimation(keyPath: "sublayerTransform.translation.y")
        hop.values = [0, -7 * s, 0, -2 * s, 0]
        hop.keyTimes = [0, 0.3, 0.6, 0.8, 1]
        hop.duration = 0.45
        root.add(hop, forKey: Key.notice)
        let widen = CAKeyframeAnimation(keyPath: "transform.scale")
        widen.values = [1, 1.22, 1]
        widen.duration = 0.4
        widen.isAdditive = false
        for eye in eyes { eye.pupilGroup.add(widen, forKey: Key.notice) }
    }

    /// Pops out of nowhere the first time it is shown, like it just hatched.
    private func popIn() {
        guard !Motion.isReduced, let root = layer else { return }
        let pop = CAKeyframeAnimation(keyPath: "sublayerTransform.scale")
        pop.values = [0.3, 1.12, 0.94, 1]
        pop.keyTimes = [0, 0.45, 0.75, 1]
        pop.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeOut),
        ]
        pop.duration = 0.5
        root.add(pop, forKey: Key.pop)
    }

    private func flashHappyEyes(duration: CFTimeInterval) {
        let smile = CAKeyframeAnimation(keyPath: "opacity")
        smile.values = [0, 1, 1, 0]
        smile.keyTimes = [0, 0.1, 0.85, 1]
        smile.duration = duration
        happy.add(smile, forKey: Key.happy)
        let open = CAKeyframeAnimation(keyPath: "opacity")
        open.values = [1, 0, 0, 1]
        open.keyTimes = [0, 0.1, 0.85, 1]
        open.duration = duration
        for eye in eyes { eye.container.add(open, forKey: Key.happy) }
    }

    /// A run just finished: a hop, and the eyes close into a smile for a moment.
    private func celebrate() {
        guard !Motion.isReduced, builtSize != .zero, let root = layer else { return }
        let s = builtSize.width / 100
        let hop = CAKeyframeAnimation(keyPath: "sublayerTransform.translation.y")
        hop.values = [0, -14 * s, 0, -4 * s, 0]
        hop.keyTimes = [0, 0.32, 0.62, 0.8, 1]
        hop.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeIn),
        ]
        hop.duration = 0.62
        root.add(hop, forKey: Key.hop)
        flashHappyEyes(duration: 1.8)
    }
}
