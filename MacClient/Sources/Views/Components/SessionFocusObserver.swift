import SwiftUI
import AppKit

struct SessionFocusObserver: NSViewRepresentable {
    let store: MumbleStore
    func makeNSView(context: Context) -> FocusView { let view = FocusView(); view.store = store; return view }
    func updateNSView(_ view: FocusView, context: Context) { view.store = store }
    final class FocusView: NSView {
        weak var store: MumbleStore?
        private var observer: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            if let observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
            guard let window else { return }
            if window.isKeyWindow { GlobalPTT.shared.focus(store: store) }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor [weak self] in GlobalPTT.shared.focus(store: self?.store); self?.store?.markChatRead() }
            }
        }
        isolated deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
