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

/// Things Hatch can be asked to do on top of its mood: a wave, a face, a gesture.
enum HatchReaction: String, CaseIterable {
    case wave, cheer, surprised, annoyed, wink, think, write, poke
    case clap, shrug, scratch, point
    /// Hands up to catch a file being dragged over the notch, until `catchEnd`.
    case catchStart, catchEnd

    func post() {
        NotificationCenter.default.post(name: .hatchReact, object: rawValue)
    }
}

/// A held position for the hands, for previewing them without animation.
enum HatchPose {
    case rest, wave, handsUp
    /// Already dozing, for previewing the sleep.
    case asleep
}

extension Notification.Name {
    /// Posted with a `HatchReaction` raw value; every global Hatch on screen acts it out.
    static let hatchReact = Notification.Name("HatchReact")
}

struct HatchlingMascotView: NSViewRepresentable {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27
    var global: Bool = false
    var celebrates: Bool = false
    /// Called with the number of recent clicks when someone clicks the global Hatch.
    var onPoke: ((Int) -> Void)? = nil
    /// Holds the hands in a pose (previews only).
    var pose: HatchPose? = nil

    func makeNSView(context: Context) -> HatchlingMascotLayerView {
        let view = HatchlingMascotLayerView()
        view.heldPose = pose
        view.reactsToEveryRun = global
        view.celebratesOnAppear = celebrates
        view.onPoke = onPoke
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
    /// Closed eyes for sleeping: two lids curving down, the opposite of the smile's arches.
    private let sleepEyes = CALayer()
    private let sleepLeft = CAShapeLayer()
    private let sleepRight = CAShapeLayer()
    /// Two small hands floating beside the block, never touching it. They hang off a rig
    /// that repeats every move of the body a beat late, so they trail it the way loose
    /// parts do (follow-through), and each also drifts on its own. Shown only where there
    /// is room for them, so not in the notch strip.
    private let handsRig = CALayer()
    private let leftHand = CAShapeLayer()
    private let rightHand = CAShapeLayer()
    private let leftShineHand = CAShapeLayer()
    private let rightShineHand = CAShapeLayer()
    /// How far behind the body the hands move.
    private static let handLag: CFTimeInterval = 0.11
    private let mouth = CAShapeLayer()
    private var lids: [CAShapeLayer] = [CAShapeLayer(), CAShapeLayer()]
    private var handRest: [CGPoint] = [.zero, .zero]
    private var catching = false
    private var pokes: [Date] = []
    var onPoke: ((Int) -> Void)?
    var heldPose: HatchPose?
    private var showsHands: Bool { builtSize.width >= 34 }

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
            NotificationCenter.default.removeObserver(self, name: .hatchReact, object: nil)
            guard reactsToEveryRun else { return }
            NotificationCenter.default.addObserver(self, selector: #selector(runFinished), name: .hatchCelebrate, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(reactionPosted(_:)), name: .hatchReact, object: nil)
        }
    }
    var celebratesOnAppear = false

    @objc private func runFinished() {
        celebrate()
        raiseHands(duration: 0.9)
    }

