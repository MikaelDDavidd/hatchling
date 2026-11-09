import SwiftUI
import CodeIslandCore

// MARK: - Animation Cadence

/// How often anything still drawn through a `TimelineView` ticks.
///
/// AppKit keeps a window in continuous-layout mode — a full layout and
/// constraint pass on every display refresh, 120×/s on ProMotion — for as long
/// as something asks it to redraw faster than every 250ms. The threshold is a
/// cliff, not a slope: measured on this machine, a 0.25s cadence costs 126
/// layout passes/s and 4.3% CPU while 0.26s costs 4 passes/s and 0.4%.
/// The mascot itself no longer redraws at all; it moves in Core Animation.
enum MascotTiming {
    static let tick: Double = 0.28
}

/// Hatch, with its eyes in the colour of the agent it is showing.
struct MascotView: View {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27
    /// The one Hatch that stands for every session: it also hops whenever any run ends.
    var global: Bool = false
    /// Opens with the finishing hop and smile instead of the plain pop.
    var celebrates: Bool = false
    /// Called with the number of recent clicks when the global Hatch is clicked.
    var onPoke: ((Int) -> Void)? = nil
    /// The files-tray Hatch, whose notch opens into a pocket for files.
    var pocket: Bool = false

    var body: some View {
        HatchlingMascotView(source: source, status: status, size: size, global: global, celebrates: celebrates,
                            onPoke: onPoke, pocket: pocket)
            .frame(width: size, height: size)
    }
}

/// What the single, global Hatch should look like given every session at once: the most
/// urgent mood wins, and its eyes take the colour of the session that set it.
struct GlobalMood {
    let source: String
    let status: AgentStatus

    init(sessions: [SessionSnapshot], fallbackSource: String = "claude") {
        func rank(_ s: SessionSnapshot) -> Int {
            switch s.status {
            case .waitingApproval, .waitingQuestion: return 0
            case .running: return 1
            case .processing: return 2
            case .idle: return 3
            }
        }
        let lead = sessions.min { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.lastActivity > b.lastActivity
        }
        source = lead?.source ?? fallbackSource
        status = lead?.status ?? .idle
    }
}

/// The agent's colour as a small dot, where a card or a chat used to carry its own mascot.
struct AgentDot: View {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 8

    var body: some View {
        let color = Color(nsColor: HatchlingMascotView.eyeColor(for: source))
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .opacity(status == .idle ? 0.45 : 1)
    }
}

extension Notification.Name {
    /// Posted with a session id when a run finishes.
    static let hatchCelebrate = Notification.Name("HatchCelebrate")
}
