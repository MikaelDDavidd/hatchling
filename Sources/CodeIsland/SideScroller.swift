import AppKit
import SwiftUI

/// A row that scrolls sideways, for the notes and the files tray.
///
/// SwiftUI's horizontal `ScrollView` didn't move in the panel: the panel never becomes
/// key, and a mouse wheel only sends vertical deltas, so with a regular mouse the row was
/// stuck on the first few items and anything after them could not be reached. This is an
/// `NSScrollView` (like the session list's) that turns a vertical wheel or swipe into a
/// sideways one, and passes it on untouched when the row already fits.
struct SideScroller<Content: View>: NSViewRepresentable {
    @ViewBuilder let content: Content

    func makeNSView(context: Context) -> SideNSScrollView {
        let scrollView = SideNSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScroller?.controlSize = .mini
        scrollView.scrollerKnobStyle = .light
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.verticalScrollElasticity = .none

        let hosting = NSHostingView(rootView: SideDocument(content: content))
        hosting.sizingOptions = []
        scrollView.documentView = hosting

        let coordinator = context.coordinator
        scrollView.measure = { [weak coordinator] in coordinator?.fittingSize() ?? .zero }
        return scrollView
    }

    func updateNSView(_ scrollView: SideNSScrollView, context: Context) {
        context.coordinator.update(content)
        if let hosting = scrollView.documentView as? NSHostingView<SideDocument<Content>> {
            hosting.rootView = SideDocument(content: content)
        }
        scrollView.scrollerStyle = .overlay
        scrollView.horizontalScroller?.controlSize = .mini
        scrollView.needsLayout = true
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: SideNSScrollView, context: Context) -> CGSize? {
        context.coordinator.update(content)
        let fitting = context.coordinator.fittingSize()
        return CGSize(width: proposal.width ?? fitting.width, height: fitting.height)
    }

    func makeCoordinator() -> Coordinator { Coordinator(content: content) }

    final class Coordinator {
        // Measures the bare row: the document view stretches to fill, so measuring it
        // would come back infinite.
        private let measurer: NSHostingController<SideMeasure<Content>>

        init(content: Content) {
            measurer = NSHostingController(rootView: SideMeasure(content: content))
        }

        func update(_ content: Content) {
            measurer.rootView = SideMeasure(content: content)
        }

        func fittingSize() -> CGSize {
            let size = measurer.sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude,
                                                        height: CGFloat.greatestFiniteMagnitude))
            return CGSize(width: ceil(size.width), height: ceil(size.height))
        }
    }
}

struct SideMeasure<Content: View>: View {
    let content: Content
    var body: some View { content.fixedSize() }
}

/// The row at its natural width, pinned to the leading edge when it is narrower than
/// the scroller.
struct SideDocument<Content: View>: View {
    let content: Content

    var body: some View {
        content
            .fixedSize()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

final class SideNSScrollView: NSScrollView {
    var measure: (() -> CGSize)?

    override func layout() {
        super.layout()
        guard let document = documentView, let measure else { return }
        let fitting = measure()
        let size = NSSize(width: max(fitting.width, contentView.bounds.width), height: contentView.bounds.height)
        if document.frame.size != size {
            document.frame = NSRect(origin: .zero, size: size)
            clampOffset()
        }
    }

    private var wheelMonitor: Any?

    // The wheel never reaches this view on its own: the SwiftUI hosting view under the
    // pointer takes it first. So the row watches the app's wheel events and handles the
    // ones over it before they are dispatched.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let wheelMonitor { NSEvent.removeMonitor(wheelMonitor) }
        wheelMonitor = nil
        guard window != nil else { return }
        wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let window = self.window, self.isPointerOver(event, in: window) else { return event }
            return self.scrollSideways(event) ? nil : event
        }
    }

    /// Compared on screen, since the panel never becomes key and an event can arrive
    /// without a window.
    private func isPointerOver(_ event: NSEvent, in window: NSWindow) -> Bool {
        guard isVisible(in: window) else { return false }
        let onScreen = event.window.map { $0.convertPoint(toScreen: event.locationInWindow) } ?? event.locationInWindow
        let mine = window.convertToScreen(convert(visibleRect, to: nil))
        return mine.contains(onScreen)
    }

    private func isVisible(in window: NSWindow) -> Bool {
        window.isVisible && !isHiddenOrHasHiddenAncestor && visibleRect.width > 0
    }

    override func scrollWheel(with event: NSEvent) {
        if !scrollSideways(event) { super.scrollWheel(with: event) }
    }

    /// Moves the row for a wheel or swipe over it. False when the row has nothing to
    /// scroll, so the event carries on to whatever is behind.
    private func scrollSideways(_ event: NSEvent) -> Bool {
        guard let document = documentView else { return false }
        let overflow = document.frame.width - contentView.bounds.width
        guard overflow > 0 else { return false }
        // A sideways swipe moves sideways; an up/down wheel or swipe moves sideways too.
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        // A mouse wheel moves in lines; give each notch a useful step.
        let step = event.hasPreciseScrollingDeltas ? delta : delta * 12
        var origin = contentView.bounds.origin
        origin.x = min(max(origin.x - step, 0), overflow)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
        flashScrollers()
        return true
    }

    /// After the row shrinks (a note deleted, a file removed), don't leave it scrolled
    /// past its new end.
    private func clampOffset() {
        guard let document = documentView else { return }
        let overflow = max(0, document.frame.width - contentView.bounds.width)
        var origin = contentView.bounds.origin
        if origin.x > overflow {
            origin.x = overflow
            contentView.scroll(to: origin)
            reflectScrolledClipView(contentView)
        }
    }
}
