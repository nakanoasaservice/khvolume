import AppKit
import SwiftUI

private enum PopoverNavItem: Hashable {
    case mute
    case reload
    case interface(String)
    case settings
    case quit
}

struct VolumePopoverView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Bindable var store: SpeakerStore
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
        .frame(width: 310)
        .background {
            PopoverKeyboardHandler(
                onMoveUp: { moveFocus(by: -1) },
                onMoveDown: { moveFocus(by: 1) },
                onActivate: { activateFocusedItem() }
            )
        }
        .onAppear {
            focusedNavIndex = nil
            store.preparePopover()
        }
        .onChange(of: navigableItems) { _, _ in
            clampFocusedNavIndex()
        }
    }

    // MARK: - Keyboard navigation

    private var navigableItems: [PopoverNavItem] {
        var items: [PopoverNavItem] = [.mute, .reload]
        items += activeInterfaces.map { .interface($0.name) }
        items.append(.settings)
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
        case .mute, .reload, .interface:
            return !store.isSearching
        case .settings, .quit:
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
        activate(item)
    }

    /// The action behind each row, shared by clicks and the keyboard.
    private func activate(_ item: PopoverNavItem) {
        switch item {
        case .mute:
            Task { await store.toggleMute() }
        case .reload:
            Task { await store.reload() }
        case .interface(let name):
            Task { await store.selectInterface(name) }
        case .settings:
            dismiss()
            SettingsWindowPresenter.present(openSettings: openSettings)
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
                Text(store.levelText)
                    .monospacedDigit()
                    .frame(width: 28, alignment: .trailing)
            }
            .padding(.horizontal, 8)

            if !store.isBalanced {
                unbalancedLevelDetails
            } else if !store.outputs.isEmpty {
                Text(store.speakerNamesText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
            }

            if let err = store.errorMessage {
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
            activate(.mute)
        } label: {
            Image(systemName: store.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.title3)
                .padding(4)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.isSearching)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(focusHighlightFill(.mute))
        }
    }

    /// Keyboard-focus highlight for the icon buttons; the rows draw their own.
    private func focusHighlightFill(_ item: PopoverNavItem) -> Color {
        guard !store.isSearching, isKeyboardFocused(item) else { return .clear }
        return Color(nsColor: .selectedContentBackgroundColor).opacity(0.85)
    }

    private var sliderControl: some View {
        Slider(
            value: Binding(
                get: { store.level },
                set: { store.setLevel($0) }
            ),
            in: 0...store.config.maxLevel
        )
        .disabled(store.isVolumeSliderDisabled)
    }

    private var unbalancedLevelDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(store.outputs.sorted { ($0.name, $0.id) < ($1.name, $1.id) }) { output in
                    Text("\(output.name)  \(Int(output.level.rounded())) dB")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 8)

            Text("Left and right levels do not match. You can only decrease volume.")
                .font(.caption)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text("Network")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                reloadButton
            }
            .padding(.leading, 8)
            // With the button's own padding, the icon lines up with the rows' checkmark.
            .padding(.trailing, 5)

            ForEach(activeInterfaces) { interface in
                PopoverMenuRow(
                    title: interfaceRowTitle(interface),
                    isSelected: store.config.networkInterface == interface.name,
                    isKeyboardFocused: isKeyboardFocused(.interface(interface.name)),
                    isEnabled: !store.isSearching
                ) {
                    activate(.interface(interface.name))
                }
            }
        }
    }

    private var reloadButton: some View {
        Button {
            activate(.reload)
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.subheadline.weight(.semibold))
                .padding(3)
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(store.isSearching)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(focusHighlightFill(.reload))
        }
        .help("Search for speakers again")
        .accessibilityLabel("Reload")
    }

    private var activeInterfaces: [NetworkInterface] {
        store.interfaces.filter(\.isActive)
    }

    private func interfaceRowTitle(_ interface: NetworkInterface) -> String {
        if interface.label.isEmpty {
            return interface.name
        }
        return interface.label
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            PopoverMenuRow(
                title: "Preferences…",
                isKeyboardFocused: isKeyboardFocused(.settings)
            ) {
                activate(.settings)
            }

            PopoverMenuRow(
                title: "Quit KH Volume",
                isKeyboardFocused: isKeyboardFocused(.quit)
            ) {
                activate(.quit)
            }
        }
    }
}