    @objc private func reactionPosted(_ note: Notification) {
        guard let raw = note.object as? String, let reaction = HatchReaction(rawValue: raw) else { return }
        perform(reaction)
    }
    /// How long at rest before it dozes off.
    private static let dozeAfter: TimeInterval = 60
    /// "z", "z", "Z" floating up out of the top corner while it sleeps.
    private let zzz: [CATextLayer] = ["z", "z", "Z"].map { letter in
        let layer = CATextLayer()
        layer.string = letter
        layer.alignmentMode = .center
        layer.opacity = 0
        return layer
    }

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
    override func mouseDown(with event: NSEvent) {
        guard reactsToEveryRun else { return super.mouseDown(with: event) }
        let now = Date()
        pokes = pokes.filter { now.timeIntervalSince($0) < 2.5 } + [now]
        perform(pokes.count >= 4 ? .annoyed : .poke)
        onPoke?(pokes.count)
    }

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
        [figure, body, bodyMask, rim, sheen, sheenMask, slot, dots, dot, sign, face, happy, happyLeft, happyRight,
         handsRig, leftHand, rightHand, leftShineHand, rightShineHand, mouth, sleepEyes, sleepLeft, sleepRight]
            + lids + zzz + eyes.flatMap(\.all)
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
        sleepEyes.addSublayer(sleepLeft)
        sleepEyes.addSublayer(sleepRight)
        sleepEyes.opacity = 0
        face.addSublayer(sleepEyes)
        for arc in [sleepLeft, sleepRight] {
            arc.fillColor = nil
            arc.lineCap = .round
        }
        for (eye, lid) in zip(eyes, lids) { eye.container.addSublayer(lid) }
        face.addSublayer(mouth)
        figure.addSublayer(face)
        // The rig sits behind the body, so a hand that swings close passes behind it.
        root.insertSublayer(handsRig, below: figure)
        for z in zzz {
            z.foregroundColor = NSColor(white: 0.85, alpha: 1).cgColor
            root.addSublayer(z)
        }
        handsRig.addSublayer(leftHand)
        handsRig.addSublayer(rightHand)
        leftHand.addSublayer(leftShineHand)
        rightHand.addSublayer(rightShineHand)
        for hand in [leftHand, rightHand] {
            // Same material as the block: its mid tone, its rim.
            hand.fillColor = NSColor(red: 0.12, green: 0.13, blue: 0.155, alpha: 1).cgColor
            hand.strokeColor = NSColor(red: 0.36, green: 0.38, blue: 0.43, alpha: 1).cgColor
            hand.opacity = 0
        }
        for shine in [leftShineHand, rightShineHand] {
            shine.fillColor = NSColor(white: 1, alpha: 0.10).cgColor
        }
        for lid in lids {
            lid.fillColor = NSColor(red: 0.15, green: 0.16, blue: 0.19, alpha: 1).cgColor
            lid.transform = CATransform3DMakeScale(1, 0, 1)
        }
        mouth.fillColor = nil
        mouth.lineCap = .round
        mouth.opacity = 0

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

