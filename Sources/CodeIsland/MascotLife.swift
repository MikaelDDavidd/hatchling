import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - Living mascot
//
// The mascots draw themselves on a 0.28s tick, which keeps the panel out of AppKit's
// continuous-layout mode (see `MascotTiming`). That is too coarse for the motion that
// makes a character feel alive — a breath, a bob, a hop — so that motion lives one level
// up, as Core Animation on the layer the mascot is hosted in. Core Animation runs in the
// window server and never wakes this process, so a breathing mascot costs what a still
// one does.

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

/// A `MascotView` that breathes while resting, bobs while working, fidgets when it needs
/// you, and hops once when a run finishes.
struct LivelyMascot: View {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27
    /// A soft halo in the mood's colour. Worth it on the cards, too busy in the notch strip.
    var glow: Bool = false

    @AppStorage(SettingsKey.mascotStyle) private var mascotStyle = SettingsDefaults.mascotStyle

    var body: some View {
        if mascotStyle == "hatchling" {
            // Already moves on its own, all of it in Core Animation; nothing to wrap.
            MascotView(source: source, status: status, size: size)
                .frame(width: size, height: size)
        } else {
            LivelyLayer(mood: MascotMood(status), glow: glow, content: AnyView(
                MascotView(source: source, status: status, size: size)
            ))
            .frame(width: size, height: size)
        }
    }
}

private struct LivelyLayer: NSViewRepresentable {
    let mood: MascotMood
    let glow: Bool
    let content: AnyView

    func makeNSView(context: Context) -> LivelyContainer {
        LivelyContainer(content: content)
    }

    func updateNSView(_ view: LivelyContainer, context: Context) {
        view.update(content: content, mood: mood, glow: glow)
    }
}

final class LivelyContainer: NSView {
    private let hosting: NSHostingView<AnyView>
    private var mood: MascotMood?
    private var glow = false
    private var animatedSize: CGSize = .zero

    private static let lifeKey = "hatchling.life"
    private static let glowKey = "hatchling.glow"
    private static let hopKey = "hatchling.hop"

    init(content: AnyView) {
        hosting = NSHostingView(rootView: content)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        hosting.wantsLayer = true
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        hosting.frame = bounds
        restartIfResized()
    }

