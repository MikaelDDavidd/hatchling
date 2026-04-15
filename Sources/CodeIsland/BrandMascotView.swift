import SwiftUI
import AppKit
import CodeIslandCore

/// Brand mascot — renderiza o ícone oficial do CLI (claude.png, gemini.png, codex.png, ...)
/// com animações por estado (idle/working/alert), preservando contrato visual com pixel mascots.
struct BrandMascotView: View {
    let source: String
    let status: AgentStatus
    var size: CGFloat = 27

    @Environment(\.mascotSpeed) private var speed
    @State private var alive = false

    private static let alertC = Color(red: 1.0, green: 0.24, blue: 0.0)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !alive)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate * max(speed, 0.01)
            BrandIconImage(source: source)
                .frame(width: size, height: size)
                .modifier(BrandStateModifier(source: source, status: status, t: t))
        }
        .frame(width: size, height: size)
        .clipped()
        .onAppear { alive = true }
        .onChange(of: status) {
            alive = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { alive = true }
        }
    }
}

// MARK: - Image loader (cached via NotchPanelView's cliIcon helper)

private struct BrandIconImage: View {
    let source: String

    var body: some View {
        Group {
            if let nsImage = loadImage() {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                // Fallback shape: monospace glyph in a rounded rect (raro, só se PNG sumir)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Text(String(source.prefix(1)).uppercased())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                    )
            }
        }
    }

    private func loadImage() -> NSImage? {
        let filename = brandIconFilename(for: source)
        guard let url = Bundle.appModule.url(
            forResource: filename,
            withExtension: "png",
            subdirectory: "Resources/cli-icons"
        ) else { return nil }
        return NSImage(contentsOf: url)
    }
}

/// Map source → ícone oficial. Todos os files já existem em Resources/cli-icons/.
private func brandIconFilename(for source: String) -> String {
    switch source {
    case "codex":                     return "codex"
    case "gemini":                    return "gemini"
    case "cursor":                    return "cursor"
    case "trae", "traecn":            return "trae"
    case "copilot":                   return "copilot"
    case "qoder":                     return "qoder"
    case "droid":                     return "factory"
    case "codebuddy", "codybuddycn":  return "codebuddy"
    case "stepfun":                   return "stepfun"
    case "opencode":                  return "opencode"
    case "qwen":                      return "qwen"
    case "antigravity":               return "antigravity"
    case "workbuddy":                 return "workbuddy"
    case "hermes":                    return "hermes"
    default:                          return "claude"
    }
}

// MARK: - State-driven animation modifier

private struct BrandStateModifier: ViewModifier {
    let source: String
    let status: AgentStatus
    let t: TimeInterval

    func body(content: Content) -> some View {
        switch status {
        case .idle:
            content
                .opacity(idleBreath)
        case .processing, .running:
            applyWorking(content)
        case .waitingApproval, .waitingQuestion:
            content
                .colorMultiply(BrandMascotView_alertTint)
                .offset(x: alertShake, y: 0)
                .scaleEffect(1.0 + 0.04 * sin(t * 14))
        }
    }

    // ── Idle: respiração suave 0.65 → 1.0 em ~2.4s ──
    private var idleBreath: Double {
        let phase = (sin(t * 2.6) + 1) / 2  // 0..1
        return 0.65 + phase * 0.35
    }

    // ── Working: animação por brand ──
    @ViewBuilder
    private func applyWorking(_ content: Content) -> some View {
        switch source {
        case "gemini":
            // twinkle: scale-pulse + leve rotação alternada (estrela 4-pontas brilhando)
            content
                .scaleEffect(1.0 + 0.12 * sin(t * 5))
                .rotationEffect(.degrees(8 * sin(t * 3)))
                .shadow(color: .blue.opacity(0.55), radius: 2 + 2 * (sin(t * 5) + 1) / 2)

        case "codex":
            // cloud flutuando + leve "respiração"
            content
                .offset(y: -1.5 * sin(t * 3))
                .scaleEffect(1.0 + 0.05 * sin(t * 6))

        default:
            // Claude (sparkle) e fallback: rotação contínua suave + glow pulsante
            content
                .rotationEffect(.degrees((t * 60).truncatingRemainder(dividingBy: 360)))
                .shadow(color: .orange.opacity(0.55), radius: 2 + 2 * (sin(t * 5) + 1) / 2)
        }
    }

    // ── Alert: shake horizontal ──
    private var alertShake: Double {
        sin(t * 22) * 1.6
    }
}

// Cor de alerta exposta a nível de arquivo (struct privada não pode ser acessada de modifier separado)
private let BrandMascotView_alertTint = Color(red: 1.0, green: 0.55, blue: 0.4)
