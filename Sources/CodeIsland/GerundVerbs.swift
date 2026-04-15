import Foundation

/// Whimsical present-participle verbs ("Hatching…", "Brewing…") that show
/// in the notch while an agent is actively processing — replacing the
/// session counter for a more delightful, Claude-Code-like vibe.
///
/// Choice is deterministic per (sessionId + currentTool) so the verb stays
/// stable while the same tool runs, then changes when the tool changes.
enum GerundVerbs {
    /// Curated list — egg/incubation theme to match Hatchling branding,
    /// plus generic AI working verbs Claude Code actually emits in its REPL.
    static let all: [String] = [
        "Hatching",
        "Incubating",
        "Brewing",
        "Pondering",
        "Enchanting",
        "Conjuring",
        "Tinkering",
        "Crunching",
        "Whirring",
        "Computing",
        "Cooking",
        "Pecking",
        "Nesting",
        "Roosting",
        "Scheming",
        "Fledging",
        "Buzzing",
        "Smithing",
        "Weaving",
        "Plotting",
        "Hustling",
        "Sketching",
        "Forging",
        "Kindling",
        "Murmuring",
    ]

    /// Pick a verb deterministically from a stable seed — same input always
    /// returns the same word, so the notch label doesn't flicker mid-tool.
    /// Pass nil seed for a random pick.
    static func pick(seed: String?) -> String {
        guard let seed, !seed.isEmpty else {
            return all.randomElement() ?? "Hatching"
        }
        var hash: UInt64 = 1469598103934665603 // FNV offset
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211 // FNV prime
        }
        let idx = Int(hash % UInt64(all.count))
        return all[idx]
    }
}
