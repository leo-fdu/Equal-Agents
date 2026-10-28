import SwiftUI
import AppKit

// Observe user input without consuming it. Streaming layout changes do not emit wheel events.
struct ScrollIntentObserver: NSViewRepresentable {
    var onScroll: () -> Void
    func makeNSView(context: Context) -> ObserverView { let view = ObserverView(); view.onScroll = onScroll; return view }
    func updateNSView(_ view: ObserverView, context: Context) { view.onScroll = onScroll }
    final class ObserverView: NSView {
        var onScroll: () -> Void = {}
        private var monitor: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown, .keyDown]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                let inside = self.bounds.contains(self.convert(event.locationInWindow, from: nil))
                let scrolling = event.type == .scrollWheel && (event.scrollingDeltaY != 0 || event.phase == .began)
                let draggingScrollbar = event.type == .leftMouseDown && inside && self.convert(event.locationInWindow, from: nil).x > self.bounds.maxX - 18
                if (inside && scrolling) || draggingScrollbar { self.onScroll() }
                return event
            }
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }
}