        // Asleep: lids closed, curving down, a little below where the eyes sit.
        sleepEyes.frame = full
        for (arc, c) in zip([sleepLeft, sleepRight], centres) {
            arc.frame = full
            let p = CGMutablePath()
            p.move(to: CGPoint(x: c.x - 9, y: c.y + 1))
            p.addQuadCurve(to: CGPoint(x: c.x + 9, y: c.y + 1), control: CGPoint(x: c.x, y: c.y + 9))
            arc.path = p.copy(using: [scale])
            arc.lineWidth = max(1.2, 3.8 * s)
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

        // Lids: dark shutters that drop over the top of each eye for a frown.
        for (eye, lid) in zip(eyes, lids) {
            let box = eye.container.bounds
            lid.anchorPoint = CGPoint(x: 0.5, y: 0)
            lid.frame = CGRect(x: -box.width * 0.1, y: -box.height * 0.05, width: box.width * 1.2, height: box.height * 0.62)
            lid.path = CGPath(rect: lid.bounds, transform: nil)
        }
        mouth.frame = full
        mouth.lineWidth = max(1.2, 3.2 * s)

        // The rig pivots like the body, so a tilt or a squash carries the hands along.
        handsRig.anchorPoint = figure.anchorPoint
        handsRig.bounds = figure.bounds
        handsRig.position = figure.position
        // Low at the sides, with a clear gap to the block: the hands never touch it.
        // A mitten: a round palm with a small thumb on the side facing the body, which is
        // what makes it read as a hand and not a stray bubble.
        let handW: CGFloat = 19 * s, handH: CGFloat = 17 * s
        handRest = [CGPoint(x: -10 * s, y: 70 * s), CGPoint(x: 110 * s, y: 70 * s)]
        for (i, (hand, rest)) in zip([leftHand, rightHand], handRest).enumerated() {
            hand.bounds = CGRect(x: 0, y: 0, width: handW, height: handH)
            hand.position = rest
            let palm = CGPath(ellipseIn: CGRect(x: handW * 0.08, y: handH * 0.12, width: handW * 0.84, height: handH * 0.82), transform: nil)
            let thumbX = i == 0 ? handW * 0.66 : handW * 0.0
            let thumb = CGPath(ellipseIn: CGRect(x: thumbX, y: handH * 0.0, width: handW * 0.34, height: handH * 0.4), transform: nil)
            hand.path = palm.union(thumb)
            hand.lineWidth = max(1, 2.2 * s)
            hand.opacity = showsHands ? 1 : 0
            // Tipped slightly outward, like loosely held mittens.
            hand.transform = CATransform3DMakeRotation(i == 0 ? 0.22 : -0.22, 0, 0, 1)
            let shine = i == 0 ? leftShineHand : rightShineHand
            shine.frame = CGRect(x: handW * 0.2, y: handH * 0.14, width: handW * 0.42, height: handH * 0.3)
            shine.path = CGPath(ellipseIn: shine.bounds, transform: nil)
        }
        if let heldPose { hold(heldPose, s: s) }

        for (i, z) in zzz.enumerated() {
            let size = (14 + CGFloat(i) * 3) * s
            z.bounds = CGRect(x: 0, y: 0, width: size, height: size * 1.25)
            z.fontSize = size
            z.font = NSFont.systemFont(ofSize: size, weight: .heavy)
            z.position = CGPoint(x: 86 * s, y: 18 * s)
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
        mouth.strokeColor = eyeColor.cgColor
        let sleepy = (eyeColor.blended(withFraction: 0.35, of: .black) ?? eyeColor).cgColor
        sleepLeft.strokeColor = sleepy
        sleepRight.strokeColor = sleepy
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
        handsRig.removeAllAnimations()
        for z in zzz {
            z.removeAllAnimations()
            z.opacity = 0
        }
        sleepEyes.opacity = 0
        for eye in eyes { eye.container.opacity = 1 }
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
            sign.opacity = 0
        }
        figure.shadowOpacity = 0
        // A faint, steady light on the eyes, as on the icon. No pulsing glow.
        face.shadowOpacity = 0.25

        guard !Motion.isReduced else { return }
        let s = builtSize.width / 100
        let phase = CACurrentMediaTime() - Double.random(in: 0...3)
        driftHands()

        switch mood {
        case .resting where sleepy:
            // Dozing: eyes half shut, slow deep breaths, "Zzz" floating up out of the corner.
            addBodyMotion(breathe(phase: phase, duration: 5.2, depth: 1.07), forKey: Key.figure)
            for eye in eyes { eye.container.opacity = 0 }
            sleepEyes.opacity = 1
            face.shadowOpacity = 0.15
            floatZzz(s: s)
        case .resting:
            addBodyMotion(breathe(phase: phase), forKey: Key.figure)
            blink(every: 5.2, phase: phase)
            for eye in eyes { eye.pupilGroup.add(lookAround(s: s, phase: phase), forKey: Key.look) }
        case .working where status == .processing:
            // Thinking: eyes up and to the side, a slow sway, the dots in no hurry.
            addBodyMotion(sway(s: s), forKey: Key.figure)
            blink(every: 4.0, phase: phase)
            for eye in eyes { eye.pupilGroup.add(ponder(s: s, phase: phase), forKey: Key.look) }
        case .working:
            addBodyMotion(bob(s: s), forKey: Key.figure)
            blink(every: 3.1, phase: phase)
            // Eyes on the work: down and to the side, where the terminal would be.
            for eye in eyes { eye.pupilGroup.transform = CATransform3DMakeTranslation(1.8 * s, 2.4 * s, 0) }
            let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
            hop.values = [0, -2.4 * s, 0, 0]
            hop.keyTimes = [0, 0.2, 0.42, 1]
            hop.duration = 0.9
            dot.add(repeating(hop), forKey: Key.dots)
        case .needsYou:
            addBodyMotion(fidget(), forKey: Key.figure)
            for eye in eyes { eye.container.transform = CATransform3DMakeScale(1.14, 1.14, 1) }
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
        if showsHands, Int.random(in: 0..<3) == 0 {
            perform([.wave, .think, .scratch, .shrug, .clap, .point, .wink].randomElement()!)
            return
        }
        switch Int.random(in: 0..<5) {
        case 0: // a stretch: tall and thin, then back with a little wobble
            let a = CAKeyframeAnimation(keyPath: "sublayerTransform")
            a.values = [
                CATransform3DIdentity, CATransform3DMakeScale(0.94, 1.12, 1), CATransform3DMakeScale(1.05, 0.95, 1),
                CATransform3DMakeScale(0.99, 1.01, 1), CATransform3DIdentity,
            ].map { NSValue(caTransform3D: $0) }
            a.keyTimes = [0, 0.35, 0.6, 0.8, 1]
            a.duration = 1.1
            addBodyMotion(a, forKey: Key.idle)
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
            addBodyMotion(a, forKey: Key.idle)
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
        dragHands(height: 7 * s, duration: 0.55)
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

    /// Three letters rising one after another from the top corner, growing and fading, on a
    /// loop: the plainest way to say "asleep" that reads at any size.
    private func floatZzz(s: CGFloat) {
        let start = CGPoint(x: 86 * s, y: 18 * s)
        for (i, z) in zzz.enumerated() {
            let rise = CAKeyframeAnimation(keyPath: "position")
            rise.values = [start, CGPoint(x: start.x + 10 * s, y: start.y - 14 * s), CGPoint(x: start.x + 16 * s, y: start.y - 30 * s)]
                .map { NSValue(point: $0) }
            rise.calculationMode = .cubic
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.2, 0.7, 1]
            let grow = CAKeyframeAnimation(keyPath: "transform.scale")
            grow.values = [0.5, 1, 1.2]
            let group = CAAnimationGroup()
            group.animations = [rise, fade, grow]
            group.duration = 2.7
            group.repeatCount = .infinity
            group.isRemovedOnCompletion = false
            group.beginTime = CACurrentMediaTime() + Double(i) * 0.9
            group.fillMode = .backwards
            z.add(group, forKey: "hatch.zzz")
        }
    }

    // MARK: Hands and reactions

    /// Plays a body animation and the same one on the hand rig, a beat later.
    private func addBodyMotion(_ animation: CAAnimation, forKey key: String) {
        figure.add(animation, forKey: key)
        guard showsHands, let trailing = animation.copy() as? CAAnimation else { return }
        let start = animation.beginTime > 0 ? animation.beginTime : CACurrentMediaTime()
        trailing.beginTime = start + Self.handLag
        handsRig.add(trailing, forKey: key)
    }

    /// Each hand drifts a little on its own, out of step with the other.
    private func driftHands() {
        guard showsHands, !Motion.isReduced else { return }
        let s = builtSize.width / 100
        for (i, hand) in [leftHand, rightHand].enumerated() {
            let bob = CABasicAnimation(keyPath: "transform.translation.y")
            bob.fromValue = -1.4 * s
            bob.toValue = 1.4 * s
            bob.duration = i == 0 ? 1.9 : 2.3
            bob.autoreverses = true
            bob.isAdditive = true
            bob.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            hand.add(repeating(bob, phase: CACurrentMediaTime() - Double(i) * 0.7), forKey: "hatch.drift")
            let tilt = CABasicAnimation(keyPath: "transform.rotation.z")
            tilt.fromValue = -0.08
            tilt.toValue = 0.08
            tilt.duration = i == 0 ? 2.6 : 2.2
            tilt.autoreverses = true
            tilt.isAdditive = true
            tilt.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            hand.add(repeating(tilt, phase: CACurrentMediaTime() - Double(i) * 1.1), forKey: "hatch.tilt")
        }
    }

    /// Hands trailing a hop: they lag on the way up, overshoot on the way down, settle.
    private func dragHands(height: CGFloat, duration: CFTimeInterval) {
        guard showsHands else { return }
        let drag = CAKeyframeAnimation(keyPath: "transform.translation.y")
        drag.values = [0, height * 0.45, -height * 0.25, height * 0.1, 0]
        drag.keyTimes = [0, 0.3, 0.62, 0.82, 1]
        drag.duration = duration
        drag.isAdditive = true
        handsRig.add(drag, forKey: "hatch.drag")
    }

    /// Where each hand sits for a held pose.
    private func hold(_ pose: HatchPose, s: CGFloat) {
        switch pose {
        case .rest:
            break
        case .asleep:
            sleepy = true
        case .wave:
            rightHand.position = CGPoint(x: 112 * s, y: 34 * s)
            rightHand.transform = CATransform3DMakeRotation(-0.6, 0, 0, 1)
        case .handsUp:
            leftHand.position = CGPoint(x: -12 * s, y: 28 * s)
            rightHand.position = CGPoint(x: 112 * s, y: 28 * s)
            leftHand.transform = CATransform3DMakeRotation(0.5, 0, 0, 1)
            rightHand.transform = CATransform3DMakeRotation(-0.5, 0, 0, 1)
        }
    }

    func perform(_ reaction: HatchReaction) {
        guard builtSize != .zero, !Motion.isReduced else { return }
        switch reaction {
        case .wave: wave()
        case .cheer: celebrate(); raiseHands(duration: 1.0)
        case .surprised: surprised()
        case .annoyed: annoyed()
        case .wink: wink()
        case .think: think()
        case .write: write()
        case .poke: poke()
        case .clap: clap()
        case .shrug: shrug()
        case .scratch: scratchHead()
        case .point: point()
        case .catchStart: setCatching(true)
        case .catchEnd: setCatching(false)
        }
    }

    // MARK: Faces

    private enum MouthShape { case smile, open, flat }

    /// Shows a mouth for a moment. Hatch has none at rest, like the icon; it only appears
    /// when a face needs one.
    private func showMouth(_ shape: MouthShape, for duration: CFTimeInterval) {
        let s = builtSize.width / 100
        let path = CGMutablePath()
        switch shape {
        case .smile:
            path.move(to: CGPoint(x: 43 * s, y: 77 * s))
            path.addQuadCurve(to: CGPoint(x: 57 * s, y: 77 * s), control: CGPoint(x: 50 * s, y: 84 * s))
            mouth.fillColor = nil
        case .open:
            path.addEllipse(in: CGRect(x: 46.5 * s, y: 74 * s, width: 7 * s, height: 8 * s))
            mouth.fillColor = NSColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1).cgColor
        case .flat:
            path.move(to: CGPoint(x: 45 * s, y: 79 * s))
            path.addLine(to: CGPoint(x: 55 * s, y: 79 * s))
            mouth.fillColor = nil
        }
        mouth.path = path
        let show = CAKeyframeAnimation(keyPath: "opacity")
        show.values = [0, 1, 1, 0]
        show.keyTimes = [0, 0.1, 0.85, 1]
        show.duration = duration
        mouth.add(show, forKey: "hatch.mouth")
    }

    /// Eyes go wide, pupils shrink, mouth drops open, hands jump.
    private func surprised() {
        let wide = CAKeyframeAnimation(keyPath: "transform.scale")
        wide.values = [1, 1.24, 1.2, 1]
        wide.keyTimes = [0, 0.12, 0.8, 1]
        wide.duration = 1.3
        let small = CAKeyframeAnimation(keyPath: "transform.scale")
        small.values = [1, 0.7, 0.72, 1]
        small.keyTimes = [0, 0.12, 0.8, 1]
        small.duration = 1.3
        for eye in eyes {
            eye.container.add(wide, forKey: "hatch.face")
            eye.pupilGroup.add(small, forKey: "hatch.face")
        }
        showMouth(.open, for: 1.3)
        nudgeHands(dy: -9, duration: 0.6)
    }

    /// A frown: lids drop and slant inward, flat mouth, a short huff, hands on its sides.
    private func annoyed() {
        for (i, lid) in lids.enumerated() {
            let angle: CGFloat = i == 0 ? 0.32 : -0.32
            let drop = CAKeyframeAnimation(keyPath: "transform")
            let down = CATransform3DRotate(CATransform3DMakeScale(1, 0.55, 1), angle, 0, 0, 1)
            drop.values = [CATransform3DMakeScale(1, 0, 1), down, down, CATransform3DMakeScale(1, 0, 1)]
                .map { NSValue(caTransform3D: $0) }
            drop.keyTimes = [0, 0.12, 0.85, 1]
            drop.duration = 1.8
            lid.add(drop, forKey: "hatch.face")
        }
        showMouth(.flat, for: 1.8)
        let huff = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        huff.values = [0, 0.07, -0.07, 0.04, 0]
        huff.duration = 0.45
        huff.isAdditive = true
        addBodyMotion(huff, forKey: "hatch.huff")
        let s = builtSize.width / 100
        moveHands(to: [CGPoint(x: -4 * s, y: 80 * s), CGPoint(x: 104 * s, y: 80 * s)], hold: 1.2, duration: 1.8)
    }

    private func wink() {
        let close = CAKeyframeAnimation(keyPath: "opacity")
        close.values = [1, 0, 0, 1]
        close.keyTimes = [0, 0.1, 0.8, 1]
        close.duration = 0.9
        eyes[1].container.add(close, forKey: "hatch.wink")
        let arc = CAKeyframeAnimation(keyPath: "opacity")
        arc.values = [0, 1, 1, 0]
        arc.keyTimes = [0, 0.1, 0.8, 1]
        arc.duration = 0.9
        // Only the right arch of the smile shows.
        happyRight.add(arc, forKey: "hatch.wink")
        happy.add(arc, forKey: "hatch.wink")
        happyLeft.opacity = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in self?.happyLeft.opacity = 1 }
        showMouth(.smile, for: 0.9)
    }

