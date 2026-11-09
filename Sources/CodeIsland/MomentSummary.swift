import Foundation
import Security
import CodeIslandCore

// MARK: - The moment, in one line
//
// A session card used to show the last prompt and the last reply cut off mid-sentence,
// which said little about where the agent actually was. Each card now shows two lines:
//
//   now   — what is happening this instant. Live and local while the agent works, built
//           from the tool it is running ("Editando PanelTabBar.swift"); once it stops, a
//           one-line summary of what it said.
//   task  — what the session is about, summarised from your last request.
//
// The summaries come from Claude Haiku when an Anthropic API key is set in Settings. With
// no key, or when the call fails, both lines fall back to local rules, so the card is
// never empty and never waits on the network.

struct SessionMoment: Equatable {
    var now: String
    var task: String?
}

@MainActor
final class MomentStore: ObservableObject {
    static let shared = MomentStore()

    /// AI lines per session, with the fingerprint of the session state they describe.
    @Published private var summaries: [String: (fingerprint: String, moment: SessionMoment)] = [:]
    private var inFlight: [String: String] = [:]
    private var lastCall: [String: Date] = [:]
    private var pending: [String: (fingerprint: String, task: Task<Void, Never>)] = [:]

    /// While an agent works its reply changes every few seconds; summarising each change
    /// would spend calls on text nobody reads. One call per session per this interval.
    private static let minimumInterval: TimeInterval = 20

    func moment(for session: SessionSnapshot, sessionId: String) -> SessionMoment {
        let local = Self.localMoment(for: session)
        guard MomentSummarizer.isEnabled else { return local }
        let fingerprint = Self.fingerprint(of: session)
        let cached = summaries[sessionId]
        // The body asks on every render; only a change of state may reschedule, or a panel that
        // redraws every few seconds would keep pushing the call back and never make it.
        if cached?.fingerprint != fingerprint, inFlight[sessionId] != fingerprint,
           pending[sessionId]?.fingerprint != fingerprint {
            schedule(session: session, sessionId: sessionId, fingerprint: fingerprint)
        }
        guard let ai = cached?.moment else { return local }
        // The live action beats any summary while the agent is mid-step.
        switch session.status {
        case .processing, .running, .waitingApproval, .waitingQuestion:
            return SessionMoment(now: local.now, task: ai.task ?? local.task)
        case .idle:
            return SessionMoment(now: ai.now, task: ai.task ?? local.task)
        }
    }

