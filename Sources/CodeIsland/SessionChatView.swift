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

    /// What is left of the panel window once the notch strip, the status and usage bars, the
    /// chat header and a four-line composer have taken their share.
    static let transcriptMaxHeight: CGFloat = 380

    @State private var store = SessionChatStore.shared
    @ObservedObject private var moments = MomentStore.shared
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

            AgentDot(source: session.source, status: session.status, size: 9)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(session.projectDisplayName)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if let model = session.shortModelName {
                        Text(model)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                // Where the session is right now, so the header answers "what is it doing?"
                // before you scroll.
                Text(moments.moment(for: session, sessionId: sessionId).now)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(session.status == .idle ? 0.45 : 0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentTransition(.opacity)
                    .animation(.easeOut(duration: 0.25), value: session.status)
            }

            Spacer(minLength: 6)

            // Still one click to the real terminal. The chat is for reading; the terminal is
            // where the work happens, and taking that away would be a downgrade.
            Button {
                TerminalActivator.activate(session: session, sessionId: sessionId)
            } label: {
                Text(L10n.shared["terminal"])
                    .font(.system(size: 10, weight: .medium))
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
            centered(String(format: L10n.shared["chat_no_log"], session.sourceLabel))
        } else if store.messages.isEmpty && store.loading {
            centered(L10n.shared["chat_reading"])
        } else if store.messages.isEmpty {
            centered(L10n.shared["chat_empty"])
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        topMarker
                        ForEach(Array(store.messages.enumerated()), id: \.offset) { index, message in
                            turn(message)
                                .id(index)
                                .transition(.opacity.combined(with: .offset(y: 10)))
                        }
                        if session.status != .idle {
                            liveRow.id("live")
                        }
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.85), value: store.messages.count)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: store.messages.count) { _, count in
                    // Opening lands at the newest turn, which is where the conversation is.
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
                .onAppear {
                    let count = store.messages.count
                    guard count > 0 else { return }
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
            // The panel sizes to its content, so an unbounded ScrollView reports the whole
            // conversation as its height: the chat outgrew the window and had nothing left to
            // scroll, with both ends cut off. A ceiling makes it scroll inside what fits.
            .frame(maxHeight: Self.transcriptMaxHeight)
        }
    }

    @ViewBuilder
    private var topMarker: some View {
        if store.reachedStart {
            Text(L10n.shared["chat_start"])
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.2))
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Button {
                store.loadMore()
            } label: {
                Text(store.loading ? L10n.shared["chat_loading"] : L10n.shared["chat_load_earlier"])
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(store.loading ? 0.2 : 0.4))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .disabled(store.loading)
        }
    }

    /// Turns the harness writes on your side of the transcript: skill bodies, task
    /// notifications, system reminders. They are not something you said, and shown in full
    /// they buried the conversation under pages of instructions.
    private static func isHarnessTurn(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.hasPrefix("<") || t.hasPrefix("Base directory for this skill")
            || t.hasPrefix("[Request interrupted") || t.hasPrefix("This session is being continued")
            || t.hasPrefix("Caveat:")
    }

    @ViewBuilder
    private func turn(_ message: MobileChatMessage) -> some View {
        if message.user && Self.isHarnessTurn(message.text) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.system(size: 8.5, weight: .semibold))
                Text(MomentStore.cleanLine(message.text, limit: 70))
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.white.opacity(0.25))
            .frame(maxWidth: .infinity, alignment: .center)
        } else if message.user {
            // Your side reads as a reply bubble on the right, so the agent's longer turns keep
            // the full width and the conversation is easy to follow at a glance.
            HStack {
                Spacer(minLength: 48)
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.88))
                        .textSelection(.enabled)
                        .lineLimit(12)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                        )
                }
            }
        } else {
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    if !message.text.isEmpty {
                        MarkdownText(text: message.text)
                    }

                if !message.tools.isEmpty {
                        let summary = ToolSummary.summarize(message.tools)
                        // Wraps, because a coalesced turn can name more tools than fit on one line.
                        FlowLayout(spacing: 5, lineSpacing: 4) {
                            ForEach(summary.prefix(8), id: \.self) { entry in
                                Text(entry.label)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.06)))
                            }
                            if summary.count > 8 {
                                Text("+\(summary.count - 8)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.25))
                            }
                        }
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The agent's current step at the foot of the conversation while it works.
    private var liveRow: some View {
        HStack(spacing: 8) {
            AgentDot(source: session.source, status: session.status, size: 7)
            Text(moments.moment(for: session, sessionId: sessionId).now)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .truncationMode(.middle)
                .contentTransition(.opacity)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(accent.opacity(0.08)))
        .transition(.opacity.combined(with: .offset(y: 6)))
    }

    private func centered(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Composer

    @ViewBuilder
    private var composer: some View {
        if PromptInjector.canInject(into: session) {
            HStack(spacing: 8) {
                TextField(L10n.shared["chat_placeholder"], text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
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
            Text(L10n.shared["chat_no_tmux"])
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
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
