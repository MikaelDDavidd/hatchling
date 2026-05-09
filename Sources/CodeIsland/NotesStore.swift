import Foundation
import SwiftUI

struct StickyNote: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var colorIndex: Int
    let createdAt: Date
    var updatedAt: Date

    init(id: UUID = UUID(), text: String = "", colorIndex: Int, createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.text = text
        self.colorIndex = colorIndex
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

@MainActor
final class NotesStore: ObservableObject {
    static let shared = NotesStore()

    @Published private(set) var notes: [StickyNote] = []

    static let palette: [Color] = [
        Color(red: 1.00, green: 0.86, blue: 0.40), // amber
        Color(red: 0.69, green: 0.86, blue: 0.99), // sky
        Color(red: 0.85, green: 0.78, blue: 0.99), // lavender
        Color(red: 0.74, green: 0.93, blue: 0.74), // mint
        Color(red: 1.00, green: 0.74, blue: 0.78), // rose
    ]

    private let storeURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = base.appendingPathComponent("Hatchling", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.storeURL = appDir.appendingPathComponent("notes.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode([StickyNote].self, from: data) else {
            return
        }
        notes = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(notes) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    @discardableResult
    func create() -> StickyNote {
        let lastColor = notes.first?.colorIndex ?? -1
        let nextColor = ((lastColor + 1) % NotesStore.palette.count + NotesStore.palette.count) % NotesStore.palette.count
        let note = StickyNote(colorIndex: nextColor)
        notes.insert(note, at: 0)
        persist()
        return note
    }

    func update(id: UUID, text: String) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].text = text
        notes[idx].updatedAt = Date()
        persist()
    }

    func cycleColor(id: UUID) {
        guard let idx = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[idx].colorIndex = (notes[idx].colorIndex + 1) % NotesStore.palette.count
        notes[idx].updatedAt = Date()
        persist()
    }

    func delete(id: UUID) {
        notes.removeAll { $0.id == id }
        persist()
    }

    func color(for note: StickyNote) -> Color {
        NotesStore.palette[note.colorIndex % NotesStore.palette.count]
    }
}
