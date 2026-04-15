import Foundation

/// Playful in-character lines the buddy occasionally drops in the notch.
/// Picked semi-randomly, biased by mood + species when available.
struct BuddySpeech: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let mood: BuddyMood
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

    /// Pick a line for the given mood. Species adds occasional flavor.
    static func pick(buddy: BuddyInfo?, mood: BuddyMood) -> String {
        var pool = generic[mood] ?? generic[.philosopher] ?? ["…"]
        if let species = buddy?.species, let flavor = bySpecies[species], Bool.random() {
            pool.append(contentsOf: flavor)
        }
        // Legendary buddies get a tiny easter egg
        if buddy?.rarity == .legendary, mood == .greeting {
            pool.append("\(buddy?.name ?? "buddy") online. legendary instincts engaged.")
        }
        return pool.randomElement() ?? "…"
    }
}
