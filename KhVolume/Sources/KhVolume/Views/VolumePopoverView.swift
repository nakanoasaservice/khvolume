import AppKit
import SwiftUI

private enum PopoverNavItem: Hashable {
    case mute
    case interface(String)
    case soundSettings
    case quit
}

struct VolumePopoverView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Bindable var store: SpeakerStore
    @State private var sliderLevel: Double = 0
    @State private var isDragging = false
    @State private var focusedNavIndex: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            volumeSection
            Divider()
            networkSection
            Divider()
            actionsSection
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: 280)
        .background {
            PopoverKeyboardHandler(
                onMoveUp: { moveFocus(by: -1) },
                onMoveDown: { moveFocus(by: 1) },
                onActivate: { activateFocusedItem() }
            )
        }
        .onAppear {
            sliderLevel = store.previewAverageLevel
            focusedNavIndex = nil
            Task {
                await store.startupIfNeeded()
                await store.loadInterfaces()
                store.scheduleRefresh()
            }
        }
        .onChange(of: store.previewAverageLevel) { _, new in
            if !isDragging {
                sliderLevel = new
            }
        }
        .onChange(of: navigableItems) { _, _ in
            clampFocusedNavIndex()
        }
    }

    // MARK: - Keyboard navigation

    private var navigableItems: [PopoverNavItem] {
        var items: [PopoverNavItem] = [.mute]
        items += activeInterfaces.map { .interface($0.name) }
        items.append(.soundSettings)
        items.append(.quit)
        return items
    }

    private func isKeyboardFocused(_ item: PopoverNavItem) -> Bool {
        guard let focusedNavIndex, navigableItems.indices.contains(focusedNavIndex) else {
            return false
        }
        return navigableItems[focusedNavIndex] == item
    }

    private func isNavItemEnabled(_ item: PopoverNavItem) -> Bool {
        switch item {
        case .mute, .interface:
            return !store.isBusy
        case .soundSettings, .quit:
            return true
        }
    }

    private func moveFocus(by delta: Int) {
        let items = navigableItems
        guard !items.isEmpty else { return }
        var index: Int
        if let focusedNavIndex {
            index = focusedNavIndex
        } else {
            index = delta > 0 ? -1 : items.count
        }
        for _ in items.indices {
            index = (index + delta + items.count) % items.count
            if isNavItemEnabled(items[index]) {
                focusedNavIndex = index
                return
            }
        }
    }

    private func activateFocusedItem() {
        guard let focusedNavIndex, navigableItems.indices.contains(focusedNavIndex) else {
            return
        }
        let item = navigableItems[focusedNavIndex]
        guard isNavItemEnabled(item) else { return }

        switch item {
        case .mute:
            Task { await store.toggleMute() }
        case .interface(let name):
            Task { await store.selectInterface(name) }
        case .soundSettings:
            dismiss()
            SoundSettingsPresenter.present(store: store, openWindow: openWindow)
        case .quit:
            NSApplication.shared.terminate(nil)
        }
    }

    private func clampFocusedNavIndex() {
        let items = navigableItems
        guard let index = focusedNavIndex else { return }
        guard !items.isEmpty else {
            focusedNavIndex = nil
            return
        }
        var clamped = min(index, items.count - 1)
        if !isNavItemEnabled(items[clamped]) {
            if let enabled = items.firstIndex(where: isNavItemEnabled) {
                clamped = enabled
            } else {
                focusedNavIndex = nil
                return
            }
        }
        focusedNavIndex = clamped
    }

    // MARK: - Sections

    private var volumeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sound")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)

            HStack(spacing: 10) {
                muteButton
                sliderControl
                Text(store.status.isMuted ? "—" : "\(Int(sliderLevel.rounded()))")
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.horizontal, 8)

            if store.status.levelMismatch {
                levelMismatchDetails
            }

            if let err = store.status.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }
        }
    }

    private var muteButton: some View {
        Button {
            Task { await store.toggleMute() }
        } label: {
            Image(systemName: store.status.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.title3)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.isBusy)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(muteHighlightFill)
        }
    }

    private var muteHighlightFill: Color {
        guard !store.isBusy, isKeyboardFocused(.mute) else { return .clear }
        return Color(nsColor: .selectedContentBackgroundColor).opacity(0.85)
    }

    private var sliderControl: some View {
        Slider(
            value: $sliderLevel,
            in: 0...store.config.effectiveMax,
            onEditingChanged: { editing in
                isDragging = editing
                if !editing {
                    Task { await store.setLevel(sliderLevel) }
                }
            }
        )
        .disabled(store.status.isMuted || store.isBusy || blockIncrease)
    }

    private var levelMismatchDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !store.status.devices.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.status.devices) { device in
                        Text("\(device.name)  \(Int(device.level.rounded())) dB")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, 8)
            }

            Text("Left and right levels do not match. You can only decrease volume.")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
    }

    private var blockIncrease: Bool {
        store.status.levelMismatch && !store.config.allowForceOnMismatch
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Network")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .padding(.bottom, 1)

            ForEach(activeInterfaces) { iface in
                PopoverMenuRow(
                    title: interfaceRowTitle(iface),
                    isSelected: store.interfaceName == iface.name,
                    isKeyboardFocused: isKeyboardFocused(.interface(iface.name)),
                    isEnabled: !store.isBusy
                ) {
                    Task { await store.selectInterface(iface.name) }
                }
            }
        }
    }

    private var activeInterfaces: [NetworkInterfaceInfo] {
        store.interfaces.filter { $0.status == "active" }
    }

    private func interfaceRowTitle(_ iface: NetworkInterfaceInfo) -> String {
        if iface.label.isEmpty {
            return iface.name
        }
        return iface.label
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            PopoverMenuRow(
                title: "Preferences…",
                isKeyboardFocused: isKeyboardFocused(.soundSettings)
            ) {
                dismiss()
                SoundSettingsPresenter.present(store: store, openWindow: openWindow)
            }

            PopoverMenuRow(
                title: "Quit KH Volume",
                isKeyboardFocused: isKeyboardFocused(.quit)
            ) {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
