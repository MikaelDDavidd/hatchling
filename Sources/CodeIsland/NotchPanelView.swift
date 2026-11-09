import SwiftUI
import UniformTypeIdentifiers
import CodeIslandCore

struct NotchPanelView: View {
    var appState: AppState
    let hasNotch: Bool
    let notchHeight: CGFloat
    let notchW: CGFloat
    let screenWidth: CGFloat

    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    @AppStorage(SettingsKey.smartSuppress) private var smartSuppress = SettingsDefaults.smartSuppress
    @AppStorage(SettingsKey.hideWhenNoSession) private var hideWhenNoSession = SettingsDefaults.hideWhenNoSession
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus
    @AppStorage(SettingsKey.collapsedWidthScale) private var collapsedWidthScale = SettingsDefaults.collapsedWidthScale
    @AppStorage(SettingsKey.hapticOnHover) private var hapticOnHover = SettingsDefaults.hapticOnHover
    @AppStorage(SettingsKey.hapticIntensity) private var hapticIntensity = SettingsDefaults.hapticIntensity
    @AppStorage(SettingsKey.selectedPanelTab) private var selectedPanelTab = SettingsDefaults.selectedPanelTab

    /// Delayed hover: prevents accidental expansion when mouse passes through
    @State private var hoverTimer: Timer?
    @State private var isHovered = false
    @State private var idleHovered = false
    /// File drag is hovering over the notch (auto-expands and switches to FILES tab)
    @State private var isFileDragTargeted = false
    /// Curtain animation for tool status toggle
    @State private var curtainOffset: CGFloat = 0
    @State private var curtainOpacity: Double = 1
    @State private var displayedToolStatus: Bool = SettingsDefaults.showToolStatus

    private var isActive: Bool { !appState.sessions.isEmpty }
    /// First launch / no-session state should still render a visible marker so the app
    /// doesn't disappear completely behind the physical notch.
    private var showIdleIndicator: Bool {
        !isActive && !hideWhenNoSession
    }
    /// Whether the bar content should be visible (respects hideWhenNoSession)
    private var showBar: Bool {
        isActive && !(hideWhenNoSession && appState.activeSessionCount == 0)
    }
    private var shouldShowExpanded: Bool {
        showBar && appState.surface.isExpanded
    }

    /// Mascot size — fits within the menu bar height
    private var mascotSize: CGFloat { min(27, notchHeight - 6) }

    /// Minimum wing width needed to display compact bar content
    private var compactWingWidth: CGFloat { mascotSize + 14 }

    /// Effective notch width — applies user scale on non-notch screens (#56).
    private var effectiveNotchW: CGFloat {
        guard !hasNotch else { return notchW }
        let scale = CGFloat(max(collapsedWidthScale, 50)) / 100.0
        return notchW * scale
    }

    /// Width needed by the left wing: the one global Hatch.
    private var leftWingWidth: CGFloat { mascotSize + 14 }

    /// Width needed by the right wing — biggest when a usage alert shows,
    /// medium for gerund verb, smallest for the idle counter.
    private var rightWingWidth: CGFloat {
        if UsageAlertCenter.shared.pending != nil { return 130 } // "Codex 5h: 85%"
        let baseCounter: CGFloat = 26
        guard appState.sessions.values.contains(where: {
            $0.status == .processing || $0.status == .running
        }) else { return baseCounter + 14 }
        return 90 // "Murmuring…"
    }

