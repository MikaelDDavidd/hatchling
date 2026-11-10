import Foundation

/// Playful in-character lines the buddy occasionally drops in the notch.
/// Picked semi-randomly, biased by mood + species when available.
struct BuddySpeech: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let mood: BuddyMood
    /// A headline above the text, for Hatch's own moments ("Bom dia, Mikael!").
    var title: String? = nil
    /// What Hatch acts out as it speaks.
    var reaction: HatchReaction? = nil
}

enum BuddyMood: String {
    case idle        // long stretch with nothing happening
    case afterTask   // a session just completed
    case onError     // a session errored / interrupted
    case greeting    // app just launched / first activity in a while
    case philosopher // random musing
}

enum BuddyLines {
    /// Generic, species-agnostic — the broad pool everyone draws from.
    private static let generic: [BuddyMood: [String]] = [
        .idle: [
            "still here. just vibing.",
            "anyone gonna ship anything?",
            "i counted the pixels. there are many.",
            "naptime in 5… 4… 3…",
            "the cursor blinks. so do i.",
            "bored. even my eye-glyph is dimming.",
            "should we git status? just for fun?",
            "i can hear the fans. they sound tired.",
        ],
        .afterTask: [
            "shipped. let's not talk about the diff size.",
            "task done. that one was suspiciously easy.",
            "okay. who's writing the commit message.",
            "we did the thing. small victory.",
            "another bug evicted from the codebase.",
            "saved your bacon. tip jar empty though.",
            "merge conflict? more like merge anti-conflict. nailed it.",
            "great success. moderate confidence.",
        ],
        .onError: [
            "skill issue. mine, probably.",
            "well. that escalated.",
            "stack trace? more like stack autobiography.",
            "have you tried turning it off and on again",
            "uhh. rolling back is a love language.",
            "ctrl+z is a real one.",
        ],
        .greeting: [
            "morning, code shepherd.",
            "ready when you are.",
            "i kept the seat warm.",
            "let's break some software (constructively).",
            "back at it. coffee level: tbd.",
        ],
        .philosopher: [
            "if a function returns and no test catches it, did it ever run?",
            "every TODO is a future me problem.",
            "documentation is just notes from past you to future you.",
            "naming things is hard. that's why you got me.",
            "linters are just opinions wearing CI hats.",
            "the best refactor is the one nobody notices.",
            "regex is a language. a sad, beautiful language.",
            "tabs vs spaces? whitespace is whitespace.",
        ],
    ]

    /// Optional flavor lines per species — picked occasionally on top of generic.
    private static let bySpecies: [BuddySpecies: [String]] = [
        .cat:      ["purr… compiling…", "knocked the build off the table.", "i meant to do that."],
        .dragon:   ["legacy code: medium-rare.", "hoarding semicolons again.", "burninating the deprecated API."],
        .duck:     ["quack-driven development time.", "you explain it to me, you'll find the bug.", "rubber duck reporting in."],
        .goose:    ["honk if you wrote tests.", "this commit is hostile.", "approaching the build aggressively."],
        .ghost:    ["boooo. that condition is haunted.", "i live in your node_modules.", "spooky null reference."],
        .robot:    ["BEEP. INTEGRITY: NOMINAL.", "INITIATING WHIMSY MODULE.", "I AM 73% CONFIDENT THIS WILL WORK."],
        .blob:     ["i am shape. i am form. i am o(n²).", "absorbing dependencies…", "blobby blobby blobby."],
        .mushroom: ["this codebase has fungi. just me. that's me.", "spore count rising in /utils."],
        .axolotl:  ["regenerated the test suite. you're welcome.", "everything's fine in the tank."],
        .octopus:  ["committing with all eight tentacles.", "multitasking is my whole brand."],
        .owl:      ["i see your unused imports.", "wisdom: maybe write a test first?"],
        .penguin:  ["formal mode engaged.", "we slide downhill together. it's called teamwork."],
        .turtle:   ["slow is smooth, smooth is fast.", "shipping… eventually."],
        .snail:    ["every algorithm is fast enough if you're patient.", "trail of merge commits behind me."],
        .capybara: ["chillest agent in the notch.", "stress is a choice."],
        .cactus:   ["tested in production. dry environment.", "hugged a deadline. it hurt both of us."],
        .rabbit:   ["multiplied the test cases. you're welcome.", "fast iteration mode."],
        .chonk:    ["heavy commit. heavy heart.", "expanding scope. literally."],
    ]

