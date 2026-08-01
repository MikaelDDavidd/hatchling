import Foundation
import CodeIslandCore
import Darwin

/// Translates between `AppState` and the wire types, and runs what the phone asks.
///
/// Lives apart from `AppState` on purpose: the mapping is going to churn as the app grows,
/// and none of it belongs in a file that is already 3.7k lines.
extension AppState {

    // MARK: - Wiring

    func setupMobileBridge() {
        MobileBridge.shared.commandHandler = { [weak self] command in
            guard let self else { return "Hatchling is shutting down" }
            return await MainActor.run { self.handleMobileCommand(command) }
        }
        MobileBridge.shared.onStateChange = { [weak self] state in
            guard case .online = state else { return }
            Task { @MainActor in self?.publishMobileState() }
        }
        MobileBridge.shared.start()
    }

    /// Called whenever session state moves. Cheap when nothing changed — the bridge diffs
    /// before it sends, and bails immediately when no phone is connected.
    func publishMobileState() {
        var payload: [String: MobileSession] = [:]
        for (id, session) in sessions {
            payload[id] = mobileSession(id: id, session: session)
        }
        MobileBridge.shared.publish(sessions: payload)
        publishMobileUsage()

        // The open session also gets its transcript refreshed, so the detail screen stays live
        // instead of showing whatever was true when it was opened.
        if let watched = MobileBridge.shared.watchedSessionId,
           let detail = mobileSessionDetail(for: watched) {
            MobileBridge.shared.publish(detail: detail)
        }
    }

    /// Rate limits, the same numbers the panel's usage bar shows.
    ///
    /// Claude's come from the statusline payload our wrapper captures; Codex's from its local
    /// rollout. Published alongside session state because they change on the same rhythm and
    /// splitting them would mean a second trip for two small numbers.
    func publishMobileUsage() {
        var claude: [MobileUsageWindow]?
        if let limits = ClaudeRateLimitReader.shared.limits {
            var windows: [MobileUsageWindow] = []
            if let pct = limits.fiveHourPercent {
                windows.append(MobileUsageWindow(
                    label: "5h", percent: pct,
                    resetsAt: limits.fiveHourResetAt.map { Int($0.timeIntervalSince1970) }
                ))
            }
            if let pct = limits.sevenDayPercent, pct >= 1 {
                windows.append(MobileUsageWindow(
                    label: "7d", percent: pct,
                    resetsAt: limits.sevenDayResetAt.map { Int($0.timeIntervalSince1970) }
                ))
            }
            if !windows.isEmpty { claude = windows }
        }

        var codex: [MobileUsageWindow]?
        if let snapshot = CodexUsageMonitor.shared.snapshot, !snapshot.isEmpty {
            codex = snapshot.windows.map {
                MobileUsageWindow(
                    label: $0.label,
                    percent: $0.roundedUsedPercentage,
                    resetsAt: $0.resetsAt.map { date in Int(date.timeIntervalSince1970) }
                )
            }
        }

        guard claude != nil || codex != nil else { return }
        MobileBridge.shared.publish(usage: MobileUsage(claude: claude, codex: codex))
    }

    // MARK: - Mapping

    private func mobileSession(id: String, session: SessionSnapshot) -> MobileSession {
        let usage = ContextUsageStore.shared.lookup(for: session, sessionId: id)
        return MobileSession(
            sessionId: id,
            source: session.source,
            status: Self.mobileStatus(session.status),
            project: session.projectDisplayName,
            cwd: session.cwd,
            model: session.shortModelName,
            currentTool: session.currentTool,
            toolDescription: session.toolDescription,
            lastUserPrompt: session.lastUserPrompt,
            lastAssistantMessage: session.lastAssistantMessage,
            startTime: Int(session.startTime.timeIntervalSince1970),
            lastActivity: Int(session.lastActivity.timeIntervalSince1970),
            interrupted: session.interrupted,
            canPrompt: PromptInjector.canInject(into: session),
            contextPercent: usage?.pct,
            // Same seed the panel uses, so the phone and the notch say the same word about the
            // same session instead of disagreeing a foot apart.
            verb: session.status == .running || session.status == .processing
                ? GerundVerbs.pick(seed: id)
                : nil,
            contextTokens: usage?.usedTokens,
            contextLimit: usage?.contextLimit,
            terminal: session.termApp,
            subagents: session.subagents.values.map { $0.agentType }.sorted()
        )
    }

