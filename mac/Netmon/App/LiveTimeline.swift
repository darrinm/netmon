import SwiftUI
import AppKit

/// A periodic timeline that only ticks while its host window is actually on
/// screen.
///
/// SwiftUI keeps `MenuBarExtra` popover content instantiated after the popover
/// is dismissed, so a bare `TimelineView(.periodic(by: 0.1))` inside it keeps
/// rebuilding its content — and keeps committing CoreAnimation transactions to
/// WindowServer — with nothing visible to the user. With a 5-minute chart
/// window at a 1s sample interval that measured ~24% of a core, permanently.
///
/// While off screen the content is still built once, with the current date, so
/// whatever SwiftUI does ask for stays correct; it just stops being rebuilt on
/// a timer.
struct LiveTimeline<Content: View>: View {
    let interval: TimeInterval
    @ViewBuilder var content: (Date) -> Content

    @State private var isOnScreen = false

    var body: some View {
        ZStack {
            if isOnScreen {
                TimelineView(.periodic(from: .now, by: interval)) { context in
                    content(context.date)
                }
            } else {
                content(Date())
            }
        }
        .background(WindowVisibilityReader { isOnScreen = $0 })
    }
}

/// Reports whether the view it's attached to currently sits in a window that
/// is both visible and unoccluded.
private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: TrackerView, context: Context) {
        nsView.onChange = onChange
    }

    final class TrackerView: NSView {
        var onChange: ((Bool) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            // Re-subscribe: the popover panel is torn down and rebuilt, so the
            // window we care about changes over the view's lifetime.
            let center = NotificationCenter.default
            center.removeObserver(self)
            if let window {
                for name: NSNotification.Name in [
                    NSWindow.didChangeOcclusionStateNotification,
                    NSWindow.willCloseNotification,
                    NSWindow.didMiniaturizeNotification,
                    NSWindow.didDeminiaturizeNotification,
                ] {
                    center.addObserver(self, selector: #selector(windowStateChanged),
                                       name: name, object: window)
                }
            }
            report()
        }

        @objc private func windowStateChanged() { report() }

        private func report() {
            let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
            // `viewDidMoveToWindow` runs inside a layout pass; driving a @State
            // change straight from there trips SwiftUI's "modifying state
            // during view update" warning.
            Task { @MainActor [weak self] in
                self?.onChange?(visible)
            }
        }
    }
}
