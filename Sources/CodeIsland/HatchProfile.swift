import AppKit
import os.log
import CodeIslandCore

// MARK: - What Hatch knows about you
//
// A small profile in `profile.json` (Application Support/Hatchling), readable and editable:
// your name, profession and areas, the technologies you use, city and country, club and
// national team, the series, films, games and music you like, a birthday.
//
// Three sources, kept apart in the file:
//  - `guessed`: worked out on the Mac (account name, region, the manifest files of the
//    projects you open). Recomputed as they change.
//  - `heard`: things you said to the agents, picked out by the AI (and football clubs by
//    name, on the Mac). Each new mention bumps `seen`.
//  - `told`: what you typed in Settings. Always wins.
//
// On the first run it reads what you typed in the Claude Code conversations of the last
// month (`~/.claude/projects`), only your own messages, so it doesn't start from nothing.
// What leaves the Mac: those messages go to the AI provider you chose, to pick out facts.
// Turned off with the "learn about me" setting; the file stays and you can edit it.

enum ProfileSlot: String, Codable, CaseIterable, Identifiable {
    case name, profession, area, technology, city, country, birthday
    case club, nationalTeam, sport
    case series, film, book, game, music, hobby, food
    case fact

    var id: String { rawValue }

    /// Slots that hold one answer; the strongest value is the one used.
    var single: Bool {
        switch self {
        case .name, .profession, .city, .country, .birthday, .club, .nationalTeam: return true
        default: return false
        }
    }

    /// Worth a Wikipedia curiosity.
    var curious: Bool {
        switch self {
        case .club, .nationalTeam, .sport, .series, .film, .book, .game, .music, .hobby, .technology: return true
        default: return false
        }
    }

    /// Worth saying "I noted that" out loud when learned.
    var announce: Bool {
        switch self {
        case .technology, .area, .country, .name: return false
        default: return true
        }
    }

    func label(pt: Bool) -> String {
        switch self {
        case .name: return pt ? "Como te chamar" : "What to call you"
        case .profession: return pt ? "Profissão" : "Profession"
        case .area: return pt ? "Áreas" : "Areas"
        case .technology: return pt ? "Tecnologias" : "Technologies"
        case .city: return pt ? "Cidade" : "City"
        case .country: return pt ? "País" : "Country"
        case .birthday: return pt ? "Aniversário (dia/mês)" : "Birthday (day/month)"
        case .club: return pt ? "Time do coração" : "Football club"
        case .nationalTeam: return pt ? "Seleção" : "National team"
        case .sport: return pt ? "Esportes" : "Sports"
        case .series: return pt ? "Séries" : "Series"
        case .film: return pt ? "Filmes" : "Films"
        case .book: return pt ? "Livros" : "Books"
        case .game: return pt ? "Jogos" : "Games"
        case .music: return pt ? "Música" : "Music"
        case .hobby: return pt ? "Hobbies" : "Hobbies"
        case .food: return pt ? "Comidas" : "Food"
        case .fact: return pt ? "Outras coisas" : "Other things"
        }
    }

    /// How the AI names this slot in its answer.
    var aiKind: String {
        switch self {
        case .nationalTeam: return "national_team"
        case .name: return "nickname"
        default: return rawValue
        }
    }
}

struct ProfileFact: Codable, Identifiable, Hashable {
    enum Source: String, Codable { case guessed, heard, told }

    var slot: ProfileSlot
    var value: String
    var source: Source
    var seen: Int
    var firstSeen: Date
    var lastSeen: Date

    var id: String { ProfileFact.key(slot, value) }
    static func key(_ slot: ProfileSlot, _ value: String) -> String {
        slot.rawValue + ":" + value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}

private struct ProfileFile: Codable {
    var version = 1
    var facts: [ProfileFact] = []
    /// Facts you removed, so a guess doesn't come back.
    var dismissed: [String] = []
}

@MainActor
final class HatchProfile: ObservableObject {
    static let shared = HatchProfile()