    // SwiftUI sizes a representable by setting its frame, which doesn't always mark it for
    // layout, so the size change is caught here as well.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        hosting.frame = bounds
        restartIfResized()
    }

    // Animations added before the view is in a window are dropped when its layer is first
    // committed; start over once it has one.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let mood, bounds.width > 0 else { return }
        animatedSize = bounds.size
        startLife(for: mood)
    }

    private func restartIfResized() {
        guard bounds.width > 0, bounds.size != animatedSize, let mood else { return }
        animatedSize = bounds.size
        startLife(for: mood)
    }

    func update(content: AnyView, mood newMood: MascotMood, glow newGlow: Bool) {
        hosting.rootView = content
        let previous = mood
        guard previous != newMood || glow != newGlow else { return }
        mood = newMood
        glow = newGlow
        guard bounds.width > 0 else { return }
        animatedSize = bounds.size
        if previous == .working && newMood == .resting {
            hop()
        }
        startLife(for: newMood)
    }

    // MARK: Animation

    private var reduceMotion: Bool { Motion.isReduced }

    /// Scale about the centre of the layer, whatever AppKit chose as its anchor point.
    private func scaleAboutCentre(_ sx: CGFloat, _ sy: CGFloat, lift: CGFloat = 0) -> CATransform3D {
        guard let layer = layer else { return CATransform3DIdentity }
        let w = layer.bounds.width, h = layer.bounds.height
        let dx = (0.5 - layer.anchorPoint.x) * w
        let dy = (0.5 - layer.anchorPoint.y) * h
        var t = CATransform3DMakeTranslation(dx, dy + lift * upSign, 0)
        t = CATransform3DScale(t, sx, sy, 1)
        return CATransform3DTranslate(t, -dx, -dy, 0)
    }

    private var upSign: CGFloat { Self.visualUp(for: hosting.layer) }

    /// A positive y translation moves a layer up on screen unless an odd number of its
    /// ancestors flip their geometry, so count them instead of guessing per view.
    private static func visualUp(for layer: CALayer?) -> CGFloat {
        var flips = 0
        var ancestor = layer?.superlayer
        while let current = ancestor {
            if current.isGeometryFlipped { flips += 1 }
            ancestor = current.superlayer
        }
        return flips.isMultiple(of: 2) ? 1 : -1
    }

    private func startLife(for mood: MascotMood) {
        guard let layer = layer, let mascotLayer = hosting.layer else { return }
        layer.removeAnimation(forKey: Self.lifeKey)
        mascotLayer.removeAnimation(forKey: Self.glowKey)
        applyGlow(for: mood, on: mascotLayer)
        guard !reduceMotion else { return }

        // AppKit owns the geometry of every view's backing layer and quietly drops a transform
        // animated on it, but leaves `sublayerTransform` alone — so the motion goes there, on
        // the container, and moves the hosted mascot as a whole.
        let animation = CAKeyframeAnimation(keyPath: "sublayerTransform")
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.calculationMode = .cubic
        // Each copy of a mascot starts at its own phase, so a row of them doesn't move in lockstep.
        animation.beginTime = CACurrentMediaTime() - Double.random(in: 0...2)

        switch mood {
        case .resting:
            animation.duration = 3.2
            animation.values = [
                scaleAboutCentre(1.0, 1.0),
                scaleAboutCentre(1.025, 1.045, lift: 0.4),
                scaleAboutCentre(1.0, 1.0),
            ].map { NSValue(caTransform3D: $0) }
            animation.keyTimes = [0, 0.45, 1]
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
            ]
        case .working:
            animation.duration = 0.62
            animation.values = [
                scaleAboutCentre(1.0, 1.0),
                scaleAboutCentre(1.03, 0.96, lift: -0.4),
                scaleAboutCentre(0.99, 1.03, lift: 1.4),
                scaleAboutCentre(1.0, 1.0),
            ].map { NSValue(caTransform3D: $0) }
            animation.keyTimes = [0, 0.2, 0.55, 1]
            animation.calculationMode = .linear
            animation.timingFunctions = [
                CAMediaTimingFunction(name: .easeOut),
                CAMediaTimingFunction(name: .easeInEaseOut),
                CAMediaTimingFunction(name: .easeIn),
            ]
        case .needsYou:
            // A quick fidget, then stillness, on repeat: enough to catch the eye without
            // vibrating for minutes while you read something else.
            animation.duration = 2.4
            let tilt: (CGFloat) -> CATransform3D = { angle in
                CATransform3DRotate(self.scaleAboutCentre(1.04, 1.04), angle, 0, 0, 1)
            }
            animation.values = [
                scaleAboutCentre(1.0, 1.0),
                tilt(0.12), tilt(-0.12), tilt(0.09), tilt(-0.06),
                scaleAboutCentre(1.0, 1.0),
                scaleAboutCentre(1.0, 1.0),
            ].map { NSValue(caTransform3D: $0) }
            animation.keyTimes = [0, 0.06, 0.13, 0.2, 0.26, 0.32, 1]
            animation.calculationMode = .linear
        }
        layer.add(animation, forKey: Self.lifeKey)
    }

    private func applyGlow(for mood: MascotMood, on layer: CALayer) {
        guard glow, mood != .resting else {
            layer.shadowOpacity = 0
            return
        }
        layer.shadowColor = mood.glowColor.cgColor
        layer.shadowOffset = .zero
        layer.shadowRadius = 7
        layer.shadowOpacity = 0.35
        guard !reduceMotion else { return }
        let pulse = CABasicAnimation(keyPath: "shadowOpacity")
        pulse.fromValue = 0.15
        pulse.toValue = 0.6
        pulse.duration = mood == .needsYou ? 0.9 : 1.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        pulse.isRemovedOnCompletion = false
        layer.add(pulse, forKey: Self.glowKey)
    }

    /// The little jump when a run finishes. Additive, so it rides on top of the breath
    /// instead of replacing it.
    private func hop() {
        guard !reduceMotion, let layer = layer else { return }
        let up = upSign
        let hop = CAKeyframeAnimation(keyPath: "sublayerTransform.translation.y")
        hop.isAdditive = true
        hop.values = [0, 7 * up, 0, 2.5 * up, 0]
        hop.keyTimes = [0, 0.32, 0.62, 0.8, 1]
        hop.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
        ]
        hop.duration = 0.6
        layer.add(hop, forKey: Self.hopKey)
    }
}
