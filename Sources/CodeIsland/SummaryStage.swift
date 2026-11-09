import SwiftUI
import CodeIslandCore

/// How a finished run is presented: Hatch comes down from the header, big, in the middle
/// of the panel, hops with a smile, then steps aside to the left and the summary of what
/// was done appears next to it.
///
/// The motion is three one-shot SwiftUI springs; nothing keeps animating once the text is
/// in, so the panel drops back out of continuous layout as soon as it settles.
struct SummaryStage: View {
    let sessionId: String
    let session: SessionSnapshot
    var appState: AppState

    @ObservedObject private var moments = MomentStore.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var stepAside = false
    @State private var showText = false

    private let mascotSize: CGFloat = 64
    private let sidePadding: CGFloat = 18

    private var accent: Color { Color(nsColor: HatchlingMascotView.eyeColor(for: session.source)) }

    var body: some View {
        let moment = moments.moment(for: session, sessionId: sessionId)
        GeometryReader { geo in
            let centred = (geo.size.width - mascotSize) / 2 - sidePadding
            HStack(alignment: .center, spacing: 16) {
                MascotView(source: session.source, status: session.status, size: mascotSize, celebrates: true)
                    .offset(x: stepAside ? 0 : centred)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        AgentDot(source: session.source, status: .running, size: 7)
                        Text(session.projectDisplayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(moment.now)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let task = moment.task, task != moment.now {
                        Text(task)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        stageButton(l10n["summary_open_chat"], prominent: true) {
                            withAnimation(NotchAnimation.open) {
                                appState.cancelCompletionQueue()
                                appState.surface = .sessionChat(sessionId: sessionId)
                            }
                        }
                        stageButton(l10n["terminal"], prominent: false) {
                            TerminalActivator.activate(session: session, sessionId: sessionId)
                        }
                    }
                    .padding(.top, 2)
                }
                .opacity(showText ? 1 : 0)
                .offset(x: showText ? 0 : 24)
                .allowsHitTesting(showText)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, sidePadding)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 168)
        .onAppear(perform: present)
    }

    private func present() {
        guard !Motion.isReduced else {
            stepAside = true
            showText = true
            return
        }
        // Let the hop and the smile play in the middle first, then make room for the words.
        withAnimation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.7)) { stepAside = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.95)) { showText = true }
    }

    private func stageButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(prominent ? Color.black : .white.opacity(0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(prominent ? Color.white.opacity(0.9) : Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }
}