    /// Total panel width — adapts based on state and screen geometry
    private var panelWidth: CGFloat {
        let nw = effectiveNotchW
        let maxWidth = min(620, screenWidth - 40)
        if showIdleIndicator { return idleHovered ? nw + compactWingWidth * 2 + 80 : nw + compactWingWidth * 2 }
        if !isActive { return hasNotch ? notchW - 20 : nw }
        if shouldShowExpanded { return min(max(nw + 200, 580), maxWidth) }
        let extra: CGFloat = appState.status == .idle ? 0 : 8
        // Reserve space for tool status — proportional to screen width
        let toolExtra: CGFloat = displayedToolStatus ? (hasNotch ? screenWidth * 0.03 : screenWidth * 0.04) : 0
        return nw + leftWingWidth + rightWingWidth + extra + toolExtra
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                if showBar {
                    // Active: compact bar — wider version when expanded
                    HStack(spacing: 0) {
                        CompactLeftWing(appState: appState, expanded: shouldShowExpanded, mascotSize: mascotSize, hasNotch: hasNotch, showToolStatus: showToolStatus)
                        if hasNotch && !shouldShowExpanded {
                            Spacer(minLength: notchW)
                        } else if !shouldShowExpanded && showToolStatus {
                            CompactToolStatus(appState: appState)
                            Spacer(minLength: 0)
                        } else {
                            Spacer(minLength: 0)
                        }
                        CompactRightWing(appState: appState, expanded: shouldShowExpanded, hasNotch: hasNotch)
                    }
                    .frame(height: notchHeight)
                } else if showIdleIndicator {
                    IdleIndicatorBar(
                        mascotSize: mascotSize,
                        compactWingWidth: compactWingWidth,
                        notchW: notchW,
                        notchHeight: notchHeight,
                        hasNotch: hasNotch,
                        hovered: idleHovered
                    )
                } else {
                    // Idle: just the notch shell
                    Spacer()
                        .frame(height: notchHeight)
                }

                // Below-notch expanded content
                if shouldShowExpanded {
                    // Everything below the notch sits in one inset tray, so the black shell reads
                    // as a frame and the content as the thing inside it.
                    VStack(spacing: 0) {
                        // Hatch's own moments (hello, a word now and then) take the whole tray.
                        if appState.surface != .buddySpeech {
                            VStack(alignment: .leading, spacing: 8) {
                                // Anthropic public status
                                StatusBar()
                                // Live usage (Codex local; per-session % on each card)
                                UsageBar()
                            }
                            .padding(.top, 12)
                        }

                        surfaceContent
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white.opacity(0.035))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    // Opening: the shell springs out first and the tray follows a beat behind,
                    // dropping into place. Closing: the tray is gone before the shell shrinks.
                    .transition(.asymmetric(
                        insertion: .offset(y: -10)
                            .combined(with: .scale(scale: 0.97, anchor: .top))
                            .combined(with: .opacity)
                            .animation(.spring(response: 0.44, dampingFraction: 0.8).delay(0.06)),
                        removal: .opacity.animation(.easeOut(duration: 0.1))
                    ))
                }
            }
            .frame(width: panelWidth)
            // Fit content vertically — the NSHostingView gives us the full
            // panel height, but the black notch shape should hug the actual
            // content (especially in completion mode where 1 card otherwise
            // leaves a huge empty void below it).
            .fixedSize(horizontal: false, vertical: true)
            .clipped()
            .background(
                NotchPanelShape(
                    topExtension: shouldShowExpanded ? 14 : 3,
                    bottomRadius: shouldShowExpanded ? 28 : 12,
                    minHeight: notchHeight
                )
                .fill(.black)
            )
            .offset(y: curtainOffset)
            .opacity(curtainOpacity)
            .onChange(of: showToolStatus) { _, newValue in
                // Phase 1: entire bar slides up and fades out
                withAnimation(.easeIn(duration: 0.2)) {
                    curtainOffset = -notchHeight
                    curtainOpacity = 0
                }
                // Phase 2: switch width while hidden
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    displayedToolStatus = newValue
                }
                // Phase 3: entire bar slides back down
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        curtainOffset = 0
                        curtainOpacity = 1
                    }
                }
            }
            .onAppear { displayedToolStatus = showToolStatus }
            .onDrop(of: [UTType.fileURL], isTargeted: $isFileDragTargeted, perform: handleNotchFileDrop)
            .onChange(of: isFileDragTargeted) { _, targeted in
                if targeted {
                    TrayStage.shared.dragEntered("panel")
                } else {
                    TrayStage.shared.dragExited("panel")
                }
                if targeted {
                    selectedPanelTab = PanelTab.files.rawValue
                    if !appState.surface.isExpanded {
                        withAnimation(NotchAnimation.open) {
                            appState.surface = .sessionList
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .onHover { hovering in
                if DebugFlags.pinOpen { return }
                // Idle indicator hover — delay un-hover to prevent oscillation when
                // the animated width change crosses the mouse position (#52).
                if showIdleIndicator {
                    if hovering {
                        hoverTimer?.invalidate()
                        hoverTimer = nil
                        withAnimation(NotchAnimation.micro) { idleHovered = true }
                    } else {
                        hoverTimer?.invalidate()
                        hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { _ in
                            Task { @MainActor in
                                withAnimation(NotchAnimation.micro) { idleHovered = false }
                            }
                        }
                    }
                    return
                }
                switch appState.surface {
                case .approvalCard, .questionCard: return
                case .completionCard:
                    // Completion card: mark entered on hover-in, block collapse until entered
                    if hovering {
                        appState.completionHasBeenEntered = true
                    } else if appState.completionHasBeenEntered || appState.deferCollapseOnMouseLeave {
                        // Mouse entered then left — allow collapse (immediate or deferred)
                        hoverTimer?.invalidate()
                        hoverTimer = nil
                        appState.deferCollapseOnMouseLeave = false
                        appState.cancelCompletionQueue()
                        withAnimation(NotchAnimation.close) {
                            appState.surface = .collapsed
                        }
                    }
                    return
                default: break
                }
                // Respect collapseOnMouseLeave setting
                if !hovering && !SettingsManager.shared.collapseOnMouseLeave { return }
                // A file is being swallowed: stay open until it is in the tray, wherever the
                // mouse went. TrayStage closes the panel itself when it is done.
                if !hovering && TrayStage.shared.isBusy { isHovered = false; return }
                // Smart suppress: don't auto-expand when active session's terminal is foreground
                if hovering && smartSuppress {
                    if let delegate = NSApp.delegate as? AppDelegate,
                       let pc = delegate.panelController,
                       pc.isActiveTerminalForeground() {
                        return
                    }
                }

                isHovered = hovering
                if hovering {
                    // Delay expansion to avoid accidental triggers
                    hoverTimer?.invalidate()
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                        Task { @MainActor in
                            // Guard: mouse may have left during the delay
                            guard isHovered else { return }
                            if hapticOnHover {
                                let performer = NSHapticFeedbackManager.defaultPerformer
                                switch hapticIntensity {
                                case 3: // strong: two taps
                                    performer.perform(.levelChange, performanceTime: .now)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                        performer.perform(.levelChange, performanceTime: .now)
                                    }
                                case 2: // medium
                                    performer.perform(.levelChange, performanceTime: .default)
                                default: // light
                                    performer.perform(.alignment, performanceTime: .default)
                                }
                            }
                            withAnimation(NotchAnimation.open) {
                                // If the user force-collapsed a pending question/permission,
                                // reopen that card instead of the regular session list.
                                if appState.hasPendingInteraction {
                                    appState.reopenPendingSurface()
                                } else {
                                    appState.surface = .sessionList
                                    appState.cancelCompletionQueue()
                                    if appState.activeSessionId == nil {
                                        appState.activeSessionId = appState.sessions.keys.sorted().first
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Collapse with brief delay to prevent flicker on accidental mouse-out
                    hoverTimer?.invalidate()
                    hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                        Task { @MainActor in
                            guard !isHovered else { return }
                            withAnimation(NotchAnimation.close) {
                                appState.surface = .collapsed
                            }
                        }
                    }
                }
            }

            Spacer()
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(NotchAnimation.open, value: appState.surface)
    }

    /// What fills the panel under the status and usage bars, by surface.
    @ViewBuilder
    private var surfaceContent: some View {
        switch appState.surface {
        case .approvalCard(let sid):
            if let pending = appState.pendingPermission {
                ApprovalBar(
                    tool: pending.event.toolName ?? "Unknown",
                    toolInput: pending.event.toolInput,
                    session: appState.sessions[sid],
                    sessionId: sid,
                    queuePosition: 1,
                    queueTotal: appState.permissionQueue.count,
                    onAllow: { appState.approvePermission(always: false) },
                    onAlwaysAllow: { appState.approvePermission(always: true) },
                    onDeny: { appState.denyPermission() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        case .questionCard(let sid):
            let session = appState.sessions[sid]
            if let q = appState.pendingQuestion {
                QuestionBar(
                    question: q.question.question,
                    options: q.question.options,
                    descriptions: q.question.descriptions,
                    allQuestions: q.askUserQuestionState?.items ?? [],
                    session: session,
                    sessionId: sid,
                    queuePosition: 1,
                    queueTotal: appState.questionQueue.count,
                    onAnswer: { appState.answerQuestion($0) },
                    onAnswerMulti: { appState.answerQuestionMulti($0) },
                    onSkip: { appState.skipQuestion() }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            } else if let preview = appState.previewQuestionPayload {
                QuestionBar(
                    question: preview.question,
                    options: preview.options,
                    descriptions: preview.descriptions,
                    allQuestions: [],
                    session: session,
                    sessionId: sid,
                    queuePosition: 1,
                    queueTotal: 1,
                    onAnswer: { _ in },
                    onAnswerMulti: { _ in },
                    onSkip: { }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        case .completionCard(let sid):
            if let session = appState.sessions[sid] {
                SummaryStage(sessionId: sid, session: session, appState: appState)
                    .transition(.opacity)
            } else {
                SessionListView(appState: appState, onlySessionId: appState.justCompletedSessionId)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        case .sessionList:
            PanelTabContent(appState: appState)
                .transition(.asymmetric(
                    insertion: .offset(x: -36).combined(with: .opacity),
                    removal: .offset(x: -36).combined(with: .opacity)
                ))
        case .sessionChat(let sid):
            if let session = appState.sessions[sid] {
                // The chat is a level deeper than the list, so it comes in from the
                // right and leaves the same way, like a page being pushed.
                SessionChatView(sessionId: sid, session: session, appState: appState)
                    .transition(.asymmetric(
                        insertion: .offset(x: 48).combined(with: .opacity),
                        removal: .offset(x: 48).combined(with: .opacity)
                    ))
            }
        case .buddySpeech:
            if let speech = appState.pendingBuddySpeech {
                HatchSpotlight(speech: speech, appState: appState, onDismiss: { appState.dismissBuddySpeech() })
                    .id(speech.id)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        case .collapsed:
            EmptyView()
        }
    }

    private func handleNotchFileDrop(providers: [NSItemProvider]) -> Bool {
        var didAccept = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                var url: URL?
                if let urlData = data as? Data {
                    url = URL(dataRepresentation: urlData, relativeTo: nil)
                } else if let u = data as? URL {
                    url = u
                }
                guard let fileURL = url else { return }
                Task { @MainActor in
                    TrayFeed.feed(fileURL)
                }
            }
            didAccept = true
        }
        return didAccept
    }
}


// MARK: - Compact Wings (notch-level, 32px height)

/// Left side: pixel character + status info
private struct CompactLeftWing: View {
    var appState: AppState
    let expanded: Bool
    let mascotSize: CGFloat
    let hasNotch: Bool
    let showToolStatus: Bool

    private var displaySession: SessionSnapshot? {
        let sid = appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
        guard let sid else { return nil }
        return appState.sessions[sid]
    }
    private var displaySource: String { displaySession?.source ?? appState.primarySource }
    @AppStorage(SettingsKey.selectedPanelTab) private var selectedPanelTab = SettingsDefaults.selectedPanelTab
    /// Whether a big Hatch is on screen further down — the summary of a finished run, or
    /// the stage at the head of the agents list — so the header one steps aside.
    private var isPresenting: Bool {
        switch appState.surface {
        case .completionCard, .buddySpeech: return true
        case .sessionList: return selectedPanelTab != PanelTab.notes.rawValue
        default: return false
        }
    }
    private var displayStatus: AgentStatus { displaySession?.status ?? .idle }
    private var liveTool: String? { displaySession?.currentTool }

    @State private var shownTool: String?
    @State private var lingerTimer: Timer?

    var body: some View {
        HStack(spacing: 6) {
            if expanded {
                // Hatch stands at the head of the panel in the mood of the session that most
                // needs attention, so the panel has a face even before you read a card.
                let mood = GlobalMood(sessions: Array(appState.sessions.values), fallbackSource: displaySource)
                MascotView(source: mood.source, status: mood.status, size: 30, global: true)
                    .padding(.trailing, 2)
                    // While it presents a finished run it is down in the panel, big; the header
                    // spot stays empty so there is only ever one of it on screen.
                    .opacity(isPresenting ? 0 : 1)
                    .animation(.easeOut(duration: 0.2), value: isPresenting)
                PanelTabSelector()
            } else {
                // One Hatch for every session, in the mood of whichever needs you most.
                let mood = GlobalMood(sessions: Array(appState.sessions.values), fallbackSource: displaySource)
                MascotView(source: mood.source, status: mood.status, size: mascotSize, global: true)
                    .transition(.opacity)

                // On notch screens, show tool name from the focus session.
                // Long MCP names like "mcp__playwright__browser_console_messages"
                // get shortened & truncated so they don't blow out the layout.
                if hasNotch, showToolStatus, let tool = shownTool {
                    Text(shortenToolName(tool))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(toolStatusColor(tool))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 160)
                        .help(tool)
                        .transition(.opacity)
                }
            }
        }
        .padding(.leading, 6)
        .clipped()
        .onChange(of: liveTool) { _, newTool in
            lingerTimer?.invalidate()
            if let newTool {
                withAnimation(.easeInOut(duration: 0.2)) { shownTool = newTool }
            } else {
                lingerTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.3)) { shownTool = nil }
                    }
                }
            }
        }
        // Session rotation: immediately sync tool to avoid stale linger from previous session
        .onChange(of: appState.rotatingSessionId) { _, _ in
            lingerTimer?.invalidate()
            let newTool = liveTool
            withAnimation(.easeInOut(duration: 0.2)) { shownTool = newTool }
        }
    }
}

/// Right side: project name + session count (detailed) or just count (simple)
private struct CompactRightWing: View {
    var appState: AppState
    let expanded: Bool
    let hasNotch: Bool
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var alerts = UsageAlertCenter.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled
    @AppStorage(SettingsKey.showToolStatus) private var showToolStatus = SettingsDefaults.showToolStatus
    @AppStorage(SettingsKey.autoAcceptPermissions) private var autoAcceptPermissions = SettingsDefaults.autoAcceptPermissions

    private var displaySessionId: String? {
        appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
    }
    private var projectName: String? {
        guard let sid = displaySessionId, let cwd = appState.sessions[sid]?.cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    /// What the working session is doing, in a few words ("Editando Foo.swift"), or nil
    /// so the session counter shows. Real information instead of a random playful verb.
    private var activeStep: String? {
        let working = appState.sessions.values.filter { $0.status == .processing || $0.status == .running }
        guard !working.isEmpty else { return nil }
        let snap = displaySessionId.flatMap { appState.sessions[$0] }
            .flatMap { ($0.status == .processing || $0.status == .running) ? $0 : nil } ?? working.first!
        return MomentStore.localMoment(for: snap).now
    }

    @ViewBuilder
    private func sessionCounter(fontSize: CGFloat, weight: Font.Weight) -> some View {
        HStack(spacing: 1) {
            let active = appState.activeSessionCount
            let total = appState.totalSessionCount
            if active > 0 {
                Text("\(active)")
                    .foregroundStyle(Color(red: 0.4, green: 1.0, blue: 0.5))
                Text("/")
                    .foregroundStyle(.white.opacity(0.4))
            }
            Text("\(total)")
                .foregroundStyle(.white.opacity(0.9))
        }
        .font(.system(size: fontSize, weight: weight, design: .monospaced))
    }

    var body: some View {
        HStack(spacing: expanded ? 2 : 6) {
            if expanded {
                NotchIconButton(icon: "chevron.up", tooltip: l10n["collapse"]) {
                    appState.collapsePanel()
                }
                NotchIconButton(icon: soundEnabled ? "speaker.wave.2" : "speaker.slash", tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]) {
                    soundEnabled.toggle()
                }
                NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                    SettingsWindowController.shared.show()
                }
                NotchIconButton(icon: "power", tint: Color(red: 1.0, green: 0.4, blue: 0.4), tooltip: l10n["quit"]) {
                    NSApplication.shared.terminate(nil)
                }
            } else {
                // YOLO mode badge — always-visible when auto-accept is on
                if autoAcceptPermissions {
                    Text("YOLO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.20))
                        .help("YOLO mode active — permissions auto-accepted")
                }

                if let alert = alerts.pending {
                    Text(alert.text)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(alert.color)
                        .lineLimit(1)
                        .transition(.opacity)
                } else if let step = activeStep {
                    Text(step)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 150, alignment: .trailing)
                        .transition(.opacity)
                } else if showToolStatus {
                    sessionCounter(fontSize: 12, weight: .semibold)
                } else {
                    sessionCounter(fontSize: 13, weight: .bold)
                }
            }
        }
        .padding(.trailing, 6)
    }
}

private struct ContextProgressTrack: View {
    let pct: Int
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color.opacity(0.15))
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(pct, 0), 100)) / 100.0)
            }
        }
    }
}

/// Make a tool identifier fit in the notch. MCP names look like
/// "mcp__playwright__browser_console_messages" — we strip the `mcp__`
/// prefix and replace the remaining `__` with a middle-dot so the
/// server is still visible but short.
private func shortenToolName(_ raw: String) -> String {
    var t = raw
    if t.hasPrefix("mcp__") { t.removeFirst("mcp__".count) }
    t = t.replacingOccurrences(of: "__", with: "·")
    return t
}

// MARK: - Tool Status Helpers

/// Accent color for each tool category — shared between notch and non-notch views
private func toolStatusColor(_ tool: String) -> Color {
    switch tool.lowercased() {
    case "bash": return Color(red: 0.4, green: 1.0, blue: 0.5)
    case "edit", "write": return Color(red: 0.5, green: 0.7, blue: 1.0)
    case "read": return Color(red: 0.9, green: 0.8, blue: 0.4)
    case "grep", "glob": return Color(red: 0.8, green: 0.6, blue: 1.0)
    case "agent": return Color(red: 1.0, green: 0.6, blue: 0.4)
    default: return .white.opacity(0.7)
    }
}

// MARK: - Compact Tool Status (non-notch center area)

/// Shows the current tool activity in the center of the bar on non-notch screens.
/// Keeps the last tool visible for a short linger period to avoid flashing.
private struct CompactToolStatus: View {
    var appState: AppState

