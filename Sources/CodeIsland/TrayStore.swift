import AppKit
import Foundation
import UniformTypeIdentifiers

struct TrayItem: Identifiable, Codable, Equatable {
    let id: UUID
    let originalName: String
    let storedFileName: String
    let addedAt: Date
    let sizeBytes: Int64

    var storedURL: URL {
        TrayStore.trayDirectory.appendingPathComponent(storedFileName)
    }
}

@MainActor
final class TrayStore: ObservableObject {
    static let shared = TrayStore()

    @Published private(set) var items: [TrayItem] = []

    private let manifestURL: URL
    nonisolated static let trayDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Hatchling/tray", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appDir = base.appendingPathComponent("Hatchling", isDirectory: true)
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        self.manifestURL = appDir.appendingPathComponent("tray.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode([TrayItem].self, from: data) else {
            return
        }
        items = decoded.filter { FileManager.default.fileExists(atPath: $0.storedURL.path) }
        if items.count != decoded.count { persist() }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    func add(fileURL: URL) {
        let stored = uniqueFileName(for: fileURL.lastPathComponent)
        let dest = TrayStore.trayDirectory.appendingPathComponent(stored)
        do {
            try FileManager.default.copyItem(at: fileURL, to: dest)
            let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            let item = TrayItem(
                id: UUID(),
                originalName: fileURL.lastPathComponent,
                storedFileName: stored,
                addedAt: Date(),
                sizeBytes: size
            )
            items.insert(item, at: 0)
            persist()
        } catch {
            NSLog("TrayStore add failed: \(error.localizedDescription)")
        }
    }

    func remove(_ item: TrayItem) {
        try? FileManager.default.removeItem(at: item.storedURL)
        items.removeAll { $0.id == item.id }
        persist()
    }

    func clearAll() {
        for item in items {
            try? FileManager.default.removeItem(at: item.storedURL)
        }
        items.removeAll()
        persist()
    }

    private func uniqueFileName(for name: String) -> String {
        let url = URL(fileURLWithPath: name)
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var candidate = "\(UUID().uuidString.prefix(8))_\(base)"
        if !ext.isEmpty { candidate += ".\(ext)" }
        return candidate
    }

    func icon(for item: TrayItem, size: CGFloat = 36) -> NSImage {
        let icon = NSWorkspace.shared.icon(forFile: item.storedURL.path)
        icon.size = NSSize(width: size, height: size)
        return icon
    }

    func formattedSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