    /// Hand to the chin, eyes up and to the side.
    private func think() {
        let s = builtSize.width / 100
        moveHands(to: [handRest[0], CGPoint(x: 70 * s, y: 100 * s)], hold: 1.4, duration: 2.0)
        let up = CAKeyframeAnimation(keyPath: "transform.translation")
        let gaze = NSValue(size: NSSize(width: -3.4 * s, height: -3.2 * s))
        up.values = [NSValue(size: .zero), gaze, gaze, NSValue(size: .zero)]
        up.keyTimes = [0, 0.15, 0.85, 1]
        up.duration = 2.0
        up.isAdditive = true
        for eye in eyes { eye.pupilGroup.add(up, forKey: "hatch.think") }
    }

    /// Scribbles under itself, eyes down on the paper.
    private func write() {
        guard showsHands else { return }
        let s = builtSize.width / 100
        let base = CGPoint(x: 62 * s, y: 100 * s)
        var points = [handRest[1], base]
        for i in 0..<6 { points.append(CGPoint(x: base.x + CGFloat(i.isMultiple(of: 2) ? -5 : 4) * s, y: base.y + CGFloat(i % 3) * s)) }
        points += [base, handRest[1]]
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = points.map { NSValue(point: $0) }
        move.calculationMode = .cubic
        move.duration = 1.6
        rightHand.add(move, forKey: "hatch.write")
        let down = CAKeyframeAnimation(keyPath: "transform.translation")
        let gaze = NSValue(size: NSSize(width: 1.5 * s, height: 3.2 * s))
        down.values = [NSValue(size: .zero), gaze, gaze, NSValue(size: .zero)]
        down.keyTimes = [0, 0.15, 0.85, 1]
        down.duration = 1.6
        down.isAdditive = true
        for eye in eyes { eye.pupilGroup.add(down, forKey: "hatch.write") }
    }