    private func schedule(session: SessionSnapshot, sessionId: String, fingerprint: String) {
        pending[sessionId]?.task.cancel()
        let since = Date().timeIntervalSince(lastCall[sessionId] ?? .distantPast)
        let idle = session.status == .idle
        // Settle first: a burst of hook events should end in one call, not ten.
        let wait = max(idle ? 1.2 : 4, idle ? 0 : Self.minimumInterval - since)
        let task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            self.inFlight[sessionId] = fingerprint
            self.lastCall[sessionId] = Date()
            let result = await MomentSummarizer.summarize(session)
            self.inFlight[sessionId] = nil
            self.pending[sessionId] = nil
            if let result {
                self.summaries[sessionId] = (fingerprint, result)
            }
        }
        pending[sessionId] = (fingerprint, task)
    }

    private static func fingerprint(of session: SessionSnapshot) -> String {
        let bucket: String = {
            switch session.status {
            case .idle: return "idle"
            case .processing, .running: return "work"
            case .waitingApproval, .waitingQuestion: return "wait"
            }
        }()
        let prompt = lastRealPrompt(of: session) ?? ""
        let reply = String((lastReply(of: session) ?? "").prefix(600))
        return "\(bucket)|\(prompt.hashValue)|\(reply.hashValue)"
    }

    // MARK: Local rules

    /// The last thing you actually typed. Harness messages arrive as user turns too —
    /// `<task-notification>`, `<system-reminder>`, scheduled tasks — and summarising one
    /// of those gave cards a "task" made of ids.
    nonisolated static func lastRealPrompt(of session: SessionSnapshot) -> String? {
        let candidates = session.recentMessages.reversed().filter(\.isUser).map(\.text) + [session.lastUserPrompt ?? ""]
        return candidates.first { text in
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !t.isEmpty && !t.hasPrefix("<") && !t.hasPrefix("[SYSTEM")
        }
    }

    nonisolated static func lastReply(of session: SessionSnapshot) -> String? {
        if let reply = session.lastAssistantMessage, !reply.isEmpty { return reply }
        return session.recentMessages.last { !$0.isUser && !$0.text.isEmpty }?.text
    }

    static func localMoment(for session: SessionSnapshot) -> SessionMoment {
        let pt = L10n.shared.effectiveLanguage == "pt"
        let task = lastRealPrompt(of: session).map { cleanLine($0, limit: 90) }.flatMap { $0.isEmpty ? nil : $0 }
        switch session.status {
        case .waitingApproval:
            return SessionMoment(now: request(tool: session.currentTool, detail: session.toolDescription, pt: pt), task: task)
        case .waitingQuestion:
            return SessionMoment(now: pt ? "Tem uma pergunta pra você" : "Has a question for you", task: task)
        case .processing, .running:
            if let tool = session.currentTool {
                return SessionMoment(now: describe(tool: tool, detail: session.toolDescription, pt: pt), task: task)
            }
            return SessionMoment(now: pt ? "Pensando…" : "Thinking…", task: task)
        case .idle:
            if let reply = lastReply(of: session) {
                return SessionMoment(now: firstSentence(of: reply), task: task)
            }
            return SessionMoment(now: pt ? "Esperando você" : "Waiting for you", task: task)
        }
    }

    /// What it is asking to do, as a request: "Quer rodar terraform apply".
    static func request(tool: String?, detail: String?, pt: Bool) -> String {
        let target = detail.map { simplify(target: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        func ask(_ verbPT: String, _ verbEN: String) -> String {
            let verb = pt ? verbPT : verbEN
            return target.map { "\(verb) \($0)" } ?? verb
        }
        switch tool {
        case "Bash":                          return ask("Quer rodar", "Wants to run")
        case "Edit", "MultiEdit", "NotebookEdit": return ask("Quer editar", "Wants to edit")
        case "Write":                         return ask("Quer criar", "Wants to write")
        case "WebFetch":                      return ask("Quer abrir", "Wants to open")
        case "WebSearch":                     return ask("Quer pesquisar", "Wants to search for")
        case .some(let name):                 return pt ? "Quer usar \(name)" : "Wants to use \(name)"
        case .none:                           return pt ? "Precisa da sua aprovação" : "Needs your approval"
        }
    }

    /// "Edit" + "/a/b/PanelTabBar.swift" → "Editando PanelTabBar.swift".
    static func describe(tool: String, detail: String?, pt: Bool) -> String {
        let target = detail.map { simplify(target: $0) }.flatMap { $0.isEmpty ? nil : $0 }
        func phrase(_ verbPT: String, _ verbEN: String) -> String {
            let verb = pt ? verbPT : verbEN
            return target.map { "\(verb) \($0)" } ?? verb
        }
        switch tool {
        case "Edit", "MultiEdit", "NotebookEdit": return phrase("Editando", "Editing")
        case "Write":                             return phrase("Escrevendo", "Writing")
        case "Read":                              return phrase("Lendo", "Reading")
        case "Bash":                              return phrase("Rodando", "Running")
        case "Grep", "Glob":                      return phrase("Procurando", "Searching for")
        case "WebSearch":                         return phrase("Pesquisando na web:", "Searching the web:")
        case "WebFetch":                          return phrase("Lendo a página", "Reading")
        case "Task", "Agent":                     return phrase("Delegou a um subagente:", "Delegated:")
        case "TodoWrite", "TaskCreate", "TaskUpdate": return pt ? "Organizando as tarefas" : "Updating the plan"
        default:
            if tool.hasPrefix("mcp__") {
                let parts = tool.split(separator: "_").filter { !$0.isEmpty }
                let name = parts.dropFirst().joined(separator: " ")
                return pt ? "Usando \(name)" : "Using \(name)"
            }
            return target.map { "\(tool) · \($0)" } ?? tool
        }
    }

    private static func simplify(target: String) -> String {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        // Paths read best as their last component.
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~"), !trimmed.contains(" ") {
            return (trimmed as NSString).lastPathComponent
        }
        return cleanLine(trimmed, limit: 60)
    }

    nonisolated static func firstSentence(of text: String) -> String {
        let plain = cleanLine(text, limit: 400)
        if let end = plain.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            let sentence = String(plain[..<end.upperBound]).trimmingCharacters(in: .whitespaces)
            if sentence.count >= 12 { return cleanLine(sentence, limit: 110) }
        }
        return cleanLine(plain, limit: 110)
    }

    /// Strips markdown and line breaks, and cuts at a word boundary with an ellipsis.
    nonisolated static func cleanLine(_ text: String, limit: Int) -> String {
        var s = text
        for pattern in [#"```[\s\S]*?```"#, #"`([^`]*)`"#, #"\*\*([^*]*)\*\*"#, #"\[([^\]]*)\]\([^)]*\)"#, #"^#+\s*"#, #"<[^>]+>"#] {
            s = s.replacingOccurrences(of: pattern, with: pattern.contains("(") && !pattern.hasPrefix("```") ? "$1" : "",
                                       options: [.regularExpression])
        }
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.count > limit else { return s }
        let cut = s.prefix(limit)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .punctuationCharacters.union(.whitespaces)) + "…"
    }
}