    /// Single source of truth: all fields derive from the same session.
    private var displaySessionId: String? {
        appState.rotatingSessionId ?? appState.activeSessionId ?? appState.sessions.keys.sorted().first
    }
    private var displaySession: SessionSnapshot? {
        guard let sid = displaySessionId else { return nil }
        return appState.sessions[sid]
    }
    private var liveTool: String? { displaySession?.currentTool }
    private var liveDesc: String? { displaySession?.toolDescription }
    private var displayStatus: AgentStatus { displaySession?.status ?? .idle }
    private var projectName: String? {
        guard let cwd = displaySession?.cwd, !cwd.isEmpty else { return nil }
        return (cwd as NSString).lastPathComponent
    }

    @State private var shownTool: String?
    @State private var shownDesc: String?
    @State private var lingerTimer: Timer?

    /// Extract meaningful part of description — file paths show last component
    private func shortDesc(_ desc: String) -> String {
        let trimmed = desc.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("/") {
            return (trimmed as NSString).lastPathComponent
        }
        return trimmed
    }

    /// Whether the current session is doing any work (not idle)
    private var isWorking: Bool { displayStatus != .idle }

    var body: some View {
        HStack(spacing: 5) {
            // Project name — shown whenever the session is not idle
            if isWorking, let project = projectName {
                Text(project)
                    .foregroundStyle(.white.opacity(0.8))
                    .id("center-project-\(displaySessionId ?? "")")
                    .transition(.opacity)
            }

            // Tool status or thinking indicator
            if let tool = shownTool {
                TypingIndicator(fontSize: 11, label: tool, bright: true, color: toolStatusColor(tool))
                    .id("tool-\(tool)-\(appState.rotatingSessionId ?? "")")
                if let desc = shownDesc {
                    MorphText(
                        text: shortDesc(desc),
                        font: .system(size: 11, weight: .medium, design: .monospaced),
                        color: .white.opacity(0.7)
                    )
                    .truncationMode(.tail)
                }
            } else if displayStatus == .processing {
                TypingIndicator(fontSize: 11, label: "thinking", bright: true)
                    .id("thinking-\(appState.rotatingSessionId ?? "")")
            }
        }
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .lineLimit(1)
        .padding(.leading, 6)
        .animation(.easeInOut(duration: 0.25), value: shownTool)
        .animation(.easeInOut(duration: 0.15), value: shownDesc)
        .animation(.easeInOut(duration: 0.3), value: appState.rotatingSessionId)
        .onChange(of: liveTool) { _, newTool in
            lingerTimer?.invalidate()
            if let newTool {
                shownTool = newTool
                shownDesc = liveDesc
            } else {
                lingerTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                    DispatchQueue.main.async {
                        withAnimation(.easeOut(duration: 0.3)) {
                            shownTool = nil
                            shownDesc = nil
                        }
                    }
                }
            }
        }
        .onChange(of: liveDesc) { _, newDesc in
            if liveTool != nil { shownDesc = newDesc }
        }
        // Session rotation: immediately sync to avoid stale linger from previous session
        .onChange(of: appState.rotatingSessionId) { _, _ in
            lingerTimer?.invalidate()
            withAnimation(.easeInOut(duration: 0.2)) {
                shownTool = liveTool
                shownDesc = liveDesc
            }
        }
    }
}

private struct NotchIconButton: View {
    let icon: String
    var tint: Color = .white
    var tooltip: String? = nil
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(tint.opacity(hovering ? 0.95 : (tint == .white ? 0.55 : 0.8)))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(hovering ? (tint == .white ? 0.08 : 0.14) : 0))
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
        .help(tooltip ?? "")
    }
}

// MARK: - Idle Indicator Bar

private struct IdleIndicatorBar: View {
    let mascotSize: CGFloat
    let compactWingWidth: CGFloat
    let notchW: CGFloat
    let notchHeight: CGFloat
    let hasNotch: Bool
    let hovered: Bool
    @ObservedObject private var l10n = L10n.shared
    @AppStorage(SettingsKey.soundEnabled) private var soundEnabled = SettingsDefaults.soundEnabled

    var body: some View {
        HStack(spacing: 0) {
            // Left: mascot
            HStack(spacing: 6) {
                MascotView(source: "claude", status: .idle, size: mascotSize)
                    .opacity(hovered ? 0.9 : 0.5)
            }
            .padding(.leading, 6)

            Spacer(minLength: hasNotch ? notchW : 0)

            // Right: expanded shows text + buttons, collapsed shows nothing
            if hovered {
                HStack(spacing: 8) {
                    Text("0")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))

                    HStack(spacing: 4) {
                        NotchIconButton(icon: soundEnabled ? "speaker.wave.2" : "speaker.slash", tooltip: soundEnabled ? l10n["mute"] : l10n["enable_sound_tooltip"]) {
                            soundEnabled.toggle()
                        }
                        NotchIconButton(icon: "gearshape", tooltip: l10n["settings"]) {
                            SettingsWindowController.shared.show()
                        }
                        NotchIconButton(icon: "power", tint: Color(red: 1.0, green: 0.4, blue: 0.4), tooltip: l10n["quit"]) {
                            NSApplication.shared.terminate(nil)
                        }
                    }
                }
                .padding(.trailing, 6)
                .transition(.opacity)
            }
        }
        .frame(height: notchHeight)
        .animation(NotchAnimation.micro, value: hovered)
    }
}

// MARK: - Session identity, shared by the approval and question cards
//
// With more than one session queued, "delete this file?" or a yes/no question says nothing
// about which project it belongs to — this used to be entirely absent from ApprovalBar and
// only a small grey line in QuestionBar. Both cards now lead with the same bold identity the
// session list already uses, so answering from memory of "which one asked" isn't required.

// MARK: - Forms: shared pieces
//
// Approvals and questions share one look with the session cards: the system font for
// prose and the monospaced one only for code, buttons in sentence case with the main one
// in white on the right, corners concentric with the tray (10 inside 20), 4 pt spacing.

/// Who is asking, and in what state: the same line as the top of a session card.
private struct FormHeader<Extra: View>: View {
    let session: SessionSnapshot
    let sessionId: String
    let status: String
    @ViewBuilder var extra: () -> Extra

    var body: some View {
        HStack(spacing: 8) {
            if let icon = cliIcon(source: session.source, size: 13) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 13, height: 13)
            }
            SessionIdentityLine(
                session: session,
                sessionId: sessionId,
                projectFontSize: 13.5,
                projectColor: .white,
                sessionFontSize: 9.5,
                sessionColor: .white.opacity(0.43),
                dividerColor: .white.opacity(0.2)
            )
            Spacer(minLength: 8)
            extra()
            Text(status)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(FormStyle.waiting)
                .lineLimit(1)
                .fixedSize()
        }
        .frame(height: 18)
    }
}

private enum FormStyle {
    static let waiting = Color(red: 1.0, green: 0.65, blue: 0.25)
    static let deny = Color(red: 1.0, green: 0.54, blue: 0.54)

    static func title(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.95))
            .lineSpacing(2)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "mais 2 esperando", then a quiet dot before the status.
    static func queue(_ waiting: Int) -> some View {
        HStack(spacing: 8) {
            Text(String(format: L10n.shared["form_queue"], waiting))
                .font(.system(size: 10))
                .tracking(0.2)
                .foregroundStyle(.white.opacity(0.35))
            Text("·").font(.system(size: 10)).foregroundStyle(.white.opacity(0.15))
        }
        .fixedSize()
    }
}

/// Where the code goes: the command, the diff, the path.
private struct CodeBlock<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            content()
        }
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(.white.opacity(0.88))
        .lineSpacing(2)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct FormButton: View {
    enum Kind { case primary, secondary, destructive }
    let label: String
    var kind: Kind = .secondary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11.5, weight: kind == .primary ? .semibold : .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(background))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .black
        case .secondary: return .white.opacity(hovering ? 0.95 : 0.8)
        case .destructive: return FormStyle.deny.opacity(hovering ? 1 : 0.9)
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return .white.opacity(hovering ? 1 : 0.92)
        case .secondary, .destructive: return .white.opacity(hovering ? 0.11 : 0.07)
        }
    }
}

/// A text field in the same shape as the options above it.
private struct FormField: View {
    let placeholder: String
    @Binding var text: String
    var focus: FocusState<Bool>.Binding
    let onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.white)
            .focused(focus)
            .onSubmit(onSubmit)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(focus.wrappedValue ? 0.28 : 0.12), lineWidth: 1)
            )
    }
}

// MARK: - Approval Bar (below notch, auto-expanded)

private struct ApprovalBar: View {
    let tool: String
    let toolInput: [String: Any]?
    /// Which session is asking. With several sessions queued, "what tool" alone doesn't say
    /// "which project".
    let session: SessionSnapshot?
    let sessionId: String
    let queuePosition: Int
    let queueTotal: Int
    let onAllow: () -> Void
    let onAlwaysAllow: () -> Void
    let onDeny: () -> Void

    private var l10n: L10n { L10n.shared }

    private var filePath: String? { toolInput?["file_path"] as? String }
    private var fileName: String? { filePath.map { ($0 as NSString).lastPathComponent } }

    /// "mcp__github__create_issue" → ("create_issue", "github").
    private var mcpParts: (tool: String, server: String)? {
        guard tool.hasPrefix("mcp__") else { return nil }
        let parts = tool.dropFirst("mcp__".count).components(separatedBy: "__")
        guard parts.count >= 2 else { return nil }
        return (parts.dropFirst().joined(separator: "__"), parts[0])
    }

    /// What the agent wants, as a sentence.
    private var title: String {
        let file = fileName ?? ""
        switch tool {
        case "Bash": return l10n["ap_bash"]
        case "Edit", "MultiEdit": return String(format: l10n["ap_edit"], file)
        case "Write": return String(format: l10n["ap_write"], file)
        case "Read": return String(format: l10n["ap_read"], file)
        case "Grep": return l10n["ap_grep"]
        case "Glob": return l10n["ap_glob"]
        default:
            if let mcp = mcpParts { return String(format: l10n["ap_mcp"], mcp.tool, mcp.server) }
            if let server = toolInput?["server_name"] as? String { return String(format: l10n["ap_mcp"], tool, server) }
            return String(format: l10n["ap_tool"], tool)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session {
                FormHeader(session: session, sessionId: sessionId, status: l10n["st_waiting_approval"]) {
                    if queueTotal > 1 { FormStyle.queue(queueTotal - queuePosition) }
                }
            }
            FormStyle.title(title)
            if toolInput != nil {
                CodeBlock { toolDetail }
            }
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                FormButton(label: l10n["form_deny"], kind: .destructive, action: onDeny)
                FormButton(label: l10n["form_always"], action: onAlwaysAllow)
                FormButton(label: l10n["form_allow"], kind: .primary, action: onAllow)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func path(_ p: String) -> some View {
        Text(p)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.white.opacity(0.42))
            .lineLimit(1)
            .truncationMode(.head)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.42))
    }

    /// One diff line, tinted across the whole block width like a code review.
    private func diffLine(_ sign: String, _ text: String, _ color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(sign).opacity(0.6)
            Text(text).lineLimit(3)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12))
        .padding(.horizontal, -12)
    }

    @ViewBuilder
    private var toolDetail: some View {
        switch tool {
        case "Bash":
            if let cmd = toolInput?["command"] as? String {
                (Text("$ ").foregroundColor(.white.opacity(0.35)) + Text(cmd))
                    .lineLimit(4)
            }
        case "Edit", "MultiEdit":
            if let fp = filePath { path(fp) }
            if let old = toolInput?["old_string"] as? String {
                diffLine("−", String(old.prefix(160)), Color(red: 1.0, green: 0.64, blue: 0.64))
            }
            if let new = toolInput?["new_string"] as? String {
                diffLine("+", String(new.prefix(160)), Color(red: 0.57, green: 0.9, blue: 0.67))
            }
        case "Write":
            if let fp = filePath { path(fp) }
            if let content = toolInput?["content"] as? String {
                Text(content.prefix(200))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(4)
                    // The preview fades out instead of stopping mid-line.
                    .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
            }
        case "Read":
            if let fp = filePath {
                Text(fp).lineLimit(1).truncationMode(.head)
            }
            if let offset = toolInput?["offset"] as? Int, let limit = toolInput?["limit"] as? Int {
                note(String(format: l10n["ap_lines"], offset + 1, offset + limit))
            }
        case "Grep", "Glob":
            if let pattern = toolInput?["pattern"] as? String {
                Text(pattern).lineLimit(2)
            }
            if let where_ = toolInput?["path"] as? String {
                note(String(format: l10n["ap_in"], where_))
            }
        default:
            if let input = toolInput {
                ForEach(Array(input.keys.sorted().filter { $0 != "server_name" }.prefix(4)), id: \.self) { key in
                    let val = input[key].map { "\($0)" } ?? ""
                    HStack(alignment: .top, spacing: 10) {
                        Text(key)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.42))
                            .frame(width: 44, alignment: .leading)
                            .lineLimit(1)
                        Text(String(val.prefix(100)))
                            .lineLimit(2)
                    }
                }
            }
        }
    }
}

