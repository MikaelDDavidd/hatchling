import Foundation

/// Wire types for the mobile app. See `docs/PROTOCOL.md` in the hatchling-mobile repo —
/// a change here is a change there, and in the relay.
///
/// These are deliberately *not* `SessionSnapshot` itself. The snapshot carries plenty the phone
/// has no business seeing (tty paths, tmux sockets, window ids) and its shape is free to move
/// with the Mac UI. This file is the contract; it moves only on purpose.
public enum MobileProtocol {
    public static let version = 1
}

// MARK: - Envelope

public struct MobileEnvelope<Body: Codable>: Codable {
    public let v: Int
    public let type: String
    public let id: String
    public let ts: Int
    public let body: Body?

    public init(type: String, id: String = MobileID.generate(), body: Body?) {
        self.v = MobileProtocol.version
        self.type = type
        self.id = id
        self.ts = Int(Date().timeIntervalSince1970)
        self.body = body
    }
}

/// Envelope with the body left unparsed, so a receiver can switch on `type` before
/// committing to a shape.
public struct MobileEnvelopeHeader: Decodable {
    public let v: Int
    public let type: String
    public let id: String
    public let ts: Int
}

/// Lexicographically sortable id: 48-bit millisecond timestamp plus 80 bits of randomness,
/// Crockford base32. Same layout as ULID, without pulling in a dependency for it.
public enum MobileID {
    private static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func generate() -> String {
        var bits: [UInt8] = []
        let ms = UInt64(Date().timeIntervalSince1970 * 1000)
        for shift in stride(from: 40, through: 0, by: -8) {
            bits.append(UInt8((ms >> UInt64(shift)) & 0xFF))
        }
        for _ in 0..<10 { bits.append(UInt8.random(in: 0...255)) }

        var out = ""
        var accumulator: UInt = 0
        var accumulatedBits = 0
        for byte in bits {
            accumulator = (accumulator << 8) | UInt(byte)
            accumulatedBits += 8
            while accumulatedBits >= 5 {
                let index = Int((accumulator >> UInt(accumulatedBits - 5)) & 0x1F)
                out.append(alphabet[index])
                accumulatedBits -= 5
            }
        }
        if accumulatedBits > 0 {
            let index = Int((accumulator << UInt(5 - accumulatedBits)) & 0x1F)
            out.append(alphabet[index])
        }
        return out
    }
}

// MARK: - Handshake

public struct MobileHello: Codable {
    public let role: String       // "mac" | "phone"
    public let token: String
    public let device: String

    public init(role: String, token: String, device: String) {
        self.role = role
        self.token = token
        self.device = device
    }
}

public struct MobilePeer: Codable {
    public let role: String
    public let device: String

    public init(role: String, device: String) {
        self.role = role
        self.device = device
    }
}

public struct MobileReady: Codable {
    public let peers: [MobilePeer]

    public init(peers: [MobilePeer]) { self.peers = peers }
}

// MARK: - Sessions

public struct MobileSession: Codable, Equatable {
    public let sessionId: String
    public let source: String
    public let status: String
    public let project: String
    public let cwd: String?
    public let model: String?
    public let currentTool: String?
    public let toolDescription: String?
    public let lastUserPrompt: String?
    public let lastAssistantMessage: String?
    public let startTime: Int
    public let lastActivity: Int
    public let interrupted: Bool
    /// Whether the Mac can inject text into this session. False means the phone should not
    /// offer a prompt box it cannot honour — see `PromptInjector`.
    public let canPrompt: Bool
    public let contextPercent: Int?
    /// The gerund the notch shows while an agent works — "Murmuring", "Nesting". Cosmetic, and
    /// the whole point: it is how the panel reads as alive rather than as a progress bar.
    public let verb: String?
    /// Absolute context, so the phone can show "495k/1M" the way the panel does.
    public let contextTokens: Int?
    public let contextLimit: Int?
    /// Which terminal the session runs in, for the same reason the panel shows it: with several
    /// sessions open it is how you know which window to go to.
    public let terminal: String?
    /// Subagents running right now, by type.
    public let subagents: [String]

    public init(
        sessionId: String,
        source: String,
        status: String,
        project: String,
        cwd: String?,
        model: String?,
        currentTool: String?,
        toolDescription: String?,
        lastUserPrompt: String?,
        lastAssistantMessage: String?,
        startTime: Int,
        lastActivity: Int,
        interrupted: Bool,
        canPrompt: Bool,
        contextPercent: Int?,
        verb: String?,
        contextTokens: Int?,
        contextLimit: Int?,
        terminal: String?,
        subagents: [String]
    ) {
        self.sessionId = sessionId
        self.source = source
        self.status = status
        self.project = project
        self.cwd = cwd
        self.model = model
        self.currentTool = currentTool
        self.toolDescription = toolDescription
        self.lastUserPrompt = lastUserPrompt
        self.lastAssistantMessage = lastAssistantMessage
        self.startTime = startTime
        self.lastActivity = lastActivity
        self.interrupted = interrupted
        self.canPrompt = canPrompt
        self.contextPercent = contextPercent
        self.verb = verb
        self.contextTokens = contextTokens
        self.contextLimit = contextLimit
        self.terminal = terminal
        self.subagents = subagents
    }
}

