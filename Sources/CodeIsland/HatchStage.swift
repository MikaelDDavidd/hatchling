import SwiftUI
import AppKit
import CodeIslandCore

// MARK: - What Hatch says
//
// Hatch keeps up a running commentary on every session while the agents list is open:
// who needs you, who just finished, what each one is doing, whose context is filling up.
// It "thinks" for a beat before each new line. Events — a click, a file dragged in, a new
// note, the app starting — interrupt the rotation with a line of their own.
//
// Everything here is built from what the hooks already report; nothing leaves the Mac.

@MainActor
final class HatchDirector: ObservableObject {
    static let shared = HatchDirector()

    @Published private(set) var line = ""
    @Published private(set) var thinking = false

    private weak var appState: AppState?
    private var rotation: Timer?
    private var stagesOnScreen = 0
    private var turn = 0
    private var holdUntil = Date.distantPast

    private static let rotateEvery: TimeInterval = 7

    func attach(_ appState: AppState) { self.appState = appState }

    private var pt: Bool { L10n.shared.effectiveLanguage == "pt" }

    // MARK: Lifetime: only talk while someone can see it

    func stageAppeared() {
        stagesOnScreen += 1
        guard stagesOnScreen == 1 else { return }
        if Date() > holdUntil { line = compose() }
        rotation?.invalidate()
        rotation = Timer.scheduledTimer(withTimeInterval: Self.rotateEvery, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        rotation?.tolerance = 1
    }

    func stageDisappeared() {
        stagesOnScreen = max(0, stagesOnScreen - 1)
        guard stagesOnScreen == 0 else { return }
        rotation?.invalidate()
        rotation = nil
    }

    // MARK: Events

    /// Says something now and keeps it up a little longer than a rotating line.
    func say(_ text: String, reaction: HatchReaction? = nil, hold: TimeInterval = 5) {
        thinking = false
        line = text
        holdUntil = Date().addingTimeInterval(hold)
        reaction?.post()
    }

    func poked(count: Int) {
        let lines: [String]
        switch count {
        case ...1: lines = pt ? ["Oi!", "Tô aqui.", "Precisa de algo?", "Hm?"] : ["Hi!", "I'm here.", "Need something?", "Hm?"]
        case 2...3: lines = pt ? ["Ei, isso faz cócegas.", "Hehe.", "De novo?"] : ["Hey, that tickles.", "Hehe.", "Again?"]
        default: lines = pt ? ["Ei! Para com isso.", "Tô ficando tonto.", "Chega, né?"] : ["Hey! Stop that.", "I'm getting dizzy.", "Enough, okay?"]
        }
        say(lines.randomElement()!, hold: 3)
    }

    func welcome(sessionCount: Int) {
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let hello = pt ? (name.isEmpty ? "Oi!" : "Oi, \(name)!") : (name.isEmpty ? "Hi!" : "Hi, \(name)!")
        let watching: String
        switch sessionCount {
        case 0: watching = pt ? "Nenhuma sessão aberta ainda." : "No sessions open yet."
        case 1: watching = pt ? "Tô de olho em uma sessão." : "Keeping an eye on one session."
        default: watching = pt ? "Tô de olho em \(sessionCount) sessões." : "Keeping an eye on \(sessionCount) sessions."
        }
        say("\(hello) \(watching)", reaction: .wave, hold: 6)
    }

    func fileCaught(_ name: String) {
        say(pt ? "Guardei \(name)." : "Got \(name).", reaction: .swallow, hold: 4)
    }

    /// The copy into the tray failed after Hatch had already said it kept the file.
    func fileFailed(_ name: String) {
        say(String(format: L10n.shared["tray_copy_failed"], name), hold: 5)
    }

    func fileHovering() {
        say(pt ? "Solta aqui que eu guardo." : "Drop it here, I'll keep it.", reaction: .catchStart, hold: 3)
    }

    func noteCreated() {
        say(pt ? "Anotado." : "Noted.", reaction: .write, hold: 3)
    }

    // MARK: Commentary

    private func advance() {
        guard Date() > holdUntil else { return }
        thinking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self else { return }
            self.thinking = false
            self.line = self.compose()
            self.turn += 1
            // Now and then it acts the line out, but not every time.
            if self.turn % 3 == 0 {
                [HatchReaction.think, .point, .scratch, .wink, .nod, .shake, .hiccup, .typing].randomElement()!.post()
            }
        }
    }