// MARK: - Claude Haiku summaries

enum MomentSummarizer {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.aiMomentSummary) as? Bool ?? SettingsDefaults.aiMomentSummary
            && AnthropicKeychain.hasKey
    }

    private struct Request: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        struct Thinking: Encodable { let type: String }
        struct OutputConfig: Encodable { let effort: String }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
        let thinking: Thinking
        let output_config: OutputConfig
    }

    private struct Response: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
        let stop_reason: String?
    }

    static func summarize(_ session: SessionSnapshot) async -> SessionMoment? {
        guard let key = AnthropicKeychain.read() else { return nil }
        let language = L10n.shared.effectiveLanguage == "pt" ? "Brazilian Portuguese"
            : L10n.shared.effectiveLanguage == "zh" ? "Simplified Chinese"
            : L10n.shared.effectiveLanguage == "tr" ? "Turkish" : "English"
        let system = """
        You label a coding agent's session for a tiny status card. Reply with exactly two lines in \(language), \
        no quotes, no markdown, no trailing period:
        line 1: what the agent just did or said, at most 70 characters, starting with a verb in the past tense \
        when it finished something (e.g. "Corrigiu o scroll da lista e reinstalou o app")
        line 2: what the session is about overall, from the user's request, at most 60 characters
        """
        var context = "Status: \(session.status)\n"
        if let prompt = MomentStore.lastRealPrompt(of: session) { context += "User's last request:\n\(prompt.prefix(1500))\n" }
        if let tool = session.currentTool { context += "Current tool: \(tool) \(session.toolDescription ?? "")\n" }
        if let reply = MomentStore.lastReply(of: session) { context += "Agent's latest message:\n\(reply.prefix(3000))\n" }

        let body = Request(
            model: "claude-haiku-5-5",
            max_tokens: 200,
            system: system,
            messages: [.init(role: "user", content: context)],
            thinking: .init(type: "disabled"),
            output_config: .init(effort: "low")
        )
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        guard let payload = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = payload

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data),
              decoded.stop_reason != "refusal" else { return nil }
        let text = decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return nil }
        return SessionMoment(
            now: MomentStore.cleanLine(first, limit: 90),
            task: lines.dropFirst().first.map { MomentStore.cleanLine($0, limit: 80) }
        )
    }
}

// MARK: - API key in the Keychain

enum AnthropicKeychain {
    private static let service = "dev.mikaeldavid.hatchling"
    private static let account = "anthropic-api-key"
    private static var cachedPresence: Bool?

    static var hasKey: Bool {
        if let cachedPresence { return cachedPresence }
        let present = read() != nil
        cachedPresence = present
        return present
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    static func save(_ key: String) -> Bool {
        delete()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let ok = SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        cachedPresence = ok
        return ok
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        cachedPresence = false
    }
}
