import AppKit
import SwiftUI
import CodeIslandCore

// MARK: - Hatch on its own
//
// Hatch says hello when the app starts, with the time of day and what the sessions are
// doing, and now and then opens the notch by itself to say something worth saying: a run
// that has gone on for hours, a context window about to fill, the 5-hour limit getting
// close, someone still at it past midnight. Every line comes from what the hooks already
// report and the clock; the occasional musing goes through Claude Haiku only when an API
// key is saved, with the same two things BuddyVoice sends.
//
// It speaks only when the notch is closed and nothing needs the user, never twice within
// ten minutes, and each kind of remark has its own cooldown so it doesn't repeat itself.

@MainActor
final class HatchCompanion {
    static let shared = HatchCompanion()

    private weak var appState: AppState?
    private weak var panel: PanelWindowController?
    private var timer: Timer?
    private var lastSpoke = Date.distantPast
    private var fired: [String: Date] = [:]
    /// When the current unbroken stretch of work began, and when something last ran.
    private var busySince: Date?
    private var lastBusy: Date?
    /// The most recent activity seen on the previous tick, to notice a return after a pause.
    private var previousActivity: Date?

    private static let tick: TimeInterval = 60
    private static let minimumGap: TimeInterval = 10 * 60

    private var pt: Bool { L10n.shared.effectiveLanguage == "pt" }
    private var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.hatchSpontaneous) as? Bool ?? SettingsDefaults.hatchSpontaneous
    }

    func start(appState: AppState, panel: PanelWindowController?) {
        self.appState = appState
        self.panel = panel
        guard !ProcessInfo.processInfo.arguments.contains("--preview") else { return }
        // Saved sessions are restored at launch; a beat later is enough to count them, and
        // the hello is the first thing the notch shows.
        greet(attempt: 0, after: 0.9)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        timer?.tolerance = 10
    }

    // MARK: Hello

    #if DEBUG
    func greetForPreview() { greet(attempt: 0, after: 0.2) }
    #endif

    private func greet(attempt: Int, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            // With Hatch's remarks turned off, the plain boot flash shows instead.
            guard let self, let appState = self.appState, self.enabled else { return }
            // Something already needs the user (a permission, a question): say hello later.
            // A run that ends as the app opens (often this very session) put its summary in
            // the notch first, and the hello waited behind it. The hello comes first now.
            if case .completionCard = appState.surface, !appState.hasPendingInteraction {
                appState.cancelCompletionQueue()
                appState.surface = .collapsed
            }
            guard self.canSpeak(ignoringGap: true) else {
                if attempt < 8 { self.greet(attempt: attempt + 1, after: 5) }
                return
            }
            var (title, text) = self.greeting(for: appState)
            var reaction = HatchReaction.wave
            if let from = UserDefaults.standard.string(forKey: SettingsKey.updatedFrom) {
                UserDefaults.standard.removeObject(forKey: SettingsKey.updatedFrom)
                let now = AppVersion.current
                if from != now {
                    title = self.pt ? "Atualizei pra versão \(now)!" : "Updated to version \(now)!"
                    text = (self.pt ? "Estava na \(from). " : "I was on \(from). ") + text
                    reaction = .cheer
                }
            }
            self.present(title: title, text: text, reaction: reaction, duration: 6.5, key: nil)
            HatchDirector.shared.say(title, reaction: nil, hold: 8)
        }
    }

    private func greeting(for appState: AppState) -> (String, String) {
        let now = Date()
        let hour = Calendar.current.component(.hour, from: now)
        let name = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let hello: String
        switch hour {
        case 5..<12: hello = pt ? "Bom dia" : "Good morning"
        case 12..<18: hello = pt ? "Boa tarde" : "Good afternoon"
        default: hello = pt ? "Boa noite" : "Good evening"
        }
        let title = name.isEmpty ? "\(hello)!" : "\(hello), \(name)!"

        let sessions = Array(appState.sessions.values)
        let working = sessions.filter { $0.status == .processing || $0.status == .running }.count
        let waiting = sessions.filter { $0.status == .waitingApproval || $0.status == .waitingQuestion }.count
        var text: String
        switch (sessions.count, working) {
        case (0, _):
            text = pt ? "Nenhuma sessão aberta ainda. Quando começar, eu fico de olho."
                      : "No sessions open yet. Start one and I'll keep an eye on it."
        case (1, 1):
            text = pt ? "Uma sessão aberta, e ela já está trabalhando." : "One session open, and it's already working."
        case (1, _):
            text = pt ? "Uma sessão aberta, esperando por você." : "One session open, waiting for you."
        case (let n, 0):
            text = pt ? "\(n) sessões abertas, todas paradas." : "\(n) sessions open, all idle."
        case (let n, let w):
            text = pt ? "\(n) sessões abertas, \(w) trabalhando agora." : "\(n) sessions open, \(w) working right now."
        }
        if waiting > 0 {
            text += pt ? " \(waiting) precisa\(waiting == 1 ? "" : "m") de você." : " \(waiting) need\(waiting == 1 ? "s" : "") you."
        }
        if hour >= 23 || hour < 5 {
            text += pt ? " Trabalhando até tarde, hein?" : " Working late, huh?"
        } else if Calendar.current.component(.weekday, from: now) == 2, hour < 12 {
            text += pt ? " Começo de semana. Bora." : " New week. Let's go."
        } else if Calendar.current.component(.weekday, from: now) == 6, hour >= 16 {
            text += pt ? " Sexta à tarde, quase lá." : " Friday afternoon, almost there."
        }
        return (title, text)
    }

    // MARK: Now and then

    private func evaluate() {
        guard let appState else { return }
        let now = Date()
        let sessions = Array(appState.sessions.values)
        let working = appState.sessions.filter { $0.value.status == .processing || $0.value.status == .running }
            .map { (id: $0.key, session: $0.value) }

        // Keep track of stretches of work and pauses even while Hatch stays quiet.
        let latest = sessions.map(\.lastActivity).max()
        if !working.isEmpty {
            if busySince == nil { busySince = now }
            lastBusy = now
        } else if let lastBusy, now.timeIntervalSince(lastBusy) > 15 * 60 {
            busySince = nil
        }
        let returning: TimeInterval? = {
            guard let latest, let previous = previousActivity, latest > previous else { return nil }
            let gap = latest.timeIntervalSince(previous)
            return gap >= 45 * 60 ? gap : nil
        }()
        previousActivity = latest

        guard enabled, canSpeak(ignoringGap: false) else { return }
        guard let remark = pickRemark(sessions: sessions, working: working, latest: latest, returning: returning, now: now)
        else { return }
        present(title: remark.title, text: remark.text, reaction: remark.reaction, duration: 6, key: remark.key)
    }

    private struct Remark {
        let key: String
        let cooldown: TimeInterval
        let title: String
        let text: String
        let reaction: HatchReaction
    }

    /// The most useful thing to say right now, or nothing. Earlier entries matter more.
    private func pickRemark(sessions: [SessionSnapshot], working: [(id: String, session: SessionSnapshot)], latest: Date?,
                            returning: TimeInterval?, now: Date) -> Remark? {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let weekday = cal.component(.weekday, from: now)
        let day = Self.dayKey(now)
        let recentlyActive = latest.map { now.timeIntervalSince($0) < 10 * 60 } ?? false
        var candidates: [Remark] = []

        // The 5-hour Claude window is nearly used up.
        if let lim = ClaudeRateLimitReader.shared.limits, lim.isFresh, let pct = lim.fiveHourPercent, pct >= 80 {
            let resets = lim.fiveHourResetAt.map { Self.duration($0.timeIntervalSince(now)) }
            let window = lim.fiveHourResetAt.map { String(Int($0.timeIntervalSince1970 / 3600)) } ?? day
            candidates.append(Remark(
                key: "usage-\(window)-\(pct >= 95 ? "hi" : "lo")", cooldown: 5 * 3600,
                title: pt ? "\(pct)% do limite de 5h do Claude" : "\(pct)% of Claude's 5-hour limit",
                text: (resets.map { pt ? "Renova em \($0)." : "Resets in \($0)." } ?? "")
                    + (pct >= 95 ? (pt ? " Talvez valha segurar as sessões pesadas." : " Maybe hold off on the heavy sessions.") : ""),
                reaction: .surprised))
        }

        // A working session whose context is about to be summarised.
        for (id, s) in working {
            guard let usage = ContextUsageStore.shared.lookup(for: s, sessionId: id), usage.pct >= 85 else { continue }
            candidates.append(Remark(
                key: "ctx-\(id)", cooldown: 45 * 60,
                title: pt ? "\(s.projectDisplayName) já usou \(usage.pct)% do contexto" : "\(s.projectDisplayName) has used \(usage.pct)% of its context",
                text: pt ? "Logo ele resume a conversa sozinho. Bom momento pra fechar o assunto."
                         : "It will summarise the conversation soon. A good moment to wrap up the topic.",
                reaction: .surprised))
        }

        // Still at it in the small hours.
        if recentlyActive, hour >= 23 || hour < 5 {
            candidates.append(Remark(
                key: "late-\(Self.dayKey(now.addingTimeInterval(-6 * 3600)))", cooldown: 3 * 3600,
                title: hour >= 23 ? (pt ? "Já passou das 23h" : "It's past 11 pm")
                                  : (pt ? "Já são \(hour)h da manhã" : "It's \(hour) am"),
                text: pt ? "Vai descansar. Eu fico de olho nas sessões e aviso se precisar."
                         : "Get some rest. I'll watch the sessions and tell you if anything needs you.",
                reaction: .scratch))
        }

        // Back after a long pause.
        if let returning {
            candidates.append(Remark(
                key: "back", cooldown: 2 * 3600,
                title: pt ? "De volta!" : "Welcome back!",
                text: pt ? "Ficou \(Self.duration(returning)) longe. \(sessions.count) sessões continuam abertas."
                         : "You were away for \(Self.duration(returning)). \(sessions.count) sessions are still open.",
                reaction: .wave))
        }

        // A long unbroken stretch of work.
        if let busySince, now.timeIntervalSince(busySince) >= 100 * 60 {
            candidates.append(Remark(
                key: "break", cooldown: 90 * 60,
                title: pt ? "\(Self.duration(now.timeIntervalSince(busySince))) de trabalho seguido"
                          : "\(Self.duration(now.timeIntervalSince(busySince))) of work without a break",
                text: pt ? "Que tal levantar e beber uma água? Eu chamo se alguém precisar de você."
                         : "How about a stretch and some water? I'll call you if anyone needs you.",
                reaction: .point))
        }

        // Lunch on a weekday.
        if recentlyActive, (2...6).contains(weekday), hour == 12 || (hour == 13 && minute < 30) {
            candidates.append(Remark(
                key: "lunch-\(day)", cooldown: 20 * 3600,
                title: pt ? "Hora do almoço" : "Lunch time",
                text: pt ? "Pode ir comer. Eu cuido das sessões." : "Go eat. I'll look after the sessions.",
                reaction: .wave))
        }

        // Several agents at once.
        if working.count >= 3 {
            candidates.append(Remark(
                key: "many", cooldown: 60 * 60,
                title: pt ? "\(working.count) agentes trabalhando ao mesmo tempo" : "\(working.count) agents working at once",
                text: pt ? "Tô de olho em todos. Te chamo se algum travar." : "I'm watching all of them. I'll call you if one gets stuck.",
                reaction: .clap))
        }

        // Friday afternoon.
        if recentlyActive, weekday == 6, hour >= 16 {
            candidates.append(Remark(
                key: "friday-\(day)", cooldown: 20 * 3600,
                title: pt ? "Sexta à tarde" : "Friday afternoon",
                text: pt ? "Deploy hoje? Corajoso. Eu fico de olho." : "Deploying today? Brave. I'll keep watch.",
                reaction: .wink))
        }

        if let remark = candidates.first(where: { isReady($0.key, cooldown: $0.cooldown, now: now) }) {
            return remark
        }

        // Nothing in particular: once in a while, a line in the companion's own voice.
        if recentlyActive, now.timeIntervalSince(lastSpoke) > 30 * 60, Double.random(in: 0...1) < 0.3 {
            muse(sessions: sessions, now: now)
        }
        return nil
    }

    private func muse(sessions: [SessionSnapshot], now: Date) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEEE HH:mm"
        let doing = sessions.prefix(5).map { "\($0.projectDisplayName): \(MomentStore.localMoment(for: $0).now)" }
        let situation = "It is \(f.string(from: now)). " + (doing.isEmpty ? "No sessions." : doing.joined(separator: "; "))
        let hour = Calendar.current.component(.hour, from: now)
        Task { @MainActor [weak self] in
            let written = await BuddyVoice.line(buddy: BuddyReader.shared.buddy, mood: .philosopher, situation: situation)
            guard let self, self.canSpeak(ignoringGap: false) else { return }
            let line = written ?? self.fallbackMusing(hour: hour)
            self.present(title: line, text: "", reaction: [.think, .shrug, .wink].randomElement()!, duration: 5.5, key: "muse")
        }
    }

    private func fallbackMusing(hour: Int) -> String {
        switch hour {
        case 5..<12: return pt ? ["Café já foi?", "Manhã rendendo por aqui."].randomElement()! : ["Had your coffee yet?", "Productive morning so far."].randomElement()!
        case 12..<18: return pt ? ["Lembra de beber água.", "Tarde rendendo."].randomElement()! : ["Remember to drink some water.", "Good afternoon so far."].randomElement()!
        case 18..<23: return pt ? ["Fim de dia chegando.", "Ainda firme por aí?"].randomElement()! : ["The day is winding down.", "Still going strong?"].randomElement()!
        default: return pt ? "Noite tranquila por aqui." : "Quiet night here."
        }
    }

    // MARK: Showing it

    /// Closed notch, nothing waiting on the user, the mouse elsewhere, and (unless it's the
    /// hello) a quiet spell since the last remark.
    private func canSpeak(ignoringGap: Bool) -> Bool {
        guard let appState else { return false }
        guard appState.surface == .collapsed, !appState.hasPendingInteraction else { return false }
        guard !(panel?.isMouseOverContent ?? false), !TrayStage.shared.isBusy else { return false }
        return ignoringGap || Date().timeIntervalSince(lastSpoke) >= Self.minimumGap
    }

    private func present(title: String, text: String, reaction: HatchReaction, duration: TimeInterval, key: String?) {
        guard let appState else { return }
        lastSpoke = Date()
        if let key { fired[key] = lastSpoke }
        appState.showBuddySpeech(text: text, mood: .idle, title: title, reaction: reaction, duration: duration)
    }

    private func isReady(_ key: String, cooldown: TimeInterval, now: Date) -> Bool {
        guard let last = fired[key] else { return true }
        return now.timeIntervalSince(last) >= cooldown
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// "1h40", "45 min", "2h".
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int(seconds / 60))
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h)h" : String(format: "%dh%02d", h, m)
    }
}

