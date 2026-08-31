import SwiftUI
import CodeIslandCore

// MARK: - Mascot Animation Cadence

/// How often every mascot's `TimelineView` ticks.
///
/// AppKit keeps a window in continuous-layout mode — a full layout and
/// constraint pass on every display refresh, 120×/s on ProMotion — for as long
/// as something asks it to redraw faster than every 250ms. The threshold is a
/// cliff, not a slope: measured on this machine, a 0.25s cadence costs 126
/// layout passes/s and 4.3% CPU while 0.26s costs 4 passes/s and 0.4%, and
/// anything below 0.25s costs the same whether it ticks 4×/s or 33×/s.
///
/// So the mascots tick just past the cliff. The animation is coarser, which
/// suits pixel art, and the app stops burning a core corner doing nothing.
/// Frame-perfect motion needs Core Animation driving the layer directly, which
/// runs in the window server and never wakes this process at all.
enum MascotTiming {
    static let tick: Double = 0.28
}

// MARK: - Mascot Animation Speed Environment

private struct MascotSpeedKey: EnvironmentKey {
    static let defaultValue: Double = 1.0
}

extension EnvironmentValues {
    var mascotSpeed: Double {
        get { self[MascotSpeedKey.self] }
        set { self[MascotSpeedKey.self] = newValue }
    }
}

/// Routes a CLI source identifier to the correct mascot view.
/// Honors `mascotStyle` setting: "pixel" → pixel-art mascots, "brand" → official brand icon animated.
struct MascotView: View {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27
    @AppStorage(SettingsKey.mascotSpeed) private var speedPct = SettingsDefaults.mascotSpeed
    @AppStorage(SettingsKey.mascotStyle) private var mascotStyle = SettingsDefaults.mascotStyle

    var body: some View {
        Group {
            if mascotStyle == "brand" {
                BrandMascotView(source: source, status: status, size: size)
            } else {
                pixelMascot
            }
        }
        .environment(\.mascotSpeed, Double(speedPct) / 100.0)
    }

    @ViewBuilder
    private var pixelMascot: some View {
        Group {
            switch source {
            case "codex":
                DexView(status: status, size: size)
            case "gemini":
                GeminiView(status: status, size: size)
            case "cursor":
                CursorView(status: status, size: size)
            case "trae", "traecn":
                TraeView(status: status, size: size)
            case "copilot":
                CopilotView(status: status, size: size)
            case "qoder":
                QoderView(status: status, size: size)
            case "droid":
                DroidView(status: status, size: size)
            case "codebuddy":
                BuddyView(status: status, size: size)
            case "codybuddycn":
                BuddyView(status: status, size: size)
            case "stepfun":
                StepFunView(status: status, size: size)
            case "opencode":
                OpenCodeView(status: status, size: size)
            case "qwen":
                QwenView(status: status, size: size)
            case "antigravity":
                AntiGravityView(status: status, size: size)
            case "workbuddy":
                WorkBuddyView(status: status, size: size)
            case "hermes":
                HermesView(status: status, size: size)
            default:
                ClawdView(status: status, size: size)
            }
        }
    }
}