/// One tool the agent ran. What the detail screen is built from.
public struct MobileToolEntry: Codable, Equatable {
    public let tool: String
    public let detail: String?
    public let at: Int
    public let ok: Bool
    /// Which subagent ran it, or nil for the main thread.
    public let agent: String?

    public init(tool: String, detail: String?, at: Int, ok: Bool, agent: String?) {
        self.tool = tool
        self.detail = detail
        self.at = at
        self.ok = ok
        self.agent = agent
    }
}

public struct MobileMessage: Codable, Equatable {
    public let user: Bool
    public let text: String

    public init(user: Bool, text: String) {
        self.user = user
        self.text = text
    }
}

/// Everything the detail screen shows, sent only when a phone opens a session.
///
/// Kept out of `MobileSession` on purpose. The list carries one line per session and is
/// republished on every state change; attaching a transcript to that would push kilobytes
/// through the relay every few seconds for rows nobody is looking at.
public struct MobileSessionDetail: Codable, Equatable {
    public let sessionId: String
    public let tools: [MobileToolEntry]
    public let messages: [MobileMessage]
    public let permissionMode: String?
    public let isYolo: Bool?
    public let subagents: [String]

    public init(
        sessionId: String,
        tools: [MobileToolEntry],
        messages: [MobileMessage],
        permissionMode: String?,
        isYolo: Bool?,
        subagents: [String]
    ) {
        self.sessionId = sessionId
        self.tools = tools
        self.messages = messages
        self.permissionMode = permissionMode
        self.isYolo = isYolo
        self.subagents = subagents
    }
}

/// One turn of the conversation, as the phone's chat renders it.
public struct MobileChatMessage: Codable, Equatable {
    public let user: Bool
    public let text: String
    public let at: Int
    /// Tools this turn called, named but not expanded — the detail screen lists them in full.
    public let tools: [String]

    public init(user: Bool, text: String, at: Int, tools: [String]) {
        self.user = user
        self.text = text
        self.at = at
        self.tools = tools
    }
}

/// A page of conversation, newest first.
///
/// Paged because a working day's transcript runs to tens of megabytes, and because a chat is
/// scrolled from the bottom anyway: the last exchange opens, older pages load on scroll.
public struct MobileChatPage: Codable, Equatable {
    public let messages: [MobileChatMessage]
    /// Cursor for the next page up, or nil at the beginning of the conversation.
    public let nextBefore: Int?
    public let reachedStart: Bool

    public init(messages: [MobileChatMessage], nextBefore: Int?, reachedStart: Bool) {
        self.messages = messages
        self.nextBefore = nextBefore
        self.reachedStart = reachedStart
    }
}

/// Reply to `session.history`, carrying the page and which session it belongs to.
public struct MobileChatHistory: Codable, Equatable {
    public let sessionId: String
    public let page: MobileChatPage
    /// False when this CLI keeps no transcript we can read, so the app can say so rather than
    /// showing an empty chat that looks broken.
    public let available: Bool

    public init(sessionId: String, page: MobileChatPage, available: Bool) {
        self.sessionId = sessionId
        self.page = page
        self.available = available
    }
}

public struct MobileHistoryRequest: Codable {
    public let sessionId: String
    public let before: Int?

    public init(sessionId: String, before: Int?) {
        self.sessionId = sessionId
        self.before = before
    }
}

public struct MobileSessionList: Codable {
    public let sessions: [MobileSession]
    public init(sessions: [MobileSession]) { self.sessions = sessions }
}

public struct MobileSessionGone: Codable {
    public let sessionId: String
    public init(sessionId: String) { self.sessionId = sessionId }
}

// MARK: - Attention

public struct MobileQuestionOption: Codable {
    public let label: String
    public let description: String?

    public init(label: String, description: String?) {
        self.label = label
        self.description = description
    }
}

public struct MobileQuestion: Codable {
    public let question: String
    public let header: String?
    public let multiSelect: Bool
    public let options: [MobileQuestionOption]

    public init(question: String, header: String?, multiSelect: Bool, options: [MobileQuestionOption]) {
        self.question = question
        self.header = header
        self.multiSelect = multiSelect
        self.options = options
    }
}

public struct MobileAttention: Codable {
    public let attentionId: String
    public let sessionId: String
    /// "permission" | "question"
    public let kind: String
    public let project: String
    public let tool: String?
    /// Flattened to strings — the phone renders it, it does not interpret it, and arbitrary
    /// JSON would drag `Any` through a Codable boundary for no gain.
    public let toolInput: [String: String]?
    public let questions: [MobileQuestion]?