// MARK: - The stage for those moments

/// Hatch's own moment in the open notch: it comes down big in the middle, acts out the
/// reaction, then steps aside to the left and the words appear beside it. Same motion as
/// the finished-run summary, three one-shot springs and then nothing moves.
struct HatchSpotlight: View {
    let speech: BuddySpeech
    var appState: AppState
    let onDismiss: () -> Void

    @State private var stepAside = false
    @State private var showText = false

    private let mascotSize: CGFloat = 64
    private let sidePadding: CGFloat = 20

    var body: some View {
        let mood = GlobalMood(sessions: Array(appState.sessions.values))
        GeometryReader { geo in
            let centred = (geo.size.width - mascotSize) / 2 - sidePadding
            HStack(alignment: .center, spacing: 18) {
                MascotView(source: mood.source, status: .idle, size: mascotSize, global: true)
                    .offset(x: stepAside ? 0 : centred)

                VStack(alignment: .leading, spacing: 6) {
                    if let title = speech.title {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !speech.text.isEmpty {
                        Text(speech.text)
                            .font(.system(size: speech.title == nil ? 14 : 12))
                            .foregroundStyle(.white.opacity(speech.title == nil ? 0.92 : 0.62))
                            .lineSpacing(2)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if speech.title == nil, let name = BuddyReader.shared.buddy?.name {
                        Text(name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .opacity(showText ? 1 : 0)
                .offset(x: showText ? 0 : 24)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, sidePadding)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 132)
        .contentShape(Rectangle())
        .onTapGesture(perform: onDismiss)
        .onAppear(perform: present)
    }

    private func present() {
        // The reaction plays while Hatch is still in the middle, then it makes room.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { speech.reaction?.post() }
        guard !Motion.isReduced else {
            stepAside = true
            showText = true
            return
        }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(1.1)) { stepAside = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(1.35)) { showText = true }
    }
}
