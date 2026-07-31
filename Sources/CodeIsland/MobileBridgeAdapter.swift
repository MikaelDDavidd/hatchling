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
    }

    // MARK: - Mapping

    private func mobileSession(id: String, session: SessionSnapshot) -> MobileSession {
        MobileSession(
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
            contextPercent: ContextUsageStore.shared.lookup(for: session, sessionId: id)?.pct
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

    // MARK: - Executing commands

    /// Returns nil on success, or a message explaining the refusal.
    private func handleMobileCommand(_ command: MobileBridge.Command) -> String? {
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
        }
    }
}
