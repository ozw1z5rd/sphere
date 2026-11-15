import SwiftUI
import AppKit

/// Reports whether the enclosing `ScrollView` (backed by `NSScrollView`) is
/// scrolled to the bottom.
///
/// The chat view uses this to follow streaming responses only while the user
/// is at the bottom: scrolling up during generation must not snap back.
struct ScrollBottomObserver: NSViewRepresentable {
    @Binding var isAtBottom: Bool
    var threshold: CGFloat = 24

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.threshold = threshold
        view.onChange = { isAtBottom = $0 }
        return view
    }

    func updateNSView(_ view: ObserverView, context: Context) {
        view.threshold = threshold
        view.onChange = { isAtBottom = $0 }
        view.attachIfNeeded()
        view.recompute()
    }

    final class ObserverView: NSView {
        var threshold: CGFloat = 24
        var onChange: ((Bool) -> Void)?
        private weak var scrollView: NSScrollView?
        private var observer: NSObjectProtocol?
        private var lastValue: Bool?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
        }

        override func layout() {
            super.layout()
            attachIfNeeded()
            recompute()
        }

        func attachIfNeeded() {
            guard scrollView == nil else { return }
            var current: NSView? = superview
            while let view = current {
                if let scroll = view as? NSScrollView {
                    scrollView = scroll
                    break
                }
                current = view.superview
            }
            guard let scrollView else { return }
            scrollView.contentView.postsBoundsChangedNotifications = true
            observer = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.recompute()
            }
            recompute()
        }

        func recompute() {
            guard let scrollView, let document = scrollView.documentView else { return }
            let clip = scrollView.contentView
            let contentHeight = document.frame.height
            let atBottom: Bool
            if contentHeight <= clip.bounds.height {
                atBottom = true
            } else if document.isFlipped {
                atBottom = clip.bounds.maxY >= contentHeight - threshold
            } else {
                atBottom = clip.bounds.minY <= threshold
            }
            if lastValue != atBottom {
                lastValue = atBottom
                DispatchQueue.main.async { [weak self] in
                    self?.onChange?(atBottom)
                }
            }
        }

        deinit {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
            }
        }
    }
}