    public init(
        attentionId: String,
        sessionId: String,
        kind: String,
        project: String,
        tool: String?,
        toolInput: [String: String]?,
        questions: [MobileQuestion]?
    ) {
        self.attentionId = attentionId
        self.sessionId = sessionId
        self.kind = kind
        self.project = project
        self.tool = tool
        self.toolInput = toolInput
        self.questions = questions
    }
}

public struct MobileAttentionCleared: Codable {
    public let attentionId: String
    /// "answered" | "expired" | "local"
    public let reason: String

    public init(attentionId: String, reason: String) {
        self.attentionId = attentionId
        self.reason = reason
    }
}

// MARK: - Usage

public struct MobileUsageWindow: Codable {
    public let label: String
    public let percent: Int
    public let resetsAt: Int?

    public init(label: String, percent: Int, resetsAt: Int?) {
        self.label = label
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

public struct MobileUsage: Codable {
    public let claude: [MobileUsageWindow]?
    public let codex: [MobileUsageWindow]?

    public init(claude: [MobileUsageWindow]?, codex: [MobileUsageWindow]?) {
        self.claude = claude
        self.codex = codex
    }
}

// MARK: - Commands from the phone

public struct MobilePermissionRespond: Codable {
    public let attentionId: String
    /// "allow" | "allowAlways" | "deny"
    public let decision: String

    public init(attentionId: String, decision: String) {
        self.attentionId = attentionId
        self.decision = decision
    }
}

public struct MobileQuestionAnswer: Codable {
    public let attentionId: String
    /// Keyed by question *text*, never by header. See commit bda258e.
    public let answers: [String: String]

    public init(attentionId: String, answers: [String: String]) {
        self.attentionId = attentionId
        self.answers = answers
    }
}

public struct MobileAttentionRef: Codable {
    public let attentionId: String
    public init(attentionId: String) { self.attentionId = attentionId }
}

public struct MobileSessionRef: Codable {
    public let sessionId: String
    public init(sessionId: String) { self.sessionId = sessionId }
}

public struct MobilePrompt: Codable {
    public let sessionId: String
    public let text: String

    public init(sessionId: String, text: String) {
        self.sessionId = sessionId
        self.text = text
    }
}

// MARK: - Replies

public struct MobileAck: Codable {
    public let ref: String
    public let ok: Bool
    public let detail: String?

    public init(ref: String, ok: Bool, detail: String?) {
        self.ref = ref
        self.ok = ok
        self.detail = detail
    }
}

public struct MobileError: Codable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}

// MARK: - Pairing

public struct MobileEmpty: Codable {
    public init() {}
}

public struct MobilePairCode: Codable {
    public let code: String?
    /// Epoch milliseconds, matching what the relay's `Date.now()` produces.
    public let expiresAt: Int?

    public init(code: String?, expiresAt: Int?) {
        self.code = code
        self.expiresAt = expiresAt
    }
}

public struct MobilePairedDevice: Codable {
    public let id: String
    public let name: String
    public let lastSeen: Int?

    public init(id: String, name: String, lastSeen: Int?) {
        self.id = id
        self.name = name
        self.lastSeen = lastSeen
    }
}

public struct MobilePairDevices: Codable {
    public let devices: [MobilePairedDevice]?

    public init(devices: [MobilePairedDevice]?) { self.devices = devices }
}

public struct MobilePairRevoke: Codable {
    public let deviceId: String
    public init(deviceId: String) { self.deviceId = deviceId }
}

/// Message type discriminators, in one place so the compiler catches a typo instead of the wire.
public enum MobileMessageType {
    public static let hello = "hello"
    public static let ready = "ready"
    public static let sessions = "sessions"
    public static let sessionPatch = "session.patch"
    public static let sessionGone = "session.gone"
    public static let attention = "attention"
    public static let attentionCleared = "attention.cleared"
    public static let usage = "usage"
    public static let ack = "ack"
    public static let error = "error"

    public static let permissionRespond = "permission.respond"
    public static let questionAnswer = "question.answer"
    public static let questionSkip = "question.skip"
    public static let sessionInterrupt = "session.interrupt"
    public static let sessionPrompt = "session.prompt"
    public static let sessionsRefresh = "sessions.refresh"
    /// Phone opened a session; Mac replies with `sessionDetail`.
    public static let sessionWatch = "session.watch"
    public static let sessionUnwatch = "session.unwatch"
    public static let sessionDetail = "session.detail"
    /// Phone asks for a page of the conversation; Mac replies with `chatHistory`.
    public static let sessionHistory = "session.history"
    public static let chatHistory = "chat.history"

    public static let pairCreate = "pair.create"
    public static let pairCreated = "pair.created"
    public static let pairList = "pair.list"
    public static let pairRevoke = "pair.revoke"
}
