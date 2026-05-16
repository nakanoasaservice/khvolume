import AppKit
import SwiftUI

/// Captures arrow keys and Return in the MenuBarExtra popover.
struct PopoverKeyboardHandler: NSViewRepresentable {
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onActivate: () -> Void

    func makeNSView(context: Context) -> PopoverKeyView {
        let view = PopoverKeyView()
        view.onMoveUp = onMoveUp
        view.onMoveDown = onMoveDown
        view.onActivate = onActivate
        return view
    }

    func updateNSView(_ nsView: PopoverKeyView, context: Context) {
        nsView.onMoveUp = onMoveUp
        nsView.onMoveDown = onMoveDown
        nsView.onActivate = onActivate
        if nsView.window?.firstResponder !== nsView {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

final class PopoverKeyView: NSView {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onActivate: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            onMoveUp?()
        case 125:
            onMoveDown?()
        case 36, 76:
            onActivate?()
        default:
            super.keyDown(with: event)
        }
    }
}