// MARK: - Question Bar (below notch, auto-expanded)

private struct QuestionBar: View {
    let question: String
    let options: [String]?
    let descriptions: [String]?
    /// All AskUserQuestion items (1-4). Empty for legacy Notification questions.
    let allQuestions: [AskUserQuestionItem]
    let session: SessionSnapshot?
    let sessionId: String
    let queuePosition: Int
    let queueTotal: Int
    let onAnswer: (String) -> Void
    let onAnswerMulti: ([(question: String, answer: String)]) -> Void
    let onSkip: () -> Void

    @State private var textInput = ""
    @FocusState private var isFocused: Bool
    @State private var selectedIndex: Int? = nil

    // Multi-question wizard state
    @State private var currentQuestionIndex: Int = 0
    @State private var collectedAnswers: [(question: String, answer: String)] = []
    @State private var selectedIndices: Set<Int> = []
    @State private var showOtherInput: Bool = false
    @State private var otherText: String = ""
    @FocusState private var otherFocused: Bool

    private var l10n: L10n { L10n.shared }

    private var currentItem: AskUserQuestionItem? {
        guard !allQuestions.isEmpty, currentQuestionIndex < allQuestions.count else { return nil }
        return allQuestions[currentQuestionIndex]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let session {
                FormHeader(session: session, sessionId: sessionId, status: l10n["st_waiting_answer"]) {
                    if allQuestions.count > 1 { steps }
                    if queueTotal > 1 { FormStyle.queue(queueTotal - queuePosition) }
                }
            }

            if let item = currentItem {
                multiQuestionContent(item)
            } else {
                legacyQuestionContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .onAppear { isFocused = true }
    }

    /// Dots and "2 de 3" for a run of questions.
    private var steps: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<allQuestions.count, id: \.self) { i in
                    Circle()
                        .fill(Color.white.opacity(i == currentQuestionIndex ? 0.9 : (i < currentQuestionIndex ? 0.45 : 0.18)))
                        .frame(width: 5, height: 5)
                }
            }
            Text(String(format: l10n["form_step"], currentQuestionIndex + 1, allQuestions.count))
                .font(.system(size: 10).monospacedDigit())
                .tracking(0.2)
                .foregroundStyle(.white.opacity(0.4))
            Text("·").font(.system(size: 10)).foregroundStyle(.white.opacity(0.15))
        }
        .fixedSize()
    }

    // MARK: - Multi-question content (AskUserQuestion)

    @ViewBuilder
    private func multiQuestionContent(_ item: AskUserQuestionItem) -> some View {
        if let header = item.payload.header, !header.isEmpty {
            Text(header)
                .font(.system(size: 10, weight: .medium))
                .tracking(0.2)
                .foregroundStyle(.white.opacity(0.55))
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.white.opacity(0.07)))
        }
        FormStyle.title(item.payload.question)

        if let opts = item.payload.options, !opts.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(opts.enumerated()), id: \.offset) { idx, option in
                    let desc = item.payload.descriptions?.indices.contains(idx) == true ? item.payload.descriptions?[idx] : nil
                    if item.multiSelect {
                        MultiSelectRow(label: option, description: desc, isChecked: selectedIndices.contains(idx)) {
                            if selectedIndices.contains(idx) {
                                selectedIndices.remove(idx)
                            } else {
                                selectedIndices.insert(idx)
                            }
                        }
                    } else {
                        OptionRow(index: idx + 1, label: option, description: desc, isSelected: selectedIndex == idx) {
                            selectedIndex = idx
                            showOtherInput = false
                            advanceWithAnswer(option)
                        }
                    }
                }

                otherOptionRow(isMultiSelect: item.multiSelect)

                if showOtherInput {
                    FormField(placeholder: l10n["form_type_answer"], text: $otherText, focus: $otherFocused) {
                        if !item.multiSelect && !otherText.isEmpty {
                            advanceWithAnswer(otherText)
                        }
                    }
                    .onAppear { otherFocused = true }
                }
            }
        } else {
            FormField(placeholder: l10n["form_type_answer"], text: $textInput, focus: $isFocused) {
                if !textInput.isEmpty { advanceWithAnswer(textInput) }
            }
        }

        HStack(spacing: 6) {
            if currentQuestionIndex > 0 {
                Button(action: goBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .bold))
                        Text(l10n["form_back"]).font(.system(size: 11.5))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            FormButton(label: l10n["form_skip"], action: onSkip)
            if item.multiSelect {
                FormButton(label: l10n["form_confirm"], kind: .primary, action: confirmMultiSelect)
            } else if item.payload.options == nil || item.payload.options?.isEmpty == true {
                FormButton(label: l10n["form_send"], kind: .primary) {
                    if !textInput.isEmpty { advanceWithAnswer(textInput) }
                }
            } else if showOtherInput {
                FormButton(label: l10n["form_send"], kind: .primary) {
                    if !otherText.isEmpty { advanceWithAnswer(otherText) }
                }
            }
        }
        .padding(.top, 2)
    }

    // MARK: - "Other" option row

    @ViewBuilder
    private func otherOptionRow(isMultiSelect: Bool) -> some View {
        if isMultiSelect {
            MultiSelectRow(label: l10n["form_other"], description: nil, isChecked: showOtherInput) {
                showOtherInput.toggle()
                if !showOtherInput { otherText = "" }
            }
        } else {
            OptionRow(index: -1, label: l10n["form_other"], description: nil, isSelected: showOtherInput) {
                showOtherInput = true
                selectedIndex = nil
            }
        }
    }

    // MARK: - Navigation

    private func advanceWithAnswer(_ answer: String) {
        guard let item = currentItem else { return }
        collectedAnswers.append((question: item.payload.question, answer: answer))
        if currentQuestionIndex + 1 < allQuestions.count {
            withAnimation(NotchAnimation.micro) {
                currentQuestionIndex += 1
                resetQuestionState()
            }
        } else {
            onAnswerMulti(collectedAnswers)
        }
    }

    private func confirmMultiSelect() {
        guard let item = currentItem, let opts = item.payload.options else { return }
        var parts: [String] = selectedIndices.sorted().compactMap { idx in
            opts.indices.contains(idx) ? opts[idx] : nil
        }
        if showOtherInput && !otherText.isEmpty {
            parts.append(otherText)
        }
        guard !parts.isEmpty else { return }
        advanceWithAnswer(parts.joined(separator: ", "))
    }

    private func goBack() {
        guard currentQuestionIndex > 0, !collectedAnswers.isEmpty else { return }
        collectedAnswers.removeLast()
        withAnimation(NotchAnimation.micro) {
            currentQuestionIndex -= 1
            resetQuestionState()
        }
    }

    private func resetQuestionState() {
        selectedIndex = nil
        selectedIndices = []
        showOtherInput = false
        otherText = ""
        textInput = ""
    }

    // MARK: - Legacy single-question content (Notification-based)

    @ViewBuilder
    private var legacyQuestionContent: some View {
        FormStyle.title(question)

        if let options = options, !options.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, option in
                    let desc = descriptions?.indices.contains(idx) == true ? descriptions?[idx] : nil
                    OptionRow(index: idx + 1, label: option, description: desc, isSelected: selectedIndex == idx) {
                        selectedIndex = idx
                        onAnswer(option)
                    }
                }
            }
        } else {
            FormField(placeholder: l10n["form_type_answer"], text: $textInput, focus: $isFocused) {
                if !textInput.isEmpty { onAnswer(textInput) }
            }
        }

        HStack(spacing: 6) {
            Spacer(minLength: 0)
            FormButton(label: l10n["form_skip"], action: onSkip)
            if options == nil || options?.isEmpty == true {
                FormButton(label: l10n["form_send"], kind: .primary) {
                    if !textInput.isEmpty { onAnswer(textInput) }
                }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - Option rows

/// One choice. The number is a quiet hint; under the mouse the row lifts and a chevron
/// says a click answers. Index -1 is "something else", with a pencil instead of a number.
private struct OptionRow: View {
    let index: Int
    let label: String
    let description: String?
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    private var lit: Bool { hovering || isSelected }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if index > 0 {
                        Text("\(index)")
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    } else {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .foregroundStyle(.white.opacity(lit ? 0.9 : 0.35))
                .frame(width: 14, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(index > 0 || lit ? 0.92 : 0.6))
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .opacity(hovering && index > 0 ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(lit ? 0.08 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(lit ? 0.14 : 0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }
}

/// A choice that can be ticked along with others: a white box when ticked.
private struct MultiSelectRow: View {
    let label: String
    let description: String?
    let isChecked: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    if isChecked {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white.opacity(0.92))
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.black)
                    } else {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .strokeBorder(Color.white.opacity(hovering ? 0.55 : 0.35), lineWidth: 1.3)
                    }
                }
                .frame(width: 14, height: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                    if let description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(isChecked || hovering ? 0.08 : 0.04)))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(isChecked || hovering ? 0.14 : 0.06), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }
}

// MARK: - Session List

struct SessionListView: View {
    var appState: AppState
    /// When set, only show this session (auto-expand on completion)
    var onlySessionId: String? = nil
    @AppStorage(SettingsKey.sessionGroupingMode) private var groupingMode = SettingsDefaults.sessionGroupingMode
    @AppStorage(SettingsKey.maxVisibleSessions) private var maxVisibleSessions = SettingsDefaults.maxVisibleSessions

