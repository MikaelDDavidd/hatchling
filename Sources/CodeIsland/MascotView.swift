import SwiftUI
import CodeIslandCore

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
