import AppKit
import SwiftUI

@MainActor
final class VolumeHUDController {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<VolumeHUDView>?
    private var hideTask: Task<Void, Never>?
    private var isVisible = false

    private let hideDelayNanos: UInt64 = 1_500_000_000
    private let slideOffset: CGFloat = 10
    private let menuBarGap: CGFloat = 8
    private let screenEdgeMargin: CGFloat = 10

    func show(deviceName: String, level: Double, maxLevel: Double, isMuted: Bool) {
        hideTask?.cancel()

        let view = VolumeHUDView(
            deviceName: deviceName,
            level: level,
            maxLevel: maxLevel,
            isMuted: isMuted
        )

        let panel = ensurePanel()
        if let hostingView {
            hostingView.rootView = view
        } else {
            let newHostingView = NSHostingView(rootView: view)
            newHostingView.translatesAutoresizingMaskIntoConstraints = false
            panel.contentView = newHostingView
            self.hostingView = newHostingView
        }

        panel.layoutIfNeeded()
        positionPanel(panel)

        if isVisible {
            panel.orderFrontRegardless()
            scheduleHide()
            return
        }

        isVisible = true
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        let finalFrame = panel.frame
        panel.setFrame(
            NSRect(
                x: finalFrame.origin.x,
                y: finalFrame.origin.y + slideOffset,
                width: finalFrame.width,
                height: finalFrame.height
            ),
            display: false
        )

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(finalFrame, display: true)
        }

        scheduleHide()
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 72),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }

    private func positionPanel(_ panel: NSPanel) {
        guard let screen = targetScreen() else { return }

        panel.layoutIfNeeded()
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = visible.maxX - screenEdgeMargin - size.width
        let y = visible.maxY - menuBarGap - size.height

        panel.setFrame(
            NSRect(x: x, y: y, width: size.width, height: size.height),
            display: false
        )
    }

    /// Prefer the screen under the cursor; fall back to the menu bar screen.
    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func scheduleHide() {
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: self?.hideDelayNanos ?? 1_500_000_000)
            guard !Task.isCancelled else { return }
            self?.hideAnimated()
        }
    }

    private func hideAnimated() {
        guard let panel, isVisible else { return }

        let startFrame = panel.frame
        let endFrame = NSRect(
            x: startFrame.origin.x,
            y: startFrame.origin.y + slideOffset,
            width: startFrame.width,
            height: startFrame.height
        )

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(endFrame, display: true)
        }, completionHandler: { [weak self] in
            Task { @MainActor in
                panel.orderOut(nil)
                self?.isVisible = false
            }
        })
    }
}