    private var groupedSessions: [(header: String, source: String?, ids: [String])] {
        if let only = onlySessionId, appState.sessions[only] != nil {
            return [("", nil, [only])]
        }

        let sorted = appState.sessions.keys.sorted()

        switch groupingMode {
        case "status":
            let l10n = L10n.shared
            let groups: [(Set<AgentStatus>, String)] = [
                ([.running], l10n["status_running"]),
                ([.waitingApproval, .waitingQuestion], l10n["status_waiting"]),
                ([.processing], l10n["status_processing"]),
                ([.idle], l10n["status_idle"]),
            ]
            var result: [(String, String?, [String])] = []
            for (statuses, label) in groups {
                let ids = sorted.filter { id in
                    guard let s = appState.sessions[id] else { return false }
                    return statuses.contains(s.status)
                }
                if !ids.isEmpty {
                    result.append(("\(label) (\(ids.count))", nil, ids))
                }
            }
            return result

        case "cli":
            let cliOrder: [(source: String, name: String)] = [
                ("claude", "Claude"),
                ("codex", "Codex"),
                ("gemini", "Gemini"),
                ("antigravity", "AntiGravity"),
                ("cursor", "Cursor"),
                ("trae", "Trae"),
                ("traecn", "Trae CN"),
                ("copilot", "Copilot"),
                ("qoder", "Qoder"),
                ("droid", "Factory"),
                ("codebuddy", "CodeBuddy"),
                ("codybuddycn", "CodyBuddyCN"),
                ("stepfun", "StepFun"),
                ("workbuddy", "WorkBuddy"),
                ("hermes", "Hermes"),
                ("qwen", "Qwen Code"),
                ("opencode", "OpenCode"),
            ]
            var result: [(String, String?, [String])] = []
            var seen = Set<String>()
            for cli in cliOrder {
                let ids = sorted.filter { id in
                    appState.sessions[id]?.source == cli.source
                }
                ids.forEach { seen.insert($0) }
                if !ids.isEmpty {
                    result.append(("\(cli.name) (\(ids.count))", cli.source, ids))
                }
            }
            let remaining = sorted.filter { !seen.contains($0) }
            if !remaining.isEmpty {
                result.append(("\(L10n.shared["other"]) (\(remaining.count))", nil, remaining))
            }
            return result

        default: // "all"
            return [("", nil, sorted)]
        }
    }

    var body: some View {
        // Compute once per render — groupedSessions, totalCount, needsScroll
        let groups = groupedSessions
        let totalSessionCount = groups.reduce(0) { $0 + $1.ids.count }
        let needsScroll = onlySessionId == nil && totalSessionCount > maxVisibleSessions
        let content = VStack(spacing: 6) {
            ForEach(groups, id: \.header) { group in
                if !group.header.isEmpty {
                    HStack(spacing: 6) {
                        if let src = group.source, let icon = cliIcon(source: src) {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 14, height: 14)
                        }
                        Text(group.header)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
                }

                ForEach(group.ids, id: \.self) { sessionId in
                    if let session = appState.sessions[sessionId] {
                        SessionCard(
                            sessionId: sessionId,
                            session: session,
                            appState: appState,
                            isCompletion: onlySessionId != nil
                        )
                    }
                }
            }

            // "Show all sessions" — hover with delay to expand
            if onlySessionId != nil && appState.sessions.count > 1 {
                SessionsExpandLink(count: appState.sessions.count) {
                    withAnimation(NotchAnimation.open) {
                        appState.surface = .sessionList
                        appState.cancelCompletionQueue()
                    }
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 6)

        if needsScroll {
            ThinScrollView(maxHeight: CGFloat(maxVisibleSessions) * 90) {
                content
            }
            .clipShape(
                UnevenRoundedRectangle(
                    topLeadingRadius: 0, bottomLeadingRadius: 20,
                    bottomTrailingRadius: 20, topTrailingRadius: 0,
                    style: .continuous
                )
            )
        } else {
            content
        }
    }
}

/// Thin overlay scrollbar via NSScrollView — ignores system "show scrollbar" preference.
///
/// Sem Auto Layout de propósito. A versão anterior prendia o topo do documento ao
/// topo da clip view por constraint, e no macOS 27 essa constraint passou a brigar
/// com o scroll: a lista travava no meio, com o primeiro card cortado, sem rolar
/// para cima nem para baixo. Agora a clip view é invertida (origem no topo) e o
/// documento recebe o frame na mão, com a altura medida para a largura atual.
private struct ThinScrollView<Content: View>: NSViewRepresentable {
    let maxHeight: CGFloat
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> ThinNSScrollView {
        let scrollView = ThinNSScrollView()
        scrollView.contentView = FlippedClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.drawsBackground = false
        scrollView.scrollerKnobStyle = .light
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()

        let hosting = NSHostingView(rootView: ThinScrollDocument(content: content))
        hosting.sizingOptions = []
        scrollView.documentView = hosting

        let coordinator = context.coordinator
        scrollView.measureHeight = { [weak coordinator] width in
            coordinator?.contentHeight(forWidth: width) ?? 0
        }
        return scrollView
    }

    func updateNSView(_ scrollView: ThinNSScrollView, context: Context) {
        context.coordinator.update(content)
        if let hosting = scrollView.documentView as? NSHostingView<ThinScrollDocument<Content>> {
            hosting.rootView = ThinScrollDocument(content: content)
        }
        scrollView.scrollerStyle = .overlay
        scrollView.verticalScroller?.controlSize = .mini
        scrollView.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: ThinNSScrollView, context: Context) -> CGSize? {
        context.coordinator.update(content)
        let width = proposal.width ?? scrollView.frame.width
        let contentHeight = context.coordinator.contentHeight(forWidth: width)
        return CGSize(width: width, height: min(contentHeight, maxHeight))
    }

    func makeCoordinator() -> Coordinator { Coordinator(content: content) }

    final class Coordinator {
        private let measurer: NSHostingController<ThinScrollMeasure<Content>>

        init(content: Content) {
            measurer = NSHostingController(rootView: ThinScrollMeasure(content: content))
        }

        func update(_ content: Content) {
            measurer.rootView = ThinScrollMeasure(content: content)
        }

        func contentHeight(forWidth width: CGFloat) -> CGFloat {
            guard width > 0 else { return 0 }
            return ceil(measurer.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        }
    }
}

/// Os cards são flexíveis na vertical: medidos sem `fixedSize` com altura infinita,
/// voltavam altura infinita, e o primeiro card esticava até o fim da lista.
private struct ThinScrollMeasure<Content: View>: View {
    let content: Content

    var body: some View {
        content.fixedSize(horizontal: false, vertical: true)
    }
}

private struct ThinScrollDocument<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class ThinNSScrollView: NSScrollView {
    var measureHeight: ((CGFloat) -> CGFloat)?

    override func layout() {
        super.layout()
        guard let document = documentView, let measureHeight else { return }
        let width = contentView.bounds.width
        let height = max(measureHeight(width), contentView.bounds.height)
        let size = NSSize(width: width, height: height)
        if document.frame.size != size {
            document.frame = NSRect(origin: .zero, size: size)
        }
    }
}

private struct SessionIdentityLine: View {
    let session: SessionSnapshot
    let sessionId: String
    let projectFontSize: CGFloat
    let projectColor: Color
    let sessionFontSize: CGFloat
    let sessionColor: Color
    let dividerColor: Color

    private var displaySessionId: String { session.displaySessionId(sessionId: sessionId) }

    var body: some View {
        HStack(spacing: 4) {
            ProjectNameLink(
                name: session.projectDisplayName,
                cwd: session.cwd,
                isInteractive: !session.isRemote,
                fontSize: projectFontSize,
                color: projectColor
            )
            .layoutPriority(2)

            if let sessionLabel = session.sessionLabel {
                Text("#\(sessionLabel)")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)

                Text("·")
                    .font(.system(size: sessionFontSize, weight: .semibold, design: .monospaced))
                    .foregroundStyle(dividerColor)

                Text("#\(shortSessionId(displaySessionId))")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor.opacity(0.6))
                    .fixedSize()
            } else {
                Text("#\(shortSessionId(displaySessionId))")
                    .font(.system(size: sessionFontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(sessionColor.opacity(0.6))
                    .fixedSize()
            }
        }
    }
}

private struct ProjectNameLink: View {
    let name: String
    let cwd: String?
    let isInteractive: Bool
    let fontSize: CGFloat
    let color: Color

    var body: some View {
        Text(name)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .onTapGesture {
                if isInteractive, let cwd = cwd {
                    NSWorkspace.shared.open(URL(fileURLWithPath: cwd))
                }
            }
            .help(isInteractive && cwd != nil ? "\(L10n.shared["open_path"]) \(cwd ?? "")" : "")
    }
}

private struct SessionsExpandLink: View {
    let count: Int
    let action: () -> Void
    @State private var hovering = false
    @State private var hoverTimer: Timer?

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
                Text("\(count) \(L10n.shared["n_sessions"])")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(hovering ? 0.7 : 0.45))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(hovering ? 0.5 : 0.3))
                Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(NotchAnimation.micro) { hovering = h }
            hoverTimer?.invalidate()
            hoverTimer = nil
            if h {
                hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false) { _ in
                    Task { @MainActor in action() }
                }
            }
        }
    }
}

private struct SessionCard: View {
    let sessionId: String
    let session: SessionSnapshot
    var appState: AppState
    var isCompletion: Bool = false
    @State private var hovering = false
    @ObservedObject private var contextStore = ContextUsageStore.shared
    @ObservedObject private var momentStore = MomentStore.shared
    @AppStorage(SettingsKey.cardClickAction) private var cardClickAction = SettingsDefaults.cardClickAction

    private func openChat() {
        withAnimation(NotchAnimation.open) {
            appState.surface = .sessionChat(sessionId: sessionId)
        }
    }

    /// Brings up the exact terminal tab or IDE window for the session; for a desktop app
    /// (Claude, Codex) only the app itself, which offers no way to pick the conversation.
    private func openApp() {
        TerminalActivator.activate(session: session, sessionId: sessionId)
        appState.collapsePanel()
    }
    @AppStorage(SettingsKey.contentFontSize) private var contentFontSize = SettingsDefaults.contentFontSize
    @AppStorage(SettingsKey.aiMessageLines) private var aiMessageLines = SettingsDefaults.aiMessageLines
    @AppStorage(SettingsKey.showAgentDetails) private var showAgentDetails = SettingsDefaults.showAgentDetails
    private var fontSize: CGFloat { CGFloat(contentFontSize) }
    private var aiLineLimit: Int? { aiMessageLines > 0 ? aiMessageLines : nil }
    private var statusNameColor: Color {
        if session.status == .idle && session.interrupted {
            return Color(red: 1.0, green: 0.45, blue: 0.35)
        }
        switch session.status {
        case .processing, .running:              return Color(red: 0.3, green: 0.85, blue: 0.4)
        case .waitingApproval, .waitingQuestion:  return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .idle:                               return .white
        }
    }

    // ── Status semantics ────────────────────────────────────────────
    private var statusAccent: Color {
        if session.status == .idle && session.interrupted {
            return Color(red: 1.0, green: 0.45, blue: 0.35)
        }
        switch session.status {
        case .processing, .running:               return Color(red: 0.36, green: 0.85, blue: 0.50)
        case .waitingApproval, .waitingQuestion:  return Color(red: 1.0,  green: 0.65, blue: 0.25)
        case .idle:                               return Color.white.opacity(0.35)
        }
    }
    private var statusLabel: String {
        let l10n = L10n.shared
        if session.status == .idle && session.interrupted { return l10n["st_interrupted"] }
        switch session.status {
        case .processing, .running:               return l10n["st_working"]
        case .waitingApproval:                    return l10n["st_waiting_approval"]
        case .waitingQuestion:                    return l10n["st_waiting_answer"]
        case .idle:                               return l10n["st_idle"]
        }
    }