    @Published private(set) var facts: [ProfileFact] = []
    private var dismissed: Set<String> = []
    private var fileDate: Date?
    @Published private(set) var learning = false
    private var lastLearn = Date.distantPast
    /// Facts heard for the first time, for Hatch to mention.
    private(set) var news: [ProfileFact] = []
    /// What the first read of past conversations found, said in one go.
    private var digest: [String]?

    static let log = Logger(subsystem: "dev.mikaeldavid.hatchling", category: "Profile")
    static var fileURL: URL { HatchlingData.directory.appendingPathComponent("profile.json") }
    private static let heardKey = "hatchProfileHeard"          // hashes of messages already read
    private static let projectsKey = "hatchProfileProjects"    // folders whose technologies were counted
    private static let bootstrapKey = "hatchProfileBootstrapped"

    private var pt: Bool { L10n.shared.effectiveLanguage == "pt" }

    var learns: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.hatchLearns) as? Bool ?? SettingsDefaults.hatchLearns
    }

    private init() { load() }

    // MARK: Reading it

    /// The strongest value of a slot: what you told, else the most mentioned, else the newest.
    func value(_ slot: ProfileSlot) -> String? { values(slot).first }

    func values(_ slot: ProfileSlot) -> [String] {
        facts.filter { $0.slot == slot }.sorted(by: Self.stronger).map(\.value)
    }

    private static func stronger(_ a: ProfileFact, _ b: ProfileFact) -> Bool {
        let rank: (ProfileFact.Source) -> Int = { $0 == .told ? 2 : ($0 == .heard ? 1 : 0) }
        if rank(a.source) != rank(b.source) { return rank(a.source) > rank(b.source) }
        if a.seen != b.seen { return a.seen > b.seen }
        return a.lastSeen > b.lastSeen
    }

    /// The name to use: a nickname you gave, else the first name of the Mac account.
    var callName: String? { value(.name) }

    /// Topics for curiosities: the things you like, your teams and your technologies, each
    /// with what to search for on Wikipedia ("Swift" alone finds the singer).
    func curiosityTopics(pt: Bool) -> (likes: [(topic: String, query: String)], techs: [(topic: String, query: String)]) {
        func hint(_ slot: ProfileSlot) -> String {
            switch slot {
            case .club: return pt ? " clube de futebol" : " football club"
            case .series: return pt ? " série de televisão" : " TV series"
            case .film: return pt ? " filme" : " film"
            case .book: return pt ? " livro" : " novel"
            case .game: return pt ? " jogo eletrônico" : " video game"
            case .technology: return pt ? " linguagem de programação software" : " programming software"
            default: return ""
            }
        }
        var likes: [(String, String)] = []
        var techs: [(String, String)] = []
        for slot in ProfileSlot.allCases where slot.curious {
            for value in values(slot).prefix(slot.single ? 1 : 4) {
                if slot == .technology { techs.append((value, value + hint(slot))) } else { likes.append((value, value + hint(slot))) }
            }
        }
        return (likes, techs)
    }

    /// A line for the AI on who the developer is, used to colour Hatch's musings.
    var summaryForAI: String? {
        let parts: [String] = [
            value(.profession).map { "works as \($0)" },
            values(.technology).prefix(3).joined(separator: ", ").nilIfEmpty.map { "uses \($0)" },
            value(.city).map { "lives in \($0)" },
            value(.club).map { "supports \($0)" },
            values(.series).prefix(2).joined(separator: ", ").nilIfEmpty.map { "watches \($0)" },
            values(.game).prefix(2).joined(separator: ", ").nilIfEmpty.map { "plays \($0)" },
            values(.music).prefix(2).joined(separator: ", ").nilIfEmpty.map { "listens to \($0)" },
            values(.hobby).prefix(2).joined(separator: ", ").nilIfEmpty.map { "enjoys \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    func isBirthday(_ date: Date = Date()) -> Bool {
        guard let raw = value(.birthday) else { return false }
        let nums = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard nums.count >= 2 else { return false }
        let c = Calendar.current.dateComponents([.day, .month], from: date)
        return c.day == nums[0] && c.month == nums[1]
    }

    func takeDigest() -> [String]? {
        defer { digest = nil }
        return digest
    }

    /// The next fact to mention, once.
    func takeNews() -> ProfileFact? {
        guard !news.isEmpty else { return nil }
        return news.removeFirst()
    }

    // MARK: Changing it

    func tell(_ slot: ProfileSlot, _ value: String) {
        let clean = Self.clean(value)
        guard !clean.isEmpty else { return }
        dismissed.remove(ProfileFact.key(slot, clean))
        if slot.single { facts.removeAll { $0.slot == slot && $0.source == .told } }
        upsert(slot, clean, source: .told)
        save()
    }

    func remove(_ fact: ProfileFact) {
        facts.removeAll { $0.id == fact.id }
        news.removeAll { $0.id == fact.id }
        dismissed.insert(fact.id)
        save()
    }

    func forgetEverything() {
        facts = []
        news = []
        digest = nil
        dismissed = []
        HatchlingData.defaults.removeObject(forKey: Self.heardKey)
        HatchlingData.defaults.removeObject(forKey: Self.projectsKey)
        HatchlingData.defaults.removeObject(forKey: Self.bootstrapKey)
        save()
        refreshGuesses(folders: [])
    }

    /// Reads the past conversations again, as on the first run.
    func readAgain() {
        HatchlingData.defaults.removeObject(forKey: Self.heardKey)
        HatchlingData.defaults.removeObject(forKey: Self.bootstrapKey)
        tick(sessions: [])
    }

    func revealFile() {
        save()
        NSWorkspace.shared.activateFileViewerSelecting([Self.fileURL])
    }

    // MARK: Learning

    /// Called every minute by the companion. Cheap when there is nothing new.
    func tick(sessions: [SessionSnapshot], force: Bool = false) {
        reloadIfEdited()
        refreshGuesses(folders: sessions.compactMap(\.cwd))
        guard learns, !learning else { return }

        if !HatchlingData.defaults.bool(forKey: Self.bootstrapKey) {
            learning = true
            HatchlingData.defaults.set(true, forKey: Self.bootstrapKey)
            Task { [weak self] in
                let (messages, folders) = await Task.detached(priority: .utility) { Self.pastMessages() }.value
                guard let self else { return }
                self.refreshGuesses(folders: folders)
                await self.learn(from: messages, projects: Self.projectNames(folders), quietly: true)
                self.learning = false
            }
            return
        }

        let fresh = Self.unread(sessions.flatMap { s in
            s.recentMessages.filter(\.isUser).map(\.text) + [s.lastUserPrompt ?? ""]
        })
        let due = force || (fresh.count >= 8) || (!fresh.isEmpty && Date().timeIntervalSince(lastLearn) > 2 * 3600)
        guard due, !fresh.isEmpty else { return }
        learning = true
        Task { [weak self] in
            guard let self else { return }
            await self.learn(from: fresh, projects: sessions.map(\.projectDisplayName), quietly: false)
            self.learning = false
        }
    }

    private func learn(from messages: [String], projects: [String], quietly: Bool) async {
        lastLearn = Date()
        let before = Set(facts.map(\.id))
        // Clubs are spotted on the Mac by name: small models miss a club said in passing.
        for club in Self.clubs(in: messages) { upsert(.club, club, source: .heard) }
        if AIText.isAvailable {
            // In batches, so a small model keeps its attention on each message.
            for batch in stride(from: 0, to: messages.count, by: 25).map({ Array(messages[$0..<min($0 + 25, messages.count)]) }) {
                let found = await Self.extract(from: batch, projects: projects)
                for (slot, value) in found { upsert(slot, value, source: .heard) }
            }
        }
        Self.markRead(messages)
        trim()
        save()
        let learned = facts.filter { !before.contains($0.id) && $0.source == .heard && $0.slot.announce }
        Self.log.notice("learned \(learned.count) new facts from \(messages.count) messages")
        if quietly {
            // After reading old conversations, one remark sums it up instead of many.
            // Tastes first: they make the better remark.
            if !learned.isEmpty {
                digest = learned.sorted { ($0.slot != .fact ? 1 : 0, $0.seen) > ($1.slot != .fact ? 1 : 0, $1.seen) }.prefix(3).map(\.value)
            }
        } else {
            news.append(contentsOf: learned.prefix(2))
        }
    }

    /// Facts the developer reveals about themselves, as (slot, value).
    private static func extract(from messages: [String], projects: [String]) async -> [(ProfileSlot, String)] {
        let sample = messages.map { String($0.prefix(400)) }.joined(separator: "\n---\n")
        let system = """
        You read messages a developer typed to AI coding assistants. Pick out facts the developer reveals about \
        THEMSELVES: never about the software they are building, its features, clients or users, and never about \
        other people's tastes.
        Kinds:
        nickname: what they like to be called
        profession: their specific job or role (skip a plain "developer")
        city, country: where they live
        birthday: day/month
        club: football club they support
        national_team: national team they support
        sport: a sport they play or follow
        series, film, book: titles they watch or read (a saga or franchise counts as book or film)
        game: a video game or board game they play
        music: a band, singer or genre they listen to
        hobby: something they do for fun away from the computer
        food: a food or drink they like
        fact: another short personal fact (pet, family, studies)
        Never list operating systems, devices, apps, stores, websites or programming tools as tastes. Never list money, \
        income, debts, health, addresses, phone numbers, documents or passwords.
        List every such fact, even one said in passing or as a joke, but only what is clearly said. One per line as \
        kind: value, values short (1 to 5 words), names written as usual, in the language of the messages. Nothing \
        else. If there is nothing, reply NONE.
        Example input: vou parar que o jogo do Palmeiras vai começar --- bora fechar antes do episódio de The Office
        Example output:
        club: Palmeiras
        series: The Office
        """
        guard let answer = await AIText.complete(system: system, user: sample, maxTokens: 220, timeout: 45, temperature: 0.1, careful: true)
        else { return [] }
        let kinds = Dictionary(uniqueKeysWithValues: ProfileSlot.allCases.map { ($0.aiKind, $0) })
        let blocked = Set(projects.map { $0.lowercased() })
        return answer.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { return nil }
            let kind = parts[0].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-•* "))
            guard let slot = kinds[kind], slot != .technology, slot != .area else { return nil }
            let value = clean(parts[1])
            guard !value.isEmpty, value.uppercased() != "NONE", value.count <= (slot == .fact ? 60 : 40),
                  !blocked.contains(value.lowercased()), !sensitive(value), !(slot == .profession && generic(value)),
                  !(slot != .fact && tool(value)), !(slot == .fact && (negative(value) || mentionsTool(value))),
                  !isOwnName(value) || slot == .name else { return nil }
            return (slot, value)
        }
    }

    /// Money, health and the like stay out of the profile even when the AI lets them through.
    nonisolated static func sensitive(_ value: String) -> Bool {
        let v = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let words = ["r$", "us$", "$", "reais", "salario", "ganho", "ganha", "renda", "divida", "mil por", "k por mes",
                     "senha", "password", "cpf", "rg ", "cartao", "doenca", "remedio", "telefone", "endereco", "@"]
        return words.contains { v.contains($0) }
    }

    /// "Uses a Mac": a tool, not a fact about the person.
    nonisolated static func mentionsTool(_ value: String) -> Bool {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { !$0.isLetter }).contains { tool(String($0)) }
    }

    /// The account's own name, which the AI sometimes files as a fact.
    nonisolated static func isOwnName(_ value: String) -> Bool {
        let fold = { (t: String) in t.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }
        let full = fold(NSFullUserName())
        return !full.isEmpty && (fold(value) == full || full.split(separator: " ").contains { fold(value) == $0 })
    }

    /// "Doesn't have two Steam accounts" says nothing about the person.
    nonisolated static func negative(_ value: String) -> Bool {
        let v = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return ["nao ", "not ", "no ", "nunca ", "never ", "sem "].contains { v.hasPrefix($0) }
            || ["steam", "conta", "account", "app", "site", "projeto", "project"].contains { v.contains($0) }
    }

    nonisolated static func generic(_ value: String) -> Bool {
        let v = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return ["developer", "dev", "programador", "programadora", "desenvolvedor", "desenvolvedora", "programmer",
                "software developer", "engineer", "engenheiro"].contains(v)
    }

    /// Computers and software, which the small models keep filing as hobbies.
    nonisolated static func tool(_ value: String) -> Bool {
        let v = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return ["linux", "mac", "macos", "macbook", "windows", "steam", "iphone", "ipad", "android", "github", "gitlab",
                "docker", "vscode", "vs code", "xcode", "claude", "claude code", "chatgpt", "terminal", "notion", "figma",
                "whatsapp", "instagram", "tiktok", "youtube", "google", "apple", "programacao", "programming", "codigo",
                "code", "ia", "ai"].contains(v)
    }

    private func upsert(_ slot: ProfileSlot, _ value: String, source: ProfileFact.Source) {
        let key = ProfileFact.key(slot, value)
        guard source == .told || !dismissed.contains(key) else { return }
        let now = Date()
        if let i = facts.firstIndex(where: { $0.id == key }) {
            if source == .heard { facts[i].seen += 1 }
            if source == .told { facts[i].source = .told }
            facts[i].lastSeen = now
        } else {
            facts.append(ProfileFact(slot: slot, value: value, source: source, seen: 1, firstSeen: now, lastSeen: now))
        }
    }

    /// Heard once and not again in a month: probably noise. Few values per slot.
    private func trim() {
        let now = Date()
        facts.removeAll { $0.source == .heard && $0.seen == 1 && now.timeIntervalSince($0.lastSeen) > 30 * 86400 }
        for slot in ProfileSlot.allCases {
            let kept = facts.filter { $0.slot == slot }.sorted(by: Self.stronger)
            let limit = slot == .fact ? 12 : (slot.single ? 4 : 8)
            guard kept.count > limit else { continue }
            let drop = Set(kept.dropFirst(limit).filter { $0.source != .told }.map(\.id))
            facts.removeAll { drop.contains($0.id) }
        }
    }

    // MARK: Guesses from the Mac

    /// Name, country, national team, technologies of the projects you open, and from them
    /// your areas and profession. Recomputed; facts you removed stay removed.
    private func refreshGuesses(folders: [String]) {
        var changed = false
        func guess(_ slot: ProfileSlot, _ value: String?) {
            guard let value, !value.isEmpty, !dismissed.contains(ProfileFact.key(slot, value)),
                  !facts.contains(where: { $0.id == ProfileFact.key(slot, value) }) else { return }
            facts.removeAll { $0.slot == slot && $0.source == .guessed && slot.single }
            upsert(slot, value, source: .guessed)
            changed = true
        }

        guess(.name, NSFullUserName().split(separator: " ").first.map(String.init))
        let region = Locale.current.region?.identifier
        guess(.country, region.flatMap { Locale(identifier: pt ? "pt_BR" : "en_US").localizedString(forRegionCode: $0) })
        guess(.nationalTeam, region.flatMap { Self.nationalTeams(pt: pt)[$0] })

        // Technologies: counted once per project folder.
        var counted = Set(HatchlingData.defaults.stringArray(forKey: Self.projectsKey) ?? [])
        for folder in Set(folders) where !counted.contains(folder) {
            counted.insert(folder)
            for tech in Self.technologies(in: folder) {
                let key = ProfileFact.key(.technology, tech)
                if let i = facts.firstIndex(where: { $0.id == key }) { facts[i].seen += 1; facts[i].lastSeen = Date() }
                else { guess(.technology, tech) }
                changed = true
            }
        }
        if counted.count != (HatchlingData.defaults.stringArray(forKey: Self.projectsKey) ?? []).count {
            HatchlingData.defaults.set(Array(counted.suffix(300)), forKey: Self.projectsKey)
        }

        // Areas and profession follow from the technologies.
        let areas = Self.areas(for: values(.technology), pt: pt).filter { !dismissed.contains(ProfileFact.key(.area, $0)) }
        let guessedAreas = Set(facts.filter { $0.slot == .area && $0.source == .guessed }.map(\.value))
        if Set(areas) != guessedAreas {
            facts.removeAll { $0.slot == .area && $0.source == .guessed }
            for area in areas { guess(.area, area) }
            changed = true
        }
        let hasOwnProfession = facts.contains { $0.slot == .profession && $0.source != .guessed }
        if !hasOwnProfession, let profession = Self.profession(for: areas, hasTech: !values(.technology).isEmpty, pt: pt),
           value(.profession) != profession {
            guess(.profession, profession)
        }
        if changed { save() }
    }

    /// The technologies of a project, from the files at its root; for a monorepo with none
    /// there, from the folders one or two levels in (apps/*, packages/*).
    nonisolated static func technologies(in folder: String) -> [String] {
        let here = technologies(at: folder)
        guard here.isEmpty else { return here }
        let fm = FileManager.default
        var inner: [String] = []
        let skip: Set<String> = ["node_modules", "build", "dist", "Pods", "ios", "android", "macos", "web", "linux", "windows"]
        func children(_ path: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: path)) ?? [])
                .filter { !$0.hasPrefix(".") && !skip.contains($0) }
                .map { (path as NSString).appendingPathComponent($0) }
                .filter { var dir: ObjCBool = false; return fm.fileExists(atPath: $0, isDirectory: &dir) && dir.boolValue }
        }
        for child in children(folder).prefix(30) {
            inner += technologies(at: child)
            if ["apps", "packages", "services"].contains((child as NSString).lastPathComponent) {
                for grandchild in children(child).prefix(20) { inner += technologies(at: grandchild) }
            }
        }
        var seen = Set<String>()
        return inner.filter { seen.insert($0).inserted }
    }

    private nonisolated static func technologies(at folder: String) -> [String] {
        var found: [String] = []
        let fm = FileManager.default
        func path(_ name: String) -> String { (folder as NSString).appendingPathComponent(name) }
        func has(_ name: String) -> Bool { fm.fileExists(atPath: path(name)) }
        if has("Package.swift") || has("Podfile") { found.append("Swift") }
        if has("pubspec.yaml") { found.append("Flutter") }
        if has("Cargo.toml") { found.append("Rust") }
        if has("go.mod") { found.append("Go") }
        if has("requirements.txt") || has("pyproject.toml") { found.append("Python") }
        if has("Gemfile") { found.append("Ruby") }
        if has("composer.json") { found.append("PHP") }
        if has("pom.xml") { found.append("Java") }
        if has("build.gradle.kts") || has("build.gradle") { found.append("Kotlin") }
        if has("docker-compose.yml") || has("Dockerfile") { found.append("Docker") }
        if has("package.json"), let data = fm.contents(atPath: path("package.json")),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let deps = ((json["dependencies"] as? [String: Any]) ?? [:]).merging((json["devDependencies"] as? [String: Any]) ?? [:]) { a, _ in a }
            let before = found.count
            if deps["next"] != nil { found.append("Next.js") }
            else if deps["react"] != nil { found.append("React") }
            if deps["react-native"] != nil || deps["expo"] != nil { found.append("React Native") }
            if deps["vue"] != nil { found.append("Vue.js") }
            if deps["@angular/core"] != nil { found.append("Angular") }
            if deps["svelte"] != nil { found.append("Svelte") }
            if deps["@nestjs/core"] != nil { found.append("NestJS") }
            else if deps["express"] != nil || deps["fastify"] != nil { found.append("Node.js") }
            if deps["typescript"] != nil { found.append("TypeScript") }
            if found.count == before { found.append("JavaScript") }
        }
        return found
    }

    nonisolated static func areas(for techs: [String], pt: Bool) -> [String] {
        let t = Set(techs)
        var areas: [String] = []
        if !t.isDisjoint(with: ["Flutter", "Swift", "Kotlin", "React Native"]) { areas.append("Mobile") }
        if !t.isDisjoint(with: ["React", "Next.js", "Vue.js", "Angular", "Svelte"]) { areas.append("Front-end") }
        if !t.isDisjoint(with: ["Node.js", "NestJS", "Go", "Python", "Ruby", "PHP", "Java", "Rust", "Next.js"]) { areas.append("Back-end") }
        if t.contains("Docker") { areas.append("DevOps") }
        return areas
    }

    nonisolated static func profession(for areas: [String], hasTech: Bool, pt: Bool) -> String? {
        guard hasTech else { return nil }
        let a = Set(areas)
        if a.contains("Mobile") && (a.contains("Back-end") || a.contains("Front-end")) || (a.contains("Front-end") && a.contains("Back-end")) {
            return pt ? "Dev full stack" : "Full-stack developer"
        }
        if a.contains("Mobile") { return pt ? "Dev mobile" : "Mobile developer" }
        if a.contains("Front-end") { return pt ? "Dev front-end" : "Front-end developer" }
        if a.contains("Back-end") { return pt ? "Dev back-end" : "Back-end developer" }
        return pt ? "Dev de software" : "Software developer"
    }

    nonisolated static func nationalTeams(pt: Bool) -> [String: String] {
        pt ? ["BR": "Seleção Brasileira", "PT": "Seleção Portuguesa", "AR": "Seleção Argentina", "US": "Seleção dos Estados Unidos",
              "ES": "Seleção Espanhola", "FR": "Seleção Francesa", "DE": "Seleção Alemã", "IT": "Seleção Italiana",
              "GB": "Seleção Inglesa", "MX": "Seleção Mexicana", "UY": "Seleção Uruguaia", "CO": "Seleção Colombiana",
              "CL": "Seleção Chilena", "AO": "Seleção Angolana", "MZ": "Seleção Moçambicana", "TR": "Seleção Turca", "JP": "Seleção Japonesa"]
           : ["BR": "Brazil national football team", "PT": "Portugal national football team", "AR": "Argentina national football team",
              "US": "United States men's national soccer team", "ES": "Spain national football team", "FR": "France national football team",
              "DE": "Germany national football team", "IT": "Italy national football team", "GB": "England national football team",
              "MX": "Mexico national football team", "UY": "Uruguay national football team", "CO": "Colombia national football team",
              "TR": "Turkey national football team", "JP": "Japan national football team"]
    }

    /// Clubs named in the messages. Whole words, ignoring case and accents, and only names
    /// with no everyday meaning ("internacional", "santos", "galo" or "bahia" would fire on
    /// ordinary sentences).
    nonisolated static func clubs(in messages: [String]) -> [String] {
        let table: [(String, String)] = [
            ("flamengo", "Flamengo"), ("mengao", "Flamengo"), ("vasco", "Vasco"), ("corinthians", "Corinthians"),
            ("timao", "Corinthians"), ("palmeiras", "Palmeiras"), ("verdao", "Palmeiras"), ("fluminense", "Fluminense"),
            ("botafogo", "Botafogo"), ("gremio", "Grêmio"), ("atletico mineiro", "Atlético Mineiro"),
            ("athletico paranaense", "Athletico Paranaense"), ("sport recife", "Sport Recife"), ("real madrid", "Real Madrid"),
        ]
        let text = messages.joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        var found: [String] = []
        for (name, club) in table where !found.contains(club) {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\b"
            if text.range(of: pattern, options: .regularExpression) != nil { found.append(club) }
        }
        return found
    }

    // MARK: Messages

    /// Your own words: no pasted blocks, no tags, no long pastes, nothing already read.
    private static func unread(_ texts: [String]) -> [String] {
        let read = Set(HatchlingData.defaults.stringArray(forKey: heardKey) ?? [])
        var seen = Set<String>()
        return texts.compactMap(ownWords).filter { text in
            let h = hash(text)
            return !read.contains(h) && seen.insert(h).inserted
        }
    }

    nonisolated static func ownWords(_ raw: String) -> String? {
        var text = raw
        // Drop pasted material: it is someone else's text.
        while let start = text.range(of: "<pasted_content"),
              let end = text.range(of: "</pasted_content>", range: start.upperBound..<text.endIndex) {
            text.removeSubrange(start.lowerBound..<end.upperBound)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3, text.count <= 1200, !text.hasPrefix("<"), !text.hasPrefix("[SYSTEM"),
              !text.hasPrefix("[Request interrupted"), !text.hasPrefix("Caveat:") else { return nil }
        return text
    }

    private static func markRead(_ texts: [String]) {
        var read = HatchlingData.defaults.stringArray(forKey: heardKey) ?? []
        read.append(contentsOf: texts.map(hash))
        HatchlingData.defaults.set(Array(read.suffix(800)), forKey: heardKey)
    }

    nonisolated private static func hash(_ text: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in text.utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return String(h, radix: 36)
    }

    private static func projectNames(_ folders: [String]) -> [String] {
        folders.map { ($0 as NSString).lastPathComponent }
    }

    /// What you typed in the Claude Code conversations of the last month, newest first, and
    /// the folders they ran in. Reads only the end of each file.
    nonisolated static func pastMessages() -> ([String], [String]) {
        let root = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return ([], []) }
        let cutoff = Date().addingTimeInterval(-30 * 86400)
        var files: [(URL, Date)] = []
        for dir in dirs {
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }
            for url in items where url.pathExtension == "jsonl" {
                let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if date > cutoff { files.append((url, date)) }
            }
        }
        var messages: [String] = []
        var folders = Set<String>()
        var seen = Set<String>()
        for (url, _) in files.sorted(by: { $0.1 > $1.1 }).prefix(60) {
            guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? handle.close() }
            let size = (try? handle.seekToEnd()) ?? 0
            try? handle.seek(toOffset: size > 1_500_000 ? size - 1_500_000 : 0)
            guard let data = try? handle.readToEnd(), let text = String(data: data, encoding: .utf8) else { continue }
            var fromFile = 0
            for line in text.split(separator: "\n").reversed() where line.contains("\"type\":\"user\"") {
                guard fromFile < 12,
                      let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      json["isSidechain"] as? Bool != true, json["isMeta"] as? Bool != true,
                      json["isCompactSummary"] as? Bool != true,
                      (json["userType"] as? String ?? "external") == "external",
                      let message = json["message"] as? [String: Any] else { continue }
                if let cwd = json["cwd"] as? String { folders.insert(cwd) }
                let content: String
                if let s = message["content"] as? String { content = s }
                else if let blocks = message["content"] as? [[String: Any]] {
                    content = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                } else { continue }
                guard let own = ownWords(content), seen.insert(hash(own)).inserted else { continue }
                messages.append(own)
                fromFile += 1
            }
            if messages.count >= 240 { break }
        }
        return (messages, Array(folders))
    }

    // MARK: The file

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(ProfileFile.self, from: data) else {
            Self.log.error("profile.json could not be read; keeping it as it is")
            return
        }
        facts = file.facts
        dismissed = Set(file.dismissed)
        fileDate = Self.modified()
    }

    /// You can edit the file by hand; pick the changes up.
    private func reloadIfEdited() {
        guard let date = Self.modified(), date != fileDate else { return }
        load()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let file = ProfileFile(facts: facts.sorted { ($0.slot.rawValue, $0.value) < ($1.slot.rawValue, $1.value) },
                               dismissed: dismissed.sorted())
        guard let data = try? encoder.encode(file) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
        fileDate = Self.modified()
    }

    private static func modified() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    nonisolated static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'.-•*“”")))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
