import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FilesTrayView: View {
    @ObservedObject private var store = TrayStore.shared
    @State private var isTargeted = false
    @State private var hoveredId: UUID?

    var body: some View {
        VStack(spacing: 6) {
            if store.items.isEmpty {
                emptyDropZone
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        addTile
                        ForEach(store.items) { item in
                            FileTile(
                                item: item,
                                hovered: hoveredId == item.id,
                                onHover: { h in hoveredId = h ? item.id : nil },
                                onRemove: { store.remove(item) }
                            )
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: 88)
                .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop)
                .overlay(
                    Rectangle()
                        .stroke(Color.green.opacity(isTargeted ? 0.5 : 0), lineWidth: 1)
                )
            }
        }
    }

    private var emptyDropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(isTargeted ? 0.85 : 0.4))
            Text(isTargeted ? "Solte aqui" : "Arraste arquivos para guardar")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 80)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
                .foregroundStyle(.white.opacity(isTargeted ? 0.6 : 0.18))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
    }

    private var addTile: some View {
        Button(action: pickFiles) {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Adicionar")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 60, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.white.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var didAdd = false
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { (data, _) in
                    var url: URL?
                    if let urlData = data as? Data {
                        url = URL(dataRepresentation: urlData, relativeTo: nil)
                    } else if let u = data as? URL {
                        url = u
                    }
                    guard let fileURL = url else { return }
                    Task { @MainActor in
                        TrayStore.shared.add(fileURL: fileURL)
                    }
                }
                didAdd = true
            }
        }
        return didAdd
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                Task { @MainActor in
                    TrayStore.shared.add(fileURL: url)
                }
            }
        }
    }
}

private struct FileTile: View {
    let item: TrayItem
    let hovered: Bool
    let onHover: (Bool) -> Void
    let onRemove: () -> Void

    @ObservedObject private var store = TrayStore.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 4) {
                Image(nsImage: store.icon(for: item, size: 36))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                Text(item.originalName)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 64)
            }
            .frame(width: 72, height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(hovered ? 0.10 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
            .help("\(item.originalName) — \(store.formattedSize(item.sizeBytes))")
            .onDrag {
                NSItemProvider(object: item.storedURL as NSURL)
            }

            if hovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.7))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
                .transition(.opacity)
            }
        }
        .onHover { onHover($0) }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }
}