    /// Everything worth saying right now, most urgent first; the rotation walks the list.
    private func compose() -> String {
        guard let appState else { return "" }
        let sessions = appState.sessions.sorted { $0.value.lastActivity > $1.value.lastActivity }
        var lines: [String] = []
        let pt = self.pt

        for (_, s) in sessions where s.status == .waitingApproval {
            let ask = MomentStore.request(tool: s.currentTool, detail: s.toolDescription, pt: pt)
            lines.append(pt ? "\(s.projectDisplayName) \(ask.prefix(1).lowercased() + ask.dropFirst()). Dá uma olhada?"
                            : "\(s.projectDisplayName) \(ask.prefix(1).lowercased() + ask.dropFirst()). Take a look?")
        }
        for (_, s) in sessions where s.status == .waitingQuestion {
            lines.append(pt ? "\(s.projectDisplayName) tem uma pergunta pra você." : "\(s.projectDisplayName) has a question for you.")
        }
        // Something needs you: say it every other turn, and keep the rest of the
        // commentary going in between instead of repeating one line for minutes.
        let urgent = lines
        lines = []
        if !urgent.isEmpty, turn.isMultiple(of: 2) { return urgent[(turn / 2) % urgent.count] }

        let working = sessions.filter { $0.value.status == .processing || $0.value.status == .running }
        for (id, s) in working {
            let moment = MomentStore.shared.moment(for: s, sessionId: id).now
            lines.append("\(s.projectDisplayName): \(moment)")
        }
        if working.count > 1 {
            lines.append(pt ? "\(working.count) sessões trabalhando ao mesmo tempo." : "\(working.count) sessions working at once.")
        }
        for (id, s) in sessions where s.status == .idle && Date().timeIntervalSince(s.lastActivity) < 600 {
            let moment = MomentStore.shared.moment(for: s, sessionId: id).now
            lines.append(pt ? "\(s.projectDisplayName) terminou: \(moment)" : "\(s.projectDisplayName) finished: \(moment)")
        }
        for (id, s) in sessions {
            if let usage = ContextUsageStore.shared.lookup(for: s, sessionId: id), usage.pct >= 80 {
                lines.append(pt ? "\(s.projectDisplayName) já usou \(usage.pct)% do contexto."
                                : "\(s.projectDisplayName) has used \(usage.pct)% of its context.")
            }
        }
        if lines.isEmpty, !urgent.isEmpty { return urgent[(turn / 2) % urgent.count] }
        // Nobody has done anything for a while: Hatch has dozed off, and says so.
        let quietFor = Date().timeIntervalSince(sessions.first?.value.lastActivity ?? .distantPast)
        if lines.isEmpty, quietFor > 60 {
            lines = pt ? ["Zzz… tudo parado por aqui.", "Zzz…"] : ["Zzz… all quiet here.", "Zzz…"]
        }
        if lines.isEmpty {
            switch sessions.count {
            case 0: lines = pt ? ["Nenhuma sessão aberta. Bora começar algo?"] : ["No sessions open. Start something?"]
            default: lines = pt ? ["Tudo quieto. \(sessions.count) sessões esperando você.", "Nada rodando agora."]
                                : ["All quiet. \(sessions.count) sessions waiting for you.", "Nothing running right now."]
            }
        }
        return lines[turn % lines.count]
    }
}

// MARK: - The stage above the cards

/// Hatch at the head of the agents list, with a floating speech bubble.
struct HatchStage: View {
    var appState: AppState
    @ObservedObject private var director = HatchDirector.shared

    private let mascotSize: CGFloat = 50

    var body: some View {
        let mood = GlobalMood(sessions: Array(appState.sessions.values))
        HStack(alignment: .center, spacing: 16) {
            MascotView(source: mood.source, status: mood.status, size: mascotSize, global: true) { count in
                director.poked(count: count)
            }
            // The hands float outside the block; leave them room.
            .padding(.horizontal, 6)

            SpeechBubble(text: director.line, thinking: director.thinking)
                .frame(maxWidth: 420, alignment: .leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 4)
        .onAppear {
            director.attach(appState)
            director.stageAppeared()
        }
        .onDisappear { director.stageDisappeared() }
    }
}

/// A rounded bubble with a small tail pointing back at Hatch. A new line pops in; while
/// Hatch "thinks" the bubble shows three dots.
struct SpeechBubble: View {
    let text: String
    let thinking: Bool

    var body: some View {
        ZStack(alignment: .leading) {
            if thinking {
                ThinkingDots()
                    .transition(.opacity)
            } else if !text.isEmpty {
                Text(text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .id(text)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92, anchor: .leading)),
                        removal: .opacity
                    ))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            BubbleShape()
                .fill(Color(white: 0.11))
        )
        .overlay(BubbleShape().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: text)
        .animation(.easeOut(duration: 0.15), value: thinking)
    }
}

/// Rounded rectangle with a tail on the left edge, at the vertical middle.
private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 12
        let tail: CGFloat = 7
        var p = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        let midY = rect.midY
        p.move(to: CGPoint(x: rect.minX + 0.5, y: midY - tail))
        p.addLine(to: CGPoint(x: rect.minX - tail, y: midY + 1))
        p.addLine(to: CGPoint(x: rect.minX + 0.5, y: midY + tail * 0.6))
        p.closeSubpath()
        return p
    }
}

/// Three dots, one lit at a time. Ticks every 0.3s — above the 250ms line that would put
/// the panel into continuous layout — and only while Hatch is thinking.
private struct ThinkingDots: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let lit = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 3
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i == lit ? 0.85 : 0.3))
                        .frame(width: 6, height: 6)
                }
            }
            .frame(height: 16)
        }
    }
}
