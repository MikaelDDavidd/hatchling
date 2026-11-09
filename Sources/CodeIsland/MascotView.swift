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

/// The mascot for a session: Hatch, with its eyes in the colour of the session's agent.
struct MascotView: View {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27

    var body: some View {
        HatchlingMascotView(source: source, status: status, size: size)
            .frame(width: size, height: size)
    }
}