    /// A click: it squashes, then answers with a face.
    private func poke() {
        let squash = CAKeyframeAnimation(keyPath: "transform.scale.y")
        squash.values = [0, -0.14, 0.07, -0.02, 0]
        squash.duration = 0.4
        squash.isAdditive = true
        addBodyMotion(squash, forKey: "hatch.poke")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            [self?.wink, self?.surprised, self?.wave].randomElement()??()
        }
    }

    // MARK: More gestures

    /// Claps above its head, three times.
    private func clap() {
        guard showsHands else { return }
        let s = builtSize.width / 100
        for (i, hand) in [leftHand, rightHand].enumerated() {
            let side: CGFloat = i == 0 ? -1 : 1
            let apart = CGPoint(x: 50 * s + side * 14 * s, y: 4 * s)
            let together = CGPoint(x: 50 * s + side * 6.5 * s, y: 4 * s)
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [handRest[i], apart, together, apart, together, apart, together, apart, handRest[i]]
                .map { NSValue(point: $0) }
            move.calculationMode = .cubic
            move.duration = 1.7
            hand.add(move, forKey: "hatch.clap")
        }
        flashHappyEyes(duration: 1.5)
    }

    /// Hands out and up, palms open, a little tilt: "who knows".
    private func shrug() {
        let s = builtSize.width / 100
        moveHands(to: [CGPoint(x: -16 * s, y: 54 * s), CGPoint(x: 116 * s, y: 54 * s)], hold: 0.8, duration: 1.4)
        let tilt = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        tilt.values = [0, 0.1, 0.1, 0]
        tilt.keyTimes = [0, 0.2, 0.8, 1]
        tilt.duration = 1.4
        tilt.isAdditive = true
        addBodyMotion(tilt, forKey: "hatch.shrug")
        showMouth(.flat, for: 1.4)
    }

    /// Scratches the top of its head, puzzled.
    private func scratchHead() {
        guard showsHands else { return }
        let s = builtSize.width / 100
        let spot = CGPoint(x: 88 * s, y: 12 * s)
        var points = [handRest[1], spot]
        for i in 0..<5 { points.append(CGPoint(x: spot.x + CGFloat(i.isMultiple(of: 2) ? 3 : -2) * s, y: spot.y + CGFloat(i.isMultiple(of: 2) ? -1.5 : 1.5) * s)) }
        points += [spot, handRest[1]]
        let move = CAKeyframeAnimation(keyPath: "position")
        move.values = points.map { NSValue(point: $0) }
        move.calculationMode = .cubic
        move.duration = 1.6
        rightHand.add(move, forKey: "hatch.scratch")
        let look = CAKeyframeAnimation(keyPath: "transform.translation")
        let gaze = NSValue(size: NSSize(width: 3 * s, height: -2.6 * s))
        look.values = [NSValue(size: .zero), gaze, gaze, NSValue(size: .zero)]
        look.keyTimes = [0, 0.15, 0.85, 1]
        look.duration = 1.6
        look.isAdditive = true
        for eye in eyes { eye.pupilGroup.add(look, forKey: "hatch.scratch") }
    }

    /// Points down and to the right, where the session cards are.
    private func point() {
        let s = builtSize.width / 100
        moveHands(to: [handRest[0], CGPoint(x: 120 * s, y: 86 * s)], hold: 1.0, duration: 1.5)
        let look = CAKeyframeAnimation(keyPath: "transform.translation")
        let gaze = NSValue(size: NSSize(width: 3.6 * s, height: 2.4 * s))
        look.values = [NSValue(size: .zero), gaze, gaze, NSValue(size: .zero)]
        look.keyTimes = [0, 0.15, 0.85, 1]
        look.duration = 1.5
        look.isAdditive = true
        for eye in eyes { eye.pupilGroup.add(look, forKey: "hatch.point") }
    }

    /// Hands up and open while a file is dragged over the notch, as if to catch it.
    private func setCatching(_ on: Bool) {
        guard on != catching else { return }
        catching = on
        let s = builtSize.width / 100
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.3)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        let targets = on ? [CGPoint(x: -12 * s, y: 30 * s), CGPoint(x: 112 * s, y: 30 * s)] : handRest
        for (hand, target) in zip([leftHand, rightHand], targets) {
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = NSValue(point: hand.presentation()?.position ?? hand.position)
            move.toValue = NSValue(point: target)
            move.duration = 0.3
            hand.position = target
            hand.add(move, forKey: "hatch.catch")
        }
        for eye in eyes {
            eye.container.transform = on ? CATransform3DMakeScale(1.18, 1.18, 1) : CATransform3DIdentity
        }
        mouth.opacity = on ? 1 : 0
        CATransaction.commit()
        if on {
            showMouthHeld(.open)
        } else {
            mouth.opacity = 0
            flashHappyEyes(duration: 1.0)
        }
    }

    private func showMouthHeld(_ shape: MouthShape) {
        showMouth(shape, for: 0.01)
        mouth.removeAnimation(forKey: "hatch.mouth")
        mouth.opacity = 1
    }

    /// Moves both hands to `targets`, holds, and brings them back, each on a gentle arc.
    private func moveHands(to targets: [CGPoint], hold: CFTimeInterval, duration: CFTimeInterval) {
        guard showsHands else { return }
        let rise = (duration - hold) / 2 / duration
        for (i, hand) in [leftHand, rightHand].enumerated() where targets[i] != handRest[i] {
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [handRest[i], targets[i], targets[i], handRest[i]].map { NSValue(point: $0) }
            move.keyTimes = [0, NSNumber(value: rise), NSNumber(value: 1 - rise), 1]
            move.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]
            move.duration = duration
            hand.add(move, forKey: "hatch.move")
        }
    }

    /// Both hands hop by `dy` (in grid units) and settle.
    private func nudgeHands(dy: CGFloat, duration: CFTimeInterval) {
        guard showsHands else { return }
        let s = builtSize.width / 100
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, dy * s, dy * 0.3 * s, 0]
        hop.duration = duration
        hop.isAdditive = true
        for hand in [leftHand, rightHand] { hand.add(hop, forKey: "hatch.nudge") }
    }

    /// The right hand rises along an arc to beside the head, waves on a small arc while
    /// tipping back and forth, and drops back the way it came. The left one sways along.
    private func wave() {
        guard showsHands else { return }
        let s = builtSize.width / 100
        let rest = handRest[1]
        let up = CGPoint(x: 112 * s, y: 34 * s)
        let rise = CGMutablePath()
        rise.move(to: rest)
        rise.addQuadCurve(to: up, control: CGPoint(x: 122 * s, y: 62 * s))
        // Rise, five small strokes, fall.
        let move = CAKeyframeAnimation(keyPath: "position")
        var points: [CGPoint] = [rest]
        for t in stride(from: 0.2, through: 1.0, by: 0.2) {
            // Points along the rising arc.
            let x = (1 - t) * (1 - t) * rest.x + 2 * (1 - t) * t * 122 * s + t * t * up.x
            let y = (1 - t) * (1 - t) * rest.y + 2 * (1 - t) * t * 62 * s + t * t * up.y
            points.append(CGPoint(x: x, y: y))
        }
        for i in 0..<5 { points.append(CGPoint(x: up.x + (i.isMultiple(of: 2) ? 3.5 : -1.5) * s, y: up.y + (i.isMultiple(of: 2) ? 1 : -1) * s)) }
        points.append(up)
        points += points.prefix(6).reversed()
        move.values = points.map { NSValue(point: $0) }
        move.calculationMode = .cubic
        move.duration = 1.9
        rightHand.add(move, forKey: "hatch.wave")

        let turn = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        turn.values = [-0.22, -0.6, -0.15, -0.75, -0.15, -0.75, -0.3, -0.6, -0.22]
        turn.keyTimes = [0, 0.25, 0.35, 0.45, 0.55, 0.65, 0.72, 0.8, 1]
        turn.duration = 1.9
        rightHand.add(turn, forKey: "hatch.waveTurn")

        let sway = CAKeyframeAnimation(keyPath: "transform.translation.y")
        sway.values = [0, -2 * s, 0, -1.5 * s, 0]
        sway.duration = 1.9
        sway.isAdditive = true
        leftHand.add(sway, forKey: "hatch.waveSway")
        flashHappyEyes(duration: 1.6)
    }

    /// Both hands up along arcs, a little shake at the top, and back with an overshoot.
    private func raiseHands(duration: CFTimeInterval) {
        guard showsHands, !Motion.isReduced else { return }
        let s = builtSize.width / 100
        for (i, hand) in [leftHand, rightHand].enumerated() {
            let rest = handRest[i]
            let side: CGFloat = i == 0 ? -1 : 1
            let top = CGPoint(x: rest.x + side * 4 * s, y: 28 * s)
            let move = CAKeyframeAnimation(keyPath: "position")
            move.values = [
                rest, CGPoint(x: rest.x + side * 9 * s, y: 52 * s), top,
                CGPoint(x: top.x, y: top.y - 2 * s), top, CGPoint(x: rest.x, y: rest.y + 2.5 * s), rest,
            ].map { NSValue(point: $0) }
            move.keyTimes = [0, 0.14, 0.3, 0.45, 0.6, 0.86, 1]
            move.calculationMode = .cubic
            // The second hand follows the first by a hair.
            move.beginTime = CACurrentMediaTime() + (i == 0 ? 0 : 0.05)
            move.duration = duration
            hand.add(move, forKey: "hatch.raise")
        }
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
        dragHands(height: 14 * s, duration: 0.75)
        flashHappyEyes(duration: 1.8)
    }
}