    private static func mobileStatus(_ status: AgentStatus) -> String {
        switch status {
        case .idle:             return "idle"
        case .processing:       return "processing"
        case .running:          return "running"
        case .waitingApproval:  return "waitingApproval"
        case .waitingQuestion:  return "waitingQuestion"
        }
    }

    /// Tool input, flattened to strings for display. Values are truncated: a phone renders
    /// this, and a Write with a 4 MB payload has no business crossing the wire.
    private static func flatten(toolInput: [String: Any]?) -> [String: String]? {
        guard let toolInput else { return nil }
        var out: [String: String] = [:]
        for (key, value) in toolInput {
            let text: String
            switch value {
            case let s as String:  text = s
            case let n as NSNumber: text = n.stringValue
            default:
                if let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]) {
                    text = String(decoding: data, as: UTF8.self)
                } else {
                    text = String(describing: value)
                }
            }
            out[key] = String(text.prefix(2000))
        }
        return out
    }

    // MARK: - Publishing attention

    func publishMobileAttention(permission: PermissionRequest) {
        let sessionId = permission.event.sessionId ?? ""
        MobileBridge.shared.publish(attention: MobileAttention(
            attentionId: permission.id,
            sessionId: sessionId,
            kind: "permission",
            project: sessions[sessionId]?.projectDisplayName ?? "",
            tool: permission.event.toolName,
            toolInput: Self.flatten(toolInput: permission.event.toolInput),
            questions: nil
        ))
    }

    func publishMobileAttention(question: QuestionRequest) {
        let sessionId = question.event.sessionId ?? ""
        let items = question.askUserQuestionState?.items ?? []

        let questions: [MobileQuestion] = items.isEmpty
            ? [MobileQuestion(
                question: question.question.question,
                header: question.question.header,
                multiSelect: false,
                options: zip(
                    question.question.options ?? [],
                    (question.question.descriptions ?? []) + Array(repeating: "", count: max(0, (question.question.options?.count ?? 0) - (question.question.descriptions?.count ?? 0)))
                ).map { MobileQuestionOption(label: $0.0, description: $0.1.isEmpty ? nil : $0.1) }
              )]
            : items.map { item in
                let options = item.payload.options ?? []
                let descriptions = item.payload.descriptions ?? []
                return MobileQuestion(
                    question: item.payload.question,
                    header: item.payload.header,
                    multiSelect: item.multiSelect,
                    options: options.enumerated().map { index, label in
                        MobileQuestionOption(
                            label: label,
                            description: index < descriptions.count && !descriptions[index].isEmpty ? descriptions[index] : nil
                        )
                    }
                )
            }

        MobileBridge.shared.publish(attention: MobileAttention(
            attentionId: question.id,
            sessionId: sessionId,
            kind: "question",
            project: sessions[sessionId]?.projectDisplayName ?? "",
            tool: question.event.toolName,
            toolInput: nil,
            questions: questions
        ))
    }

    // MARK: - Session detail

    /// Full picture of one session, for the phone's detail screen.
    ///
    /// Only sent when a phone actually opens a session. Attaching this to every list update
    /// would push a transcript through the relay every few seconds for rows nobody is reading.
    func mobileSessionDetail(for sessionId: String) -> MobileSessionDetail? {
        guard let session = sessions[sessionId] else { return nil }

        // Newest first: on a phone the recent tools are what matter, and the list is read
        // from the top. Capped because a long session can accumulate hundreds.
        let tools = session.toolHistory.suffix(60).reversed().map { entry in
            MobileToolEntry(
                tool: entry.tool,
                detail: entry.description,
                at: Int(entry.timestamp.timeIntervalSince1970),
                ok: entry.success,
                agent: entry.agentType
            )
        }

        let messages = session.recentMessages.map {
            MobileMessage(user: $0.isUser, text: String($0.text.prefix(4000)))
        }

        return MobileSessionDetail(
            sessionId: sessionId,
            tools: Array(tools),
            messages: messages,
            permissionMode: session.permissionMode,
            isYolo: session.isYoloMode,
            subagents: session.subagents.values.map { $0.agentType }.sorted()
        )
    }

    // MARK: - Executing commands

    /// Returns nil on success, or a message explaining the refusal.
    ///
    /// Not private so tests can drive it directly. The interesting failures here are about
    /// whether a remote answer actually unblocks the waiting hook, and going through a live
    /// socket to assert that would be testing the socket.
    func handleMobileCommand(_ command: MobileBridge.Command) -> String? {
        switch command {
        case .permissionRespond(let attentionId, let decision):
            // Match on identity, never on "whatever is at the front of the queue" — by the time
            // this arrives the Mac may already have answered and moved on.
            guard let pending = permissionQueue.first, pending.id == attentionId else {
                return "That request was already resolved"
            }
            switch decision {
            case "allow":       approvePermission(always: false)
            case "allowAlways": approvePermission(always: true)
            case "deny":        denyPermission()
            default:            return "Unknown decision \(decision)"
            }
            MobileBridge.shared.publishAttentionCleared(attentionId: attentionId, reason: "answered")
            return nil

        case .questionAnswer(let attentionId, let answers):
            guard let pending = questionQueue.first, pending.id == attentionId else {
                return "That question was already answered"
            }
            // Keyed by question text, matching what AskUserQuestion expects.
            answerQuestionMulti(answers.map { (question: $0.key, answer: $0.value) })
            MobileBridge.shared.publishAttentionCleared(attentionId: attentionId, reason: "answered")
            return nil

        case .questionSkip(let attentionId):
            guard let pending = questionQueue.first, pending.id == attentionId else {
                return "That question was already answered"
            }
            skipQuestion()
            MobileBridge.shared.publishAttentionCleared(attentionId: attentionId, reason: "answered")
            return nil

        case .interrupt(let sessionId):
            guard let session = sessions[sessionId] else { return "Unknown session" }
            guard let pid = session.cliPid, pid > 0 else {
                return "This session has no live process to interrupt"
            }
            guard kill(pid, SIGINT) == 0 else {
                return "Could not interrupt: \(String(cString: strerror(errno)))"
            }
            return nil

        case .prompt(let sessionId, let text):
            guard let session = sessions[sessionId] else { return "Unknown session" }
            return PromptInjector.inject(text: text, into: session)

        case .refresh:
            publishMobileState()
            return nil

        case .watch(let sessionId):
            guard let detail = mobileSessionDetail(for: sessionId) else { return "Unknown session" }
            MobileBridge.shared.publish(detail: detail)
            MobileBridge.shared.watchedSessionId = sessionId
            return nil

        case .unwatch:
            MobileBridge.shared.watchedSessionId = nil
            return nil

        case .history(let sessionId, let before):
            guard let session = sessions[sessionId] else { return "Unknown session" }

            guard let path = TranscriptReader.transcriptPath(for: session, sessionId: sessionId) else {
                // Not an error worth an ack failure: the app shows "no transcript" instead of an
                // empty chat that looks broken.
                MobileBridge.shared.publish(history: MobileChatHistory(
                    sessionId: sessionId,
                    page: MobileChatPage(messages: [], nextBefore: nil, reachedStart: true),
                    available: false
                ))
                return nil
            }

            // Reading megabytes off disk has no business on the main thread; the panel would
            // stutter every time a phone scrolled up.
            Task.detached(priority: .userInitiated) {
                let page = TranscriptReader.page(path: path, before: before)
                    ?? MobileChatPage(messages: [], nextBefore: nil, reachedStart: true)
                await MainActor.run {
                    MobileBridge.shared.publish(history: MobileChatHistory(
                        sessionId: sessionId,
                        page: page,
                        available: true
                    ))
                }
            }
            return nil
        }
    }
}
