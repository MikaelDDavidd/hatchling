import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CodeIslandCore

struct FilesTrayView: View {
    @ObservedObject private var store = TrayStore.shared
    @State private var isTargeted = false
    /// The row is an AppKit scroll view, which hides it from the drop target around it,
    /// so it takes drops itself.
    @State private var rowTargeted = false
    @State private var hoveredId: UUID?

    @ObservedObject private var stage = TrayStage.shared

    private let hatchSize: CGFloat = 54
    private var hatchBox: CGFloat { hatchSize * 1.44 }

    var body: some View {
        // One Hatch for every state of the tray, so the one that opens up for a file is the
        // one that swallows it. While a file is on its way the tray clears and Hatch takes
        // the middle, bigger; once every file is in, it steps back to the left and the
        // items come back, the new one sliding out from beside it.
        GeometryReader { geo in
            let centred = (geo.size.width - hatchBox) / 2 - 16
            ZStack(alignment: .leading) {
                trayContent
                    .padding(.leading, 16 + hatchBox + 6)
                    .opacity(stage.centred ? 0 : 1)
                    .allowsHitTesting(!stage.centred)

                trayHatch(size: hatchSize)
                    .scaleEffect(stage.centred ? 1.3 : 1)
                    .offset(x: stage.centred ? centred : 0)
                    .padding(.leading, 16)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 124)
        .padding(.top, 8)
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop)
        .onChange(of: isTargeted) { _, targeted in
            if targeted { stage.dragEntered("tray") } else { stage.dragExited("tray") }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: stage.centred)
        .animation(.spring(response: 0.45, dampingFraction: 0.78), value: store.items.count)
    }

    @ViewBuilder
    private var trayContent: some View {
        if store.items.isEmpty {
            Text(L10n.shared["tray_drop_hint"])
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            SideScroller {
                HStack(spacing: 8) {
                    addTile
                    ForEach(store.items) { item in
                        FileTile(
                            item: item,
                            hovered: hoveredId == item.id,
                            onHover: { h in hoveredId = h ? item.id : nil },
                            onRemove: { store.remove(item) }
                        )
                        // A file arrives from Hatch's side, as if handed over.
                        .transition(.asymmetric(
                            insertion: .offset(x: -80).combined(with: .scale(scale: 0.3, anchor: .leading)).combined(with: .opacity),
                            removal: .opacity.combined(with: .scale(scale: 0.8))
                        ))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .onDrop(of: [UTType.fileURL], isTargeted: $rowTargeted, perform: handleDrop)
                .onChange(of: rowTargeted) { _, targeted in
                    if targeted { stage.dragEntered("row") } else { stage.dragExited("row") }
                }
            }
        }
    }

    /// Hatch keeps the tray: it opens the slot on its head while a file is dragged over and
    /// gulps each one dropped in.
    private func trayHatch(size: CGFloat) -> some View {
        MascotView(source: "claude", status: .idle, size: size, global: true, pocket: true)
            .padding(.horizontal, size * 0.22)
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
                        TrayFeed.feed(fileURL)
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
                    TrayFeed.feed(url)
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

/// Whether Hatch has the tray to itself: from the moment a file is dragged over the panel
/// until the last dropped file is in, or the drag leaves without dropping.
@MainActor
final class TrayStage: ObservableObject {
    static let shared = TrayStage()

    @Published private(set) var centred = false
    private var dragOver: Set<String> = []
    private var pending = 0

    /// While true the panel ignores the mouse leaving and clicks elsewhere: the drop is
    /// not finished until the new tile is in the tray.
    var isBusy: Bool { centred || pending > 0 || !dragOver.isEmpty }

    /// Once the sequence is over, close the panel if the mouse has gone elsewhere — the
    /// collapse the mouse leaving would have caused, held back until now.
    private func closeIfAbandoned(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.isBusy,
                  let delegate = NSApp.delegate as? AppDelegate,
                  delegate.appState.surface.isExpanded,
                  !(delegate.panelController?.isMouseOverContent ?? false) else { return }
            withAnimation(NotchAnimation.close) { delegate.appState.surface = .collapsed }
        }
    }

    func dragEntered(_ source: String) {
        dragOver.insert(source)
        guard !centred else { return }
        centred = true
        HatchDirector.shared.fileHovering()
    }

    /// The drag left one of the drop targets. If it left them all and nothing was dropped,
    /// Hatch closes up and steps back; a drop arrives a moment after the exit, so wait.
    func dragExited(_ source: String) {
        dragOver.remove(source)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.dragOver.isEmpty, self.pending == 0, self.centred else { return }
            HatchReaction.catchEnd.post()
            self.centred = false
            self.closeIfAbandoned(after: 0.8)
        }
    }

    func fileDropped() {
        pending += 1
        centred = true
    }

    /// One swallowed file is ready to land. When it was the last, Hatch steps back first and
    /// the tile follows it out a beat later.
    func fileSwallowed(land: @escaping () -> Void) {
        pending = max(0, pending - 1)
        guard pending == 0 else { land(); return }
        centred = false
        DispatchQueue.main.asyncAfter(deadline: .now() + (Motion.isReduced ? 0 : 0.35), execute: land)
        // Let the new tile settle before the panel closes on its own.
        closeIfAbandoned(after: 1.6)
    }
}

/// Hands dropped files to Hatch one at a time: each is swallowed first and lands in the
/// tray only when the gulp is done, so the drop, the swallow and the new tile read as one
/// motion. Several files queue up a beat apart.
@MainActor
enum TrayFeed {
    private static var nextFree = Date.distantPast
    /// How long the swallow takes before the file comes out the other side.
    private static let swallowTime: TimeInterval = 1.0
    private static let spacing: TimeInterval = 1.15

    #if DEBUG
    /// Plays a whole drag and drop without a file, for reviewing the sequence
    /// (`--rehearse-drop`). Nothing is added to the tray.
    static func rehearse() {
        TrayStage.shared.dragEntered("rehearsal")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            TrayStage.shared.fileDropped()
            TrayStage.shared.dragExited("rehearsal")
            HatchReaction.catchEnd.post()
            HatchDirector.shared.fileCaught("relatorio.pdf")
            DispatchQueue.main.asyncAfter(deadline: .now() + swallowTime) {
                TrayStage.shared.fileSwallowed {}
            }
        }
    }
    #endif

    static func feed(_ url: URL) {
        TrayStage.shared.fileDropped()
        let start = max(Date(), nextFree)
        nextFree = start.addingTimeInterval(spacing)
        let wait = start.timeIntervalSinceNow
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) {
            HatchReaction.catchEnd.post()
            HatchDirector.shared.fileCaught(url.lastPathComponent)
            let land = Motion.isReduced ? 0 : swallowTime
            DispatchQueue.main.asyncAfter(deadline: .now() + land) {
                TrayStage.shared.fileSwallowed {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                        TrayStore.shared.add(fileURL: url)
                    }
                }
            }
        }
    }
}
