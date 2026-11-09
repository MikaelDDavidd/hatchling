import Foundation
import Security
import os.log

// MARK: - Who writes the AI lines
//
// The card summaries and the companion's lines can come from Claude Haiku (an Anthropic
// key) or from a model on NVIDIA's free API (an NVIDIA key). "Automático" uses whichever
// key is saved, Anthropic first. The keys live in the Keychain, never in a file, and only
// the short text each feature builds is sent.

enum AIProvider: String, CaseIterable {
    case auto, anthropic, nvidia
}

enum AIText {
    /// What each call did (provider, outcome, time), never the key or the text.
    static let log = Logger(subsystem: "dev.mikaeldavid.hatchling", category: "AI")
    /// The model used on NVIDIA's API. On 2026-11-09 only 3 of the 53 chat models listed
    /// for the free key actually answered (the rest gave 404 or timed out); this one did in
    /// under a second, in the two-line format, in good Portuguese. The second is the
    /// fallback when the first is down.
    static let defaultNvidiaModel = "nvidia/nemotron-3.5-bolt-e4b"
    static let fallbackNvidiaModel = "google/diffusiongemma-26b-a4b-it"

    private enum Route {
        case anthropic(key: String)
        case nvidia(key: String, model: String)
    }

    private static var route: Route? {
        let choice = AIProvider(rawValue: UserDefaults.standard.string(forKey: SettingsKey.aiProvider) ?? "") ?? .auto
        let anthropic = KeychainSecret.anthropic.read()
        let nvidia = KeychainSecret.nvidia.read()
        let model = UserDefaults.standard.string(forKey: SettingsKey.nvidiaModel).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultNvidiaModel
        switch choice {
        case .anthropic: return anthropic.map { .anthropic(key: $0) }
        case .nvidia: return nvidia.map { .nvidia(key: $0, model: model) }
        case .auto:
            if let anthropic { return .anthropic(key: anthropic) }
            return nvidia.map { .nvidia(key: $0, model: model) }
        }
    }

    /// True when a key for the chosen provider is saved.
    static var isAvailable: Bool {
        switch AIProvider(rawValue: UserDefaults.standard.string(forKey: SettingsKey.aiProvider) ?? "") ?? .auto {
        case .anthropic: return KeychainSecret.anthropic.hasKey
        case .nvidia: return KeychainSecret.nvidia.hasKey
        case .auto: return KeychainSecret.anthropic.hasKey || KeychainSecret.nvidia.hasKey
        }
    }

    /// One short completion, or nil without a key or on any failure (callers fall back to
    /// their local rules).
    /// `temperature` applies to NVIDIA models; Claude keeps its default.
    static func complete(system: String, user: String, maxTokens: Int, timeout: TimeInterval,
                         temperature: Double = 0.3) async -> String? {
        guard let route else {
            log.notice("no key for the chosen provider; local rules instead")
            return nil
        }
        switch route {
        case .anthropic(let key):
            return await anthropic(key: key, system: system, user: user, maxTokens: maxTokens, timeout: timeout)
        case .nvidia(let key, let model):
            for candidate in [model, fallbackNvidiaModel] where candidate == model || model == defaultNvidiaModel {
                if let text = await nvidia(key: key, model: candidate, system: system, user: user,
                                           maxTokens: maxTokens, timeout: timeout, temperature: temperature) {
                    return text
                }
            }
            return nil
        }
    }

    // MARK: Anthropic

    private struct AnthropicRequest: Encodable {
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

    private struct AnthropicResponse: Decodable {
        struct Block: Decodable { let type: String; let text: String? }
        let content: [Block]
        let stop_reason: String?
    }

    private static func anthropic(key: String, system: String, user: String, maxTokens: Int, timeout: TimeInterval) async -> String? {
        let body = AnthropicRequest(
            model: "claude-haiku-5-5",
            max_tokens: maxTokens,
            system: system,
            messages: [.init(role: "user", content: user)],
            thinking: .init(type: "disabled"),
            output_config: .init(effort: "low")
        )
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        guard let payload = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = payload
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(AnthropicResponse.self, from: data),
              decoded.stop_reason != "refusal" else { return nil }
        let text = decoded.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        return text.isEmpty ? nil : text
    }

    // MARK: NVIDIA (OpenAI-style chat completions)

    private struct NvidiaRequest: Encodable {
        struct Message: Encodable { let role: String; let content: String }
        let model: String
        let messages: [Message]
        let max_tokens: Int
        let temperature: Double
    }

    private struct NvidiaResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private static func nvidia(key: String, model: String, system: String, user: String,
                               maxTokens: Int, timeout: TimeInterval, temperature: Double) async -> String? {
        let body = NvidiaRequest(
            model: model,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)],
            max_tokens: maxTokens,
            temperature: temperature
        )
        var request = URLRequest(url: URL(string: "https://integrate.api.nvidia.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = max(timeout, 12)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        guard let payload = try? JSONEncoder().encode(body) else { return nil }
        request.httpBody = payload
        let started = Date()
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            log.notice("nvidia \(model, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200,
              let decoded = try? JSONDecoder().decode(NvidiaResponse.self, from: data),
              var text = decoded.choices.first?.message.content else {
            log.notice("nvidia \(model, privacy: .public): HTTP \(status) unusable answer")
            return nil
        }
        log.notice("nvidia \(model, privacy: .public): ok in \(Int(Date().timeIntervalSince(started) * 1000))ms")
        // Some models think out loud first; keep only what comes after.
        if let end = text.range(of: "</think>") { text = String(text[end.upperBound...]) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

// MARK: - API keys in the Keychain

struct KeychainSecret {
    let account: String

    static let anthropic = KeychainSecret(account: "anthropic-api-key")
    static let nvidia = KeychainSecret(account: "nvidia-api-key")

    private static let service = "dev.mikaeldavid.hatchling"
    nonisolated(unsafe) private static var presence: [String: Bool] = [:]

    var hasKey: Bool {
        if let known = Self.presence[account] { return known }
        let present = read() != nil
        Self.presence[account] = present
        return present
    }

    func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status != errSecSuccess && status != errSecItemNotFound {
            AIText.log.notice("keychain \(account, privacy: .public): OSStatus \(status)")
        }
        guard status == errSecSuccess,
              let data = item as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    @discardableResult
    func save(_ key: String) -> Bool {
        delete()
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(trimmed.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let ok = SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
        Self.presence[account] = ok
        return ok
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        Self.presence[account] = false
    }
}
