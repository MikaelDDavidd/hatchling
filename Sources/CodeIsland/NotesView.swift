import SwiftUI

struct NotesView: View {
    @ObservedObject private var store = NotesStore.shared
    @State private var expandedId: UUID?
    @Namespace private var animation

    var body: some View {
        ZStack {
            if let id = expandedId, let note = store.notes.first(where: { $0.id == id }) {
                expandedNote(note)
                    .transition(.opacity)
            } else {
                carousel
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: expandedId)
    }

    private var carousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                addCard
                ForEach(store.notes) { note in
                    NoteCard(note: note, color: store.color(for: note))
                        .matchedGeometryEffect(id: note.id, in: animation)
                        .onTapGesture { expandedId = note.id }
                        .contextMenu {
                            Button("Mudar cor") { store.cycleColor(id: note.id) }
                            Button("Apagar", role: .destructive) { store.delete(id: note.id) }
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: 110)
    }

    private var addCard: some View {
        Button {
            let new = store.create()
            expandedId = new.id
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Nova")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 80, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.white.opacity(0.18))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func expandedNote(_ note: StickyNote) -> some View {
        ExpandedNoteCard(
            note: note,
            color: store.color(for: note),
            onCommit: { newText in store.update(id: note.id, text: newText) },
            onClose: { expandedId = nil },
            onCycleColor: { store.cycleColor(id: note.id) },
            onDelete: {
                store.delete(id: note.id)
                expandedId = nil
            }
        )
        .matchedGeometryEffect(id: note.id, in: animation)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

private struct NoteCard: View {
    let note: StickyNote
    let color: Color

    private var preview: String {
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Nota vazia" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(preview)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.black.opacity(0.78))
                .lineLimit(5)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(8)
        .frame(width: 90, height: 88)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.black.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 2)
        .rotationEffect(.degrees(rotation))
    }

    private var rotation: Double {
        let hash = abs(note.id.uuidString.hashValue) % 7
        return Double(hash) - 3.0
    }
}

private struct ExpandedNoteCard: View {
    let note: StickyNote
    let color: Color
    let onCommit: (String) -> Void
    let onClose: () -> Void
    let onCycleColor: () -> Void
    let onDelete: () -> Void

    @State private var draft: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack(alignment: .topLeading) {
                if draft.isEmpty {
                    Text("Escreva sua nota…")
                        .font(.system(size: 12))
                        .foregroundStyle(.black.opacity(0.35))
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $draft)
                    .focused($focused)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black.opacity(0.85))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .onChange(of: draft) { _, new in onCommit(new) }
            }
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 200)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(.black.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
        .onAppear {
            draft = note.text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { focused = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("Voltar")

            Spacer()

            Button(action: onCycleColor) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 11))
                    .foregroundStyle(.black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("Trocar cor")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.black.opacity(0.65))
            }
            .buttonStyle(.plain)
            .help("Apagar")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.05))
    }
}
