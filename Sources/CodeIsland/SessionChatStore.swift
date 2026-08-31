import Foundation
import CodeIslandCore
import Observation

/// The conversation the panel is currently showing, loaded a page at a time.
///
/// Separate from `AppState` because it is screen state, not session state: it exists only while
/// a chat is open, it is thrown away on close, and nothing else in the app needs to know it was
/// ever there.
@MainActor
@Observable
final class SessionChatStore {
    static let shared = SessionChatStore()

    private(set) var sessionId: String?
    /// Oldest first — reading order, even though pages arrive newest first.
    private(set) var messages: [MobileChatMessage] = []
    private(set) var loading = false
    private(set) var reachedStart = false
    /// True when this CLI keeps no transcript we can read. Not the same as an empty chat.
    private(set) var available = true

    private var nextBefore: Int?
    private var path: String?

    private init() {}

    var canLoadMore: Bool { available && !reachedStart && !loading }

    func open(session: SessionSnapshot, sessionId: String) {
        guard self.sessionId != sessionId else { return }
        self.sessionId = sessionId
        messages = []
        nextBefore = nil
        reachedStart = false
        loading = true

        guard let path = TranscriptReader.transcriptPath(for: session, sessionId: sessionId) else {
            available = false
            loading = false
            return
        }
        available = true
        self.path = path
        load(before: nil)
    }

    func close() {
        sessionId = nil
        messages = []
        path = nil
        nextBefore = nil
        loading = false
        reachedStart = false
        available = true
    }

    func loadMore() {
        guard canLoadMore else { return }
        loading = true
        load(before: nextBefore)
    }

    /// Re-reads the newest page. Cheap — one window off the end of the file — so it can run
    /// whenever the session reports activity, which is what keeps an open chat live.
    func refreshTail() {
        guard let path, !loading, sessionId != nil else { return }
        Task.detached(priority: .utility) {
            let page = TranscriptReader.page(path: path, before: nil, limit: 30)
            await MainActor.run { [weak self] in
                guard let self, let page, self.path == path else { return }
                let fresh = Array(page.messages.reversed())
                guard let cut = fresh.first?.at else { return }
                // Only the tail is replaced; anything already paged in above it stays put.
                // The split is by timestamp rather than by count: turns are coalesced from a
                // varying number of transcript entries, so counting would drift and either
                // duplicate or drop a turn on every refresh.
                let kept = self.messages.filter { $0.at < cut }
                self.messages = TranscriptReader.coalesceChronological(kept + fresh)
            }
        }
    }

    private func load(before: Int?) {
        guard let path else { loading = false; return }
        let requested = sessionId

        // Reading megabytes has no business on the main thread — the panel would stutter every
        // time someone scrolled.
        Task.detached(priority: .userInitiated) {
            let page = TranscriptReader.page(path: path, before: before, limit: 30)
            await MainActor.run { [weak self] in
                guard let self, self.sessionId == requested else { return }
                self.loading = false
                guard let page else {
                    self.reachedStart = true
                    return
                }
                // Pages walk backwards, so each one goes in front of what is already held.
                // Coalescing again across the seam keeps a turn that straddles two pages from
                // reading as two turns by the same speaker.
                self.messages = TranscriptReader.coalesceChronological(
                    Array(page.messages.reversed()) + self.messages
                )
                self.nextBefore = page.nextBefore
                self.reachedStart = page.reachedStart
            }
        }
    }
}
