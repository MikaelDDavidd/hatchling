import SwiftUI
import CodeIslandCore

/// A session's conversation, inside the notch panel.
///
/// The panel is small and this is a lot of text, so the layout gives almost everything to the
/// words: a thin header to get back out, the turns, and a field. No avatars, no timestamps on
/// every line, no bubbles — at this width a bubble is mostly padding.
struct SessionChatView: View {
    let sessionId: String
    let session: SessionSnapshot
    var appState: AppState

    @State private var store = SessionChatStore.shared
    @State private var draft = ""
    @State private var sendError: String?
    @FocusState private var composerFocused: Bool

    private var accent: Color {
        switch session.source {
        case "codex":  return Color(red: 0.35, green: 0.60, blue: 0.95)
        case "gemini": return Color(red: 0.54, green: 0.71, blue: 0.97)
        default:       return Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color.white.opacity(0.08))
            transcript
            if let sendError {
                Text(sendError)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.35))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 6)
            }
            composer
        }
        .onAppear { store.open(session: session, sessionId: sessionId) }
        .onDisappear { store.close() }
        // The transcript grows while it is being read; re-reading the tail is one window off the
        // end of the file, so it can follow the session's own activity.
        .onChange(of: session.lastActivity) { _, _ in store.refreshTail() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 9) {
            Button {
                withAnimation(NotchAnimation.open) { appState.surface = .sessionList }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .buttonStyle(.plain)

            MascotView(source: session.source, status: session.status, size: 20)

            Text(session.projectDisplayName)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)

            if let model = session.shortModelName {
                Text(model)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
            }

            Spacer(minLength: 6)

            // Still one click to the real terminal. The chat is for reading; the terminal is
            // where the work happens, and taking that away would be a downgrade.
            Button {
                TerminalActivator.activate(session: session, sessionId: sessionId)
            } label: {
                Text("TERMINAL")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5).stroke(.white.opacity(0.15), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcript: some View {
        if !store.available {
            centered("\(session.sourceLabel) keeps no conversation log this app can read")
        } else if store.messages.isEmpty && store.loading {
            centered("reading the transcript")
        } else if store.messages.isEmpty {
            centered("nothing said yet")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        topMarker
                        ForEach(Array(store.messages.enumerated()), id: \.offset) { index, message in
                            turn(message)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: store.messages.count) { _, count in
                    // Opening lands at the newest turn, which is where the conversation is.
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var topMarker: some View {
        if store.reachedStart {
            Text("start of the conversation")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Button {
                store.loadMore()
            } label: {
                Text(store.loading ? "loading" : "load earlier")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(store.loading ? 0.2 : 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(store.loading)
        }
    }

    private func turn(_ message: MobileChatMessage) -> some View {
        HStack(alignment: .top, spacing: 9) {
            // Who spoke is carried by a rail, so both sides start at the same margin and the
            // text reads as one column instead of zig-zagging.
            Rectangle()
                .fill((message.user ? Color.white.opacity(0.28) : accent).opacity(0.75))
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 5) {
                Text(message.user ? "YOU" : session.sourceLabel.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(message.user ? .white.opacity(0.35) : accent.opacity(0.8))

                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.white.opacity(message.user ? 0.72 : 0.92))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !message.tools.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(message.tools.prefix(6), id: \.self) { tool in
                            Text(tool)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.06)))
                        }
                        if message.tools.count > 6 {
                            Text("+\(message.tools.count - 6)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.25))
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func centered(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.white.opacity(0.28))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer

    @ViewBuilder
    private var composer: some View {
        if PromptInjector.canInject(into: session) {
            HStack(spacing: 8) {
                TextField("Send a message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.06)))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(composerFocused ? accent.opacity(0.45) : .white.opacity(0.1), lineWidth: 1)
                    )

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(draft.isEmpty ? .white.opacity(0.2) : Color.black)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(draft.isEmpty ? Color.white.opacity(0.06) : Color(red: 0.3, green: 0.85, blue: 0.4))
                        )
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        } else {
            // Says why instead of offering a field that would be refused after it was typed in.
            Text("Not in tmux, so Hatchling cannot type into this session. Turn on keystroke injection in Settings to send messages.")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sendError = PromptInjector.inject(text: text, into: session)
        if sendError == nil {
            draft = ""
            SoundManager.shared.handleEvent("PromptSent")
        }
    }
}