    var body: some View {
        Button {
            // A click does what Settings says (the session's app or terminal, by default);
            // ⌘-click does the other one, and the small button on the card does too.
            let wantsChat = (cardClickAction == "chat") != NSEvent.modifierFlags.contains(.command)
            if wantsChat { openChat() } else { openApp() }
        } label: {
            cardContent
        } // end Button label
        .buttonStyle(CardPressStyle())
        .contentShape(Rectangle())
        .onHover { h in withAnimation(NotchAnimation.micro) { hovering = h } }
    }

    @ViewBuilder
    private var cardContent: some View {
        // No coloured stripe down the side and no status-tinted border: the agent dot and
        // the status text already say it. Corners are concentric with the tray (20 minus
        // the 6 pt margin), and every gap sits on the 4 pt grid.
        HStack(alignment: .top, spacing: 0) {
            mascotColumn
            contentColumn
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.06 : 0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(hovering ? 0.11 : 0.06), lineWidth: 1)
        )
        // A 1 pt catch of light along the top edge.
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.05), .clear], startPoint: .top, endPoint: .center),
                    lineWidth: 1
                )
                .allowsHitTesting(false)
        )
        .padding(.horizontal, 6)
    }

    private var isIdle: Bool { session.status == .idle }
    private var isWorking: Bool { session.status == .processing || session.status == .running }

    /// The agent's colour, where each card used to carry its own mascot. Hatch is one
    /// character now, at the head of the panel, speaking for every session.
    @ViewBuilder
    private var mascotColumn: some View {
        VStack(spacing: 6) {
            AgentDot(source: session.source, status: session.status, size: 8)
                .background(
                    // A quiet ring around the dot of a session that is working.
                    Circle()
                        .stroke(Color(nsColor: HatchlingMascotView.eyeColor(for: session.source)).opacity(isWorking ? 0.22 : 0), lineWidth: 3)
                        .frame(width: 11, height: 11)
                )
                .padding(.top, 5)
            if showAgentDetails && !session.subagents.isEmpty {
                subagentGrid
            }
        }
        .frame(width: showAgentDetails && !session.subagents.isEmpty ? 36 : 28)
        .padding(.top, 12)
    }

    @ViewBuilder
    private var subagentGrid: some View {
        let sorted = session.subagents.values.sorted { $0.startTime < $1.startTime }
        let rows = stride(from: 0, to: sorted.count, by: 4).map {
            Array(sorted[$0..<min($0 + 4, sorted.count)])
        }
        VStack(spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.agentId) { sub in
                        MiniAgentIcon(active: sub.status != .idle, size: 7)
                    }
                }
            }
        }
    }

    // ── Content column ──────────────────────────────────────────────
    @ViewBuilder
    private var contentColumn: some View {
        let _ = momentStore.objectWillChange
        let moment = momentStore.moment(for: session, sessionId: sessionId)
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .frame(height: 18)
            contextRow
                .padding(.top, 4)
            Text(moment.now)
                .font(.system(size: fontSize + 1, weight: .medium))
                .foregroundStyle(.white.opacity(isIdle ? 0.72 : 0.94))
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
                .animation(.easeOut(duration: 0.25), value: moment.now)
                .padding(.top, 8)
            footerRow(task: moment.task != moment.now ? moment.task : nil)
                .padding(.top, 4)
        }
        .padding(.trailing, 16)
        .padding(.vertical, 12)
    }

    /// Model + tokens-used / context-window. Hidden when we can't read it. The token count
    /// only shows under the mouse; at rest the percentage says enough.
    @ViewBuilder
    private var contextRow: some View {
        // Touch the published property so SwiftUI re-renders on cache updates
        let _ = contextStore.objectWillChange
        if let usage = ContextUsageStore.shared.lookup(for: session, sessionId: sessionId) {
            HStack(spacing: 8) {
                Text(usage.modelShort)
                    .font(.system(size: fontSize - 1.5, weight: .medium, design: .monospaced))
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
                ContextProgressTrack(pct: usage.pct, color: usage.color)
                    .frame(width: 60, height: 3)
                Text("\(usage.pct)%")
                    .font(.system(size: fontSize - 1.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(usage.color.opacity(0.92))
                    .monospacedDigit()
                Text(usage.tokensCompact)
                    .font(.system(size: fontSize - 2, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.26))
                    .opacity(hovering ? 1 : 0)
                Spacer(minLength: 0)
            }
            .frame(height: 12)
        }
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 8) {
            SessionIdentityLine(
                session: session,
                sessionId: sessionId,
                projectFontSize: fontSize + 2.5,
                projectColor: .white.opacity(isIdle ? 0.82 : 1),
                sessionFontSize: fontSize - 1.5,
                sessionColor: .white.opacity(0.43),
                dividerColor: .white.opacity(0.2)
            )
            if let remote = session.remoteDisplayName {
                SessionTag("@\(remote)", color: Color(red: 0.45, green: 0.72, blue: 1.0))
            }
            if session.isYoloMode == true {
                SessionTag("YOLO", color: Color(red: 1.0, green: 0.35, blue: 0.35))
            }
            Spacer(minLength: 8)
            statusPill
        }
    }

    // ── Status (top-right of header) ────────────────────────────────
    @ViewBuilder
    private var statusPill: some View {
        Text(statusLabel)
            .font(.system(size: fontSize - 1, weight: .medium))
            .tracking(0.2)
            .foregroundStyle(isIdle && !session.interrupted ? Color.white.opacity(0.36) : statusAccent)
            .lineLimit(1)
            .fixedSize()
    }

    // ── Footer: what the session is about, then the way in, how long ago, which app ──
    @ViewBuilder
    private func footerRow(task: String?) -> some View {
        HStack(spacing: 8) {
            Text(task ?? "")
                .font(.system(size: fontSize - 0.5))
                .tracking(0.1)
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            // The other way in, one click away: the chat when a click opens the app, and the
            // app when a click opens the chat. Only under the mouse, so a resting card is calm.
            let alternateIsChat = cardClickAction != "chat"
            Button(action: alternateIsChat ? openChat : openApp) {
                Image(systemName: alternateIsChat ? "text.bubble" : "macwindow")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 22, height: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .help(L10n.shared[alternateIsChat ? "card_open_chat" : "card_open_app"])
            Text(timeAgo(session.startTime))
                .font(.system(size: fontSize - 1.5, weight: .medium).monospacedDigit())
                .tracking(0.2)
                .foregroundStyle(.white.opacity(0.32))
            TerminalBadge(session: session)
                .opacity(isIdle ? 0.6 : 1)
        }
        .frame(height: 18)
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "<1m" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}

/// Cards give a little under the click, so a press reads as a press before the chat opens.
private struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Claude Logo (official sunburst from simple-icons, viewBox 0 0 24 24)

private struct ClaudeLogo: View {
    var size: CGFloat = 22
    private static let color = Color(red: 0.85, green: 0.47, blue: 0.34) // #D97757

    // Official Claude logo SVG path (source: simple-icons)
    fileprivate static let svgPath = "m4.7144 15.9555 4.7174-2.6471.079-.2307-.079-.1275h-.2307l-.7893-.0486-2.6956-.0729-2.3375-.0971-2.2646-.1214-.5707-.1215-.5343-.7042.0546-.3522.4797-.3218.686.0608 1.5179.1032 2.2767.1578 1.6514.0972 2.4468.255h.3886l.0546-.1579-.1336-.0971-.1032-.0972L6.973 9.8356l-2.55-1.6879-1.3356-.9714-.7225-.4918-.3643-.4614-.1578-1.0078.6557-.7225.8803.0607.2246.0607.8925.686 1.9064 1.4754 2.4893 1.8336.3643.3035.1457-.1032.0182-.0728-.164-.2733-1.3539-2.4467-1.445-2.4893-.6435-1.032-.17-.6194c-.0607-.255-.1032-.4674-.1032-.7285L6.287.1335 6.6997 0l.9957.1336.419.3642.6192 1.4147 1.0018 2.2282 1.5543 3.0296.4553.8985.2429.8318.091.255h.1579v-.1457l.1275-1.706.2368-2.0947.2307-2.6957.0789-.7589.3764-.9107.7468-.4918.5828.2793.4797.686-.0668.4433-.2853 1.8517-.5586 2.9021-.3643 1.9429h.2125l.2429-.2429.9835-1.3053 1.6514-2.0643.7286-.8196.85-.9046.5464-.4311h1.0321l.759 1.1293-.34 1.1657-1.0625 1.3478-.8804 1.1414-1.2628 1.7-.7893 1.36.0729.1093.1882-.0183 2.8535-.607 1.5421-.2794 1.8396-.3157.8318.3886.091.3946-.3278.8075-1.967.4857-2.3072.4614-3.4364.8136-.0425.0304.0486.0607 1.5482.1457.6618.0364h1.621l3.0175.2247.7892.522.4736.6376-.079.4857-1.2142.6193-1.6393-.3886-3.825-.9107-1.3113-.3279h-.1822v.1093l1.0929 1.0686 2.0035 1.8092 2.5075 2.3314.1275.5768-.3218.4554-.34-.0486-2.2039-1.6575-.85-.7468-1.9246-1.621h-.1275v.17l.4432.6496 2.3436 3.5214.1214 1.0807-.17.3521-.6071.2125-.6679-.1214-1.3721-1.9246L14.38 17.959l-1.1414-1.9428-.1397.079-.674 7.2552-.3156.3703-.7286.2793-.6071-.4614-.3218-.7468.3218-1.4753.3886-1.9246.3157-1.53.2853-1.9004.17-.6314-.0121-.0425-.1397.0182-1.4328 1.9672-2.1796 2.9446-1.7243 1.8456-.4128.164-.7164-.3704.0667-.6618.4008-.5889 2.386-3.0357 1.4389-1.882.929-1.0868-.0062-.1579h-.0546l-6.3385 4.1164-1.1293.1457-.4857-.4554.0608-.7467.2307-.2429 1.9064-1.3114Z"

    var body: some View {
        ClaudeLogoShape()
            .fill(Self.color)
            .frame(width: size, height: size)
    }
}

private struct ClaudeLogoShape: Shape {
    private static let basePath: Path = ClaudeLogoShape.parseSVGPath(ClaudeLogo.svgPath)

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24.0
        let transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY))
        return Self.basePath.applying(transform)
    }

    // Minimal SVG path parser for m/l/h/v/c/z commands
    private static func parseSVGPath(_ d: String) -> Path {
        var path = Path()
        var x: CGFloat = 0, y: CGFloat = 0
        var i = d.startIndex
        var cmd: Character = "m"

        func skipWS() {
            while i < d.endIndex && (d[i] == " " || d[i] == ",") { i = d.index(after: i) }
        }

        func peekNum() -> Bool {
            guard i < d.endIndex else { return false }
            let c = d[i]
            return c == "-" || c == "." || c.isNumber
        }

        func num() -> CGFloat {
            skipWS()
            var s = ""
            if i < d.endIndex && d[i] == "-" { s.append(d[i]); i = d.index(after: i) }
            var hasDot = false
            while i < d.endIndex {
                let c = d[i]
                if c == "." {
                    if hasDot { break }
                    hasDot = true; s.append(c); i = d.index(after: i)
                } else if c.isNumber {
                    s.append(c); i = d.index(after: i)
                } else { break }
            }
            return CGFloat(Double(s) ?? 0)
        }

        while i < d.endIndex {
            skipWS()
            guard i < d.endIndex else { break }
            let c = d[i]
            if c.isLetter {
                cmd = c; i = d.index(after: i)
            }

            switch cmd {
            case "m":
                let dx = num(), dy = num(); x += dx; y += dy
                path.move(to: CGPoint(x: x, y: y))
                cmd = "l" // subsequent coords are implicit lineTo
            case "M":
                x = num(); y = num()
                path.move(to: CGPoint(x: x, y: y))
                cmd = "L"
            case "l":
                let dx = num(), dy = num(); x += dx; y += dy
                path.addLine(to: CGPoint(x: x, y: y))
            case "L":
                x = num(); y = num()
                path.addLine(to: CGPoint(x: x, y: y))
            case "h":
                x += num(); path.addLine(to: CGPoint(x: x, y: y))
            case "H":
                x = num(); path.addLine(to: CGPoint(x: x, y: y))
            case "v":
                y += num(); path.addLine(to: CGPoint(x: x, y: y))
            case "V":
                y = num(); path.addLine(to: CGPoint(x: x, y: y))
            case "c":
                let dx1 = num(), dy1 = num(), dx2 = num(), dy2 = num(), dx = num(), dy = num()
                path.addCurve(to: CGPoint(x: x+dx, y: y+dy),
                              control1: CGPoint(x: x+dx1, y: y+dy1),
                              control2: CGPoint(x: x+dx2, y: y+dy2))
                x += dx; y += dy
            case "C":
                let x1 = num(), y1 = num(), x2 = num(), y2 = num()
                x = num(); y = num()
                path.addCurve(to: CGPoint(x: x, y: y),
                              control1: CGPoint(x: x1, y: y1),
                              control2: CGPoint(x: x2, y: y2))
            case "Z", "z":
                path.closeSubpath()
            default:
                i = d.index(after: i)
            }

            // Handle repeated implicit commands
            skipWS()
            if i < d.endIndex && peekNum() && "mlhvcMLHVC".contains(cmd) {
                continue
            }
        }
        return path
    }
}