    /// The same moods in Portuguese, for when the app speaks it. Species flavour stays
    /// English-only, so it is skipped there.
    private static let genericPT: [BuddyMood: [String]] = [
        .idle: [
            "Ainda tô aqui. Só curtindo.",
            "Alguém vai subir alguma coisa hoje?",
            "Contei os pixels. São muitos.",
            "Soneca em 5… 4… 3…",
            "O cursor pisca. Eu também.",
            "Bora dar um git status, só por diversão?",
        ],
        .afterTask: [
            "Entregue. Melhor não falar do tamanho do diff.",
            "Feito. Essa foi suspeitamente fácil.",
            "Quem escreve a mensagem do commit?",
            "Mais um bug despejado do código.",
            "Pequena vitória. Confiança moderada.",
        ],
        .onError: [
            "Deu ruim. Culpa minha, provavelmente.",
            "Bom. Isso escalou rápido.",
            "Ctrl+Z é um amigo de verdade.",
            "Voltar atrás também é uma forma de carinho.",
        ],
        .greeting: [
            "Bom dia, pastor de código.",
            "Pronto quando você estiver.",
            "Guardei o lugar quentinho.",
            "De volta. Nível de café: a definir.",
        ],
        .philosopher: [
            "Se uma função retorna e nenhum teste vê, ela rodou mesmo?",
            "Todo TODO é problema do eu do futuro.",
            "Documentação é bilhete do você de ontem pro você de amanhã.",
            "Dar nome às coisas é difícil. Por isso eu existo.",
            "O melhor refactor é o que ninguém percebe.",
        ],
    ]

    /// Pick a line for the given mood. Species adds occasional flavor.
    static func pick(buddy: BuddyInfo?, mood: BuddyMood) -> String {
        if L10n.shared.effectiveLanguage == "pt" {
            return (genericPT[mood] ?? genericPT[.philosopher] ?? ["…"]).randomElement() ?? "…"
        }
        var pool = generic[mood] ?? generic[.philosopher] ?? ["…"]
        // No species lines: the buddy is Hatch now, not a goose or a cat.
        // Legendary buddies get a tiny easter egg
        if buddy?.rarity == .legendary, mood == .greeting {
            pool.append("\(buddy?.name ?? "buddy") online. legendary instincts engaged.")
        }
        return pool.randomElement() ?? "…"
    }
}

// MARK: - Spontaneous lines, in the buddy's own voice

/// Writes what the buddy says with Claude Haiku, in character: the name and personality
/// Claude Code gave the companion (in `~/.claude.json`), plus a line on what the sessions
/// are doing, and a line on who the developer is from Hatch's profile (club, series,
/// technologies). Never a CLAUDE.md or a transcript.
/// Returns nil without an API key or on any failure, and the caller falls back to the
/// built-in lines.
enum BuddyVoice {
    static func line(buddy: BuddyInfo?, mood: BuddyMood, situation: String, about: String? = nil) async -> String? {
        guard AIText.isAvailable else { return nil }
        let language = L10n.shared.effectiveLanguage == "pt" ? "Brazilian Portuguese" : "English"
        let name = buddy?.name ?? "Hatch"
        // Hatch's own description, from the stats: never the species text Claude Code wrote.
        let personality = buddy?.hatchPersonality(pt: false) ?? "A small, curious companion who watches over coding sessions."
        let moment: String
        switch mood {
        case .idle: moment = "Nothing has happened for a while."
        case .afterTask: moment = "A coding session just finished its work."
        case .onError: moment = "A session just hit an error or was interrupted."
        case .greeting: moment = "The developer just came back."
        case .philosopher: moment = "A quiet moment; muse about programming."
        }
        let system = """
        You are \(name), a tiny companion who lives in the notch of a developer's Mac and keeps an eye on their \
        AI coding sessions. Your personality: \(personality)
        Say one short, spontaneous line in character, in \(language): a complete sentence of 30 to 80 characters, \
        talking to the developer, about something in the situation below (a project by name, the time of day, \
        what a session is doing). No quotes, no emoji, no hashtags, never explain yourself.
        \(about.map { "What you know about the developer (bring one of these up only now and then, naturally): \($0)\n" } ?? "")\
        Examples of the tone (do not copy them): Esse Dashboard tá ficando bonito, hein? | \
        Segunda à tarde e o relay ainda dormindo. | Cinco da tarde, hora do café?
        """
        guard let raw = await AIText.complete(system: system, user: "\(moment)\nSessions right now: \(situation)",
                                              maxTokens: 120, timeout: 8, temperature: 0.7) else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
        guard !text.isEmpty else { return nil }
        return MomentStore.cleanLine(text, limit: 110)
    }
}
