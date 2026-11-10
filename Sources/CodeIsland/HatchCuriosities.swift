import Foundation
import os.log
import CodeIslandCore

// MARK: - Curiosities about what you care about
//
// The topics come from what Hatch knows about you (HatchProfile): your club and national
// team, the series, films, games and music you like, the technologies of your projects.
// Now and then it looks one up on Wikipedia and keeps one curiosity ready for the next
// quiet moment.
//
// What leaves the Mac: topic names go to Wikipedia; the article text goes to the AI
// provider you chose, to write the line. Turned off with the "curiosities" setting.

struct HatchCuriosity {
    let topic: String
    let text: String
}

@MainActor
final class HatchCuriosities {
    static let shared = HatchCuriosities()

    private(set) var ready: HatchCuriosity?
    private var preparing = false
    private var lastPrepared = Date.distantPast
    private var recentTopics: [String] = []

    private static let log = Logger(subsystem: "dev.mikaeldavid.hatchling", category: "Curiosities")

    private var pt: Bool { L10n.shared.effectiveLanguage == "pt" }

    var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.hatchCuriosities) as? Bool ?? SettingsDefaults.hatchCuriosities
    }

    /// Hands over the prepared curiosity, if any, and starts on the next one later.
    func take() -> HatchCuriosity? {
        defer { ready = nil }
        return ready
    }

    /// Called every minute by the companion: keeps one curiosity ready. Cheap when there is
    /// nothing to do.
    func tick(force: Bool = false) {
        guard enabled, !preparing, ready == nil, force || Date().timeIntervalSince(lastPrepared) > 20 * 60 else { return }
        preparing = true
        lastPrepared = Date()
        Task { [weak self] in
            guard let self else { return }
            await self.prepare()
            self.preparing = false
        }
    }

    // MARK: A curiosity

    private func prepare() async {
        // Half the time something you like, when there is one; otherwise a technology of
        // yours, or a classic of computing.
        let mine = HatchProfile.shared.curiosityTopics(pt: pt)
        let classics: [(topic: String, query: String)] = (pt
            ? ["Grace Hopper", "Ada Lovelace", "Linus Torvalds", "Bug (informática)", "Unix", "Git"]
            : ["Grace Hopper", "Ada Lovelace", "Linus Torvalds", "Software bug", "Unix", "Git"]).map { ($0, $0) }
        var pool: [(topic: String, query: String)]
        if !mine.likes.isEmpty, Bool.random() { pool = mine.likes }
        else if !mine.techs.isEmpty, Bool.random() { pool = mine.techs }
        else { pool = classics }
        pool = pool.filter { !recentTopics.contains($0.topic) }
        if pool.isEmpty { pool = mine.likes + mine.techs + classics }
        guard let pick = pool.randomElement() else { return }
        recentTopics = (recentTopics + [pick.topic]).suffix(6)
        let topic = pick.query

        guard let article = await Self.wikipedia(topic, pt: pt) else {
            Self.log.notice("no article for a topic")
            return
        }
        let text: String
        if AIText.isAvailable, let written = await AIText.complete(
            system: """
            Write ONE surprising, true curiosity about "\(article.title)" for a fan, in \(pt ? "Brazilian Portuguese" : "English"), \
            at most 160 characters, starting with "\(pt ? "Sabia que" : "Did you know")". Use only facts stated in the text below. \
            No quotes, no emoji, no hashtags, no preamble.
            """,
            user: String(article.text.prefix(6000)), maxTokens: 120, timeout: 15, temperature: 0.6
        ) {
            text = written.trimmingCharacters(in: CharacterSet(charactersIn: "\"“” \n"))
        } else if let sentence = Self.factSentence(in: article.text) {
            text = sentence
        } else {
            return
        }
        ready = HatchCuriosity(topic: pick.topic, text: MomentStore.cleanLine(text, limit: 200))
        Self.log.notice("curiosity ready")
    }

    /// A sentence with a number in it reads like a fact; the first one past the opening.
    private nonisolated static func factSentence(in text: String) -> String? {
        let sentences = text.components(separatedBy: ". ").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Skip pieces cut at an abbreviation ("Howard H."), whose last word is a letter or two.
        let candidates = sentences.dropFirst().filter { sentence in
            let last = sentence.split(separator: " ").last.map { $0.trimmingCharacters(in: .punctuationCharacters) } ?? ""
            return sentence.count > 40 && sentence.count < 200 && last.count > 2
                && sentence.rangeOfCharacter(from: .decimalDigits) != nil
        }
        return candidates.randomElement().map { $0.hasSuffix(".") ? $0 : $0 + "." }
    }

    /// The article for a topic: search, then its plain text.
    private nonisolated static func wikipedia(_ topic: String, pt: Bool) async -> (title: String, text: String)? {
        let host = pt ? "pt.wikipedia.org" : "en.wikipedia.org"
        var search = URLComponents(string: "https://\(host)/w/api.php")!
        search.queryItems = [
            .init(name: "action", value: "query"), .init(name: "list", value: "search"),
            .init(name: "srsearch", value: topic), .init(name: "srlimit", value: "1"), .init(name: "format", value: "json"),
        ]
        guard let searchURL = search.url,
              let found = await json(searchURL),
              let title = ((found["query"] as? [String: Any])?["search"] as? [[String: Any]])?.first?["title"] as? String
        else { return nil }
        var extract = URLComponents(string: "https://\(host)/w/api.php")!
        extract.queryItems = [
            .init(name: "action", value: "query"), .init(name: "prop", value: "extracts"),
            .init(name: "explaintext", value: "1"), .init(name: "exchars", value: "6000"),
            .init(name: "titles", value: title), .init(name: "format", value: "json"),
        ]
        guard let extractURL = extract.url,
              let page = await json(extractURL),
              let pages = (page["query"] as? [String: Any])?["pages"] as? [String: Any],
              let first = pages.values.first as? [String: Any],
              let text = first["extract"] as? String, text.count > 200
        else { return nil }
        return (title, text)
    }

    private nonisolated static func json(_ url: URL) async -> [String: Any]? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        // Wikipedia asks API clients to say who they are.
        request.setValue("Hatchling/0.5 (macOS notch companion; https://github.com/MikaelDDavidd/hatchling)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