// MARK: - Notch Panel Shape (inverse radius at top, regular radius at bottom)

private struct NotchPanelShape: Shape {
    var topExtension: CGFloat
    var bottomRadius: CGFloat
    /// Fixed minimum height — NOT animated, prevents spring overshoot from exposing the notch
    var minHeight: CGFloat = 0

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topExtension, bottomRadius) }
        set {
            topExtension = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let ext = topExtension
        let maxY = max(rect.maxY, rect.minY + minHeight)
        let br = min(bottomRadius, rect.width / 4, (maxY - rect.minY) / 2)
        // Smoothness factor for continuous-curvature corners (superellipse approximation).
        // 0.5523 = perfect circle; higher values tighten the curve for an Apple squircle feel.
        let k: CGFloat = 0.62

        var p = Path()
        // Top edge (extends into notch area via wings)
        p.move(to: CGPoint(x: rect.minX - ext, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX + ext, y: rect.minY))
        // Right shoulder: cubic bezier tangent to top line (horizontal) and right side (vertical)
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + ext),
            control1: CGPoint(x: rect.maxX + ext * 0.35, y: rect.minY),
            control2: CGPoint(x: rect.maxX, y: rect.minY + ext * 0.35)
        )
        // Right side down to bottom-right corner
        p.addLine(to: CGPoint(x: rect.maxX, y: maxY - br))
        // Bottom-right: cubic bezier for continuous-curvature corner
        p.addCurve(
            to: CGPoint(x: rect.maxX - br, y: maxY),
            control1: CGPoint(x: rect.maxX, y: maxY - br * (1 - k)),
            control2: CGPoint(x: rect.maxX - br * (1 - k), y: maxY)
        )
        // Bottom edge
        p.addLine(to: CGPoint(x: rect.minX + br, y: maxY))
        // Bottom-left: cubic bezier for continuous-curvature corner
        p.addCurve(
            to: CGPoint(x: rect.minX, y: maxY - br),
            control1: CGPoint(x: rect.minX + br * (1 - k), y: maxY),
            control2: CGPoint(x: rect.minX, y: maxY - br * (1 - k))
        )
        // Left side up to shoulder
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + ext))
        // Left shoulder: cubic bezier tangent to left side (vertical) and top line (horizontal)
        p.addCurve(
            to: CGPoint(x: rect.minX - ext, y: rect.minY),
            control1: CGPoint(x: rect.minX, y: rect.minY + ext * 0.35),
            control2: CGPoint(x: rect.minX - ext * 0.35, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}

/// Terminal icon + name badge (display only, not a button)
private struct TerminalBadge: View {
    let session: SessionSnapshot

    private static let sourceBundleIds: [String: String] = [
        "cursor": "com.todesktop.230313mzl4w4u92",
        "trae": "com.trae.app",
        "traecn": "com.trae.app",
        "qoder": "com.qoder.ide",
        "droid": "com.factory.app",
        "codebuddy": "com.tencent.codebuddy",
        "codybuddycn": "com.tencent.codebuddy.cn",
        "stepfun": "com.stepfun.app",
        "codex": "com.openai.codex",
        "opencode": "ai.opencode.desktop",
    ]
    private static var termIconCache: [String: NSImage] = [:]

    private var termIcon: NSImage? {
        let bid = session.termBundleId ?? Self.sourceBundleIds[session.source]
        guard let bid else { return nil }
        if let cached = Self.termIconCache[bid] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.termIconCache[bid] = icon
        return icon
    }

    private let remoteColor = Color(red: 0.3, green: 0.75, blue: 0.5)

    var body: some View {
        Group {
            if session.isRemote {
                HStack(spacing: 4) {
                    Image(systemName: "network")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(remoteColor)
                    if let term = session.terminalName {
                        Text(term)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(remoteColor)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(remoteColor.opacity(0.08))
                )
            } else {
                HStack(spacing: 3) {
                    if let icon = termIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 13, height: 13)
                    }
                    if let term = session.terminalName {
                        Text(term)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
    }
}

/// Collapsed single-line row for idle sessions >15 min
// MARK: - Pixel Text (5×7 dot matrix style)

struct PixelText: View {
    let text: String
    let color: Color
    var pixelSize: CGFloat = 2

    private static let W = 5  // glyph width
    private static let H = 7  // glyph height

    // 5×7 bitmaps — each row is 5 bits, 7 rows per glyph
    private static let glyphs: [Character: [UInt8]] = [
        "0": [0,1,1,1,0, 1,0,0,1,1, 1,0,1,0,1, 1,1,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "1": [0,0,1,0,0, 0,1,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "2": [0,1,1,1,0, 1,0,0,0,1, 0,0,1,1,0, 0,1,0,0,0, 1,1,1,1,1, 0,0,0,0,0, 0,0,0,0,0],
        "3": [0,1,1,1,0, 1,0,0,0,1, 0,0,1,1,0, 1,0,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "4": [0,0,0,1,0, 0,0,1,1,0, 0,1,0,1,0, 1,1,1,1,1, 0,0,0,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "5": [1,1,1,1,1, 1,0,0,0,0, 1,1,1,1,0, 0,0,0,0,1, 1,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "6": [0,1,1,1,0, 1,0,0,0,0, 1,1,1,1,0, 1,0,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "7": [1,1,1,1,1, 0,0,0,0,1, 0,0,0,1,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,0,0,0, 0,0,0,0,0],
        "8": [0,1,1,1,0, 1,0,0,0,1, 0,1,1,1,0, 1,0,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "9": [0,1,1,1,0, 1,0,0,0,1, 0,1,1,1,1, 0,0,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "A": [0,0,1,0,0, 0,1,0,1,0, 1,0,0,0,1, 1,1,1,1,1, 1,0,0,0,1, 0,0,0,0,0, 0,0,0,0,0],
        "B": [1,1,1,1,0, 1,0,0,0,1, 1,1,1,1,0, 1,0,0,0,1, 1,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "C": [0,1,1,1,0, 1,0,0,0,1, 1,0,0,0,0, 1,0,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "D": [1,1,1,1,0, 1,0,0,0,1, 1,0,0,0,1, 1,0,0,0,1, 1,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "E": [1,1,1,1,1, 1,0,0,0,0, 1,1,1,1,0, 1,0,0,0,0, 1,1,1,1,1, 0,0,0,0,0, 0,0,0,0,0],
        "F": [1,1,1,1,1, 1,0,0,0,0, 1,1,1,1,0, 1,0,0,0,0, 1,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0],
        "G": [0,1,1,1,0, 1,0,0,0,0, 1,0,0,1,1, 1,0,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "H": [1,0,0,0,1, 1,0,0,0,1, 1,1,1,1,1, 1,0,0,0,1, 1,0,0,0,1, 0,0,0,0,0, 0,0,0,0,0],
        "I": [0,1,1,1,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "K": [1,0,0,1,0, 1,0,1,0,0, 1,1,0,0,0, 1,0,1,0,0, 1,0,0,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "L": [1,0,0,0,0, 1,0,0,0,0, 1,0,0,0,0, 1,0,0,0,0, 1,1,1,1,1, 0,0,0,0,0, 0,0,0,0,0],
        "N": [1,0,0,0,1, 1,1,0,0,1, 1,0,1,0,1, 1,0,0,1,1, 1,0,0,0,1, 0,0,0,0,0, 0,0,0,0,0],
        "O": [0,1,1,1,0, 1,0,0,0,1, 1,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "P": [1,1,1,1,0, 1,0,0,0,1, 1,1,1,1,0, 1,0,0,0,0, 1,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0],
        "R": [1,1,1,1,0, 1,0,0,0,1, 1,1,1,1,0, 1,0,0,1,0, 1,0,0,0,1, 0,0,0,0,0, 0,0,0,0,0],
        "S": [0,1,1,1,1, 1,0,0,0,0, 0,1,1,1,0, 0,0,0,0,1, 1,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "T": [1,1,1,1,1, 0,0,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,1,0,0, 0,0,0,0,0, 0,0,0,0,0],
        "U": [1,0,0,0,1, 1,0,0,0,1, 1,0,0,0,1, 1,0,0,0,1, 0,1,1,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "W": [1,0,0,0,1, 1,0,0,0,1, 1,0,1,0,1, 1,0,1,0,1, 0,1,0,1,0, 0,0,0,0,0, 0,0,0,0,0],
        "X": [1,0,0,0,1, 0,1,0,1,0, 0,0,1,0,0, 0,1,0,1,0, 1,0,0,0,1, 0,0,0,0,0, 0,0,0,0,0],
        "/": [0,0,0,0,1, 0,0,0,1,0, 0,0,1,0,0, 0,1,0,0,0, 1,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0],
        "-": [0,0,0,0,0, 0,0,0,0,0, 1,1,1,1,1, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0],
        " ": [0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0, 0,0,0,0,0],
    ]

    var body: some View {
        let chars = Array(text.uppercased())
        let px = pixelSize
        let gap: CGFloat = px

        Canvas { ctx, size in
            var xOff: CGFloat = 0
            for ch in chars {
                guard let glyph = Self.glyphs[ch] else {
                    xOff += 3 * px
                    continue
                }
                for row in 0..<Self.H {
                    for col in 0..<Self.W {
                        if glyph[row * Self.W + col] == 1 {
                            let rect = CGRect(x: xOff + CGFloat(col) * px, y: CGFloat(row) * px, width: px, height: px)
                            ctx.fill(Path(rect), with: .color(color))
                        }
                    }
                }
                xOff += CGFloat(Self.W) * px + gap
            }
        }
        .frame(width: charWidth(chars.count), height: CGFloat(Self.H) * pixelSize)
    }

    private func charWidth(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let px = pixelSize
        return CGFloat(count) * (CGFloat(Self.W) * px + px) - px
    }
}

private struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return p
    }
}

// MARK: - Shared Helpers

private let cliIconFiles: [String: String] = [
    "claude": "claude",
    "codex": "codex",
    "gemini": "gemini",
    "antigravity": "antigravity",
    "cursor": "cursor",
    "trae": "trae",
    "traecn": "trae",
    "copilot": "copilot",
    "qoder": "qoder",
    "droid": "factory",
    "codebuddy": "codebuddy",
    "codybuddycn": "codebuddy",
    "stepfun": "stepfun",
    "workbuddy": "workbuddy",
    "hermes": "hermes",
    "qwen": "qwen",
    "opencode": "opencode",
]

private var cliIconCache: [String: NSImage] = [:]

func cliIcon(source: String, size: CGFloat = 16) -> NSImage? {
    let key = "\(source)_\(Int(size))"
    if let cached = cliIconCache[key] { return cached }
    guard let filename = cliIconFiles[source],
          let url = Bundle.appModule.url(forResource: filename, withExtension: "png", subdirectory: "Resources/cli-icons"),
          let image = NSImage(contentsOf: url)
    else { return nil }
    image.size = NSSize(width: size, height: size)
    cliIconCache[key] = image
    return image
}

private struct SessionTag: View {
    let text: String
    var color: Color = .white.opacity(0.7)

    init(_ text: String, color: Color = .white.opacity(0.7)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(color.opacity(0.12))
            )
    }
}

// MARK: - Typing Indicator (three bouncing dots)

private struct TypingIndicator: View {
    let fontSize: CGFloat
    var label: String? = nil
    var bright: Bool = false
    var color: Color? = nil

    var body: some View {
        if let label {
            let baseColor: Color = color ?? .white
            let baseOpacity: Double = bright ? 0.6 : 0.35
            let peakOpacity: Double = bright ? 0.8 : 0.5
            let midOpacity: Double = bright ? 0.5 : 0.3
            let bandWidth: CGFloat = bright ? 80 : 60
            let duration: Double = 2.5
            let endPhase: CGFloat = bright ? 100 : 80
            let startPhase: CGFloat = bright ? -80 : -60

            Text(label)
                .font(.system(size: fontSize, design: .monospaced))
                .foregroundStyle(baseColor.opacity(baseOpacity))
                .overlay(
                    ShimmerSweep(
                        label: label,
                        fontSize: fontSize,
                        bandWidth: bandWidth,
                        duration: duration,
                        startPhase: startPhase,
                        endPhase: endPhase,
                        midOpacity: midOpacity,
                        peakOpacity: peakOpacity,
                        edgeInset: bright ? 0.35 : 0.4
                    )
                    .allowsHitTesting(false)
                )
        }
    }
}

/// The band of light that sweeps across the status label.
///
/// This used to be a SwiftUI `LinearGradient` whose offset was driven by
/// `withAnimation(.repeatForever)`. Any SwiftUI animation interpolating on the
/// main thread pins the window in continuous-layout mode — a full layout pass
/// on every display refresh — and this one runs for as long as an agent is
/// working, which is most of the time. It cost ~4.3% CPU on its own, enough to
/// cancel out every other saving in the panel.
///
/// Handing the same motion to Core Animation moves it to the window server:
/// the layer's position is interpolated out of process and this app is never
/// woken for a frame. Measured at 0.02%, indistinguishable from a static view.
private struct ShimmerSweep: NSViewRepresentable {
    let label: String
    let fontSize: CGFloat
    let bandWidth: CGFloat
    let duration: Double
    let startPhase: CGFloat
    let endPhase: CGFloat
    let midOpacity: Double
    let peakOpacity: Double
    let edgeInset: Double

    final class SweepView: NSView {
        let band = CAGradientLayer()
        let textMask = CATextLayer()
        var bandWidth: CGFloat = 60
        var startPhase: CGFloat = -60
        var endPhase: CGFloat = 80
        var duration: Double = 2.5

        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            band.bounds = CGRect(x: 0, y: 0, width: bandWidth, height: bounds.height)
            textMask.frame = bounds
            layer?.mask = textMask
            CATransaction.commit()
            restartSweep()
        }

        func restartSweep() {
            band.removeAnimation(forKey: "sweep")
            let midY = bounds.height / 2
            band.position = CGPoint(x: startPhase + bandWidth / 2, y: midY)
            let sweep = CABasicAnimation(keyPath: "position.x")
            sweep.fromValue = startPhase + bandWidth / 2
            sweep.toValue = endPhase + bandWidth / 2
            sweep.duration = duration
            sweep.repeatCount = .infinity
            sweep.isRemovedOnCompletion = false
            sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            band.add(sweep, forKey: "sweep")
        }
    }

    func makeNSView(context: Context) -> SweepView {
        let view = SweepView()
        view.wantsLayer = true
        view.layer = CALayer()

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        view.band.startPoint = CGPoint(x: 0, y: 0.5)
        view.band.endPoint = CGPoint(x: 1, y: 0.5)
        view.band.contentsScale = scale
        view.layer?.addSublayer(view.band)

        view.textMask.contentsScale = scale
        view.textMask.alignmentMode = .center
        view.textMask.truncationMode = .end
        view.textMask.foregroundColor = NSColor.white.cgColor

        apply(to: view)
        return view
    }

    func updateNSView(_ view: SweepView, context: Context) {
        apply(to: view)
        view.needsLayout = true
    }

    private func apply(to view: SweepView) {
        view.bandWidth = bandWidth
        view.startPhase = startPhase
        view.endPhase = endPhase
        view.duration = duration

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        view.band.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(midOpacity).cgColor,
            NSColor.white.withAlphaComponent(peakOpacity).cgColor,
            NSColor.white.withAlphaComponent(midOpacity).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor,
        ]
        view.band.locations = [0, NSNumber(value: edgeInset), 0.5,
                               NSNumber(value: 1 - edgeInset), 1]
        view.textMask.string = label
        view.textMask.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        view.textMask.fontSize = fontSize
        CATransaction.commit()
    }
}

// MARK: - Mini Agent Icon (8-bit robot head)

struct MiniAgentIcon: View {
    let active: Bool
    var size: CGFloat = 12

    // 0=empty, 1=body, 2=eye, 3=antenna tip, 4=highlight, 5=shadow
    private let grid: [[Int]] = [
        [0, 0, 0, 3, 0, 0, 0],  // antenna tip (glows)
        [0, 0, 0, 1, 0, 0, 0],  // antenna stem
        [0, 4, 1, 1, 1, 5, 0],  // head top
        [0, 1, 2, 1, 2, 1, 0],  // eyes
        [0, 1, 1, 1, 1, 1, 0],  // face
        [0, 5, 1, 0, 1, 5, 0],  // mouth
        [0, 0, 1, 0, 1, 0, 0],  // legs
    ]

    var body: some View {
        let base = active ? Color.green : Color.gray
        let bright = active ? Color(red: 0.5, green: 1.0, blue: 0.5) : Color(white: 0.7)
        let dark = active ? Color(red: 0.1, green: 0.5, blue: 0.15) : Color(white: 0.35)
        let eye = active ? Color.white : Color(white: 0.85)
        let glow = active ? Color(red: 0.4, green: 1.0, blue: 0.4) : Color(white: 0.6)

        Canvas { ctx, sz in
            let px = sz.width / 7
            for row in 0..<7 {
                for col in 0..<7 {
                    let v = grid[row][col]
                    guard v != 0 else { continue }
                    let color: Color = switch v {
                    case 2: eye
                    case 3: glow
                    case 4: bright
                    case 5: dark
                    default: base
                    }
                    ctx.fill(
                        Path(CGRect(x: CGFloat(col) * px, y: CGFloat(row) * px, width: px, height: px)),
                        with: .color(color)
                    )
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: active ? .green.opacity(0.4) : .clear, radius: 2)
    }
}

// MARK: - Shared Helpers

/// Inline markdown rendering (bold, italic, code, links)
private var markdownCache: [String: AttributedString] = [:]
private let markdownCacheLimit = 128

private func inlineMarkdown(_ text: String) -> AttributedString {
    if let cached = markdownCache[text] { return cached }
    let result: AttributedString
    if let attr = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
        result = attr
    } else {
        result = AttributedString(text)
    }
    if markdownCache.count >= markdownCacheLimit {
        markdownCache.removeAll(keepingCapacity: true)
    }
    markdownCache[text] = result
    return result
}

/// Generate a short session ID with better disambiguation.
private func shortSessionId(_ id: String) -> String {
    let clean = id.replacingOccurrences(of: "-", with: "")
    if clean.count >= 8 {
        return String(clean.suffix(4))
    }
    return String(id.prefix(4))
}

/// Strip internal directives (::code-comment{}, ::git-*{}, etc.) from message text
/// so they don't leak into the UI preview.
// MARK: - Chat Message Row (extracted for render-skip optimization)

/// Separate view so SwiftUI skips body re-evaluation when only the parent's
/// hover state changes — avoids expensive text processing on every hover.
private struct ChatMessageRow: View, Equatable {
    let text: String
    let isUser: Bool
    let fontSize: CGFloat
    let aiLineLimit: Int?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.text == rhs.text && lhs.isUser == rhs.isUser
        && lhs.fontSize == rhs.fontSize && lhs.aiLineLimit == rhs.aiLineLimit
    }

    var body: some View {
        if isUser {
            HStack(alignment: .top, spacing: 4) {
                Text(">")
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.3, green: 0.85, blue: 0.4))
                Text(ChatMessageTextFormatter.literalText(text))
                    .font(.system(size: fontSize, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        } else {
            HStack(alignment: .top, spacing: 4) {
                Text("$")
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                Text(ChatMessageTextFormatter.inlineMarkdown(compactText(stripDirectives(text))))
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(aiLineLimit)
                    .truncationMode(.tail)
            }
        }
    }

    private func compactText(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .reduce(into: [String]()) { result, line in
                if line.isEmpty && (result.last?.isEmpty ?? true) { return }
                result.append(line)
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private func stripDirectives(_ text: String) -> String {
    // Match ::directive-name{...} patterns (may span multiple lines)
    // Use a simple approach: remove lines that start with ::word{ or are continuation of a directive
    var result: [String] = []
    var inDirective = false
    var braceDepth = 0

    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if inDirective {
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                if ch == "}" { braceDepth -= 1 }
            }
            if braceDepth <= 0 {
                inDirective = false
                braceDepth = 0
            }
            continue
        }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("::") && trimmed.contains("{") {
            // Count braces to handle single-line vs multi-line directives
            braceDepth = 0
            for ch in line {
                if ch == "{" { braceDepth += 1 }
                if ch == "}" { braceDepth -= 1 }
            }
            if braceDepth > 0 {
                inDirective = true
            }
            // Either way, skip this line
            continue
        }
        result.append(String(line))
    }

    let cleaned = result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned
}
