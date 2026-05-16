import SwiftUI

struct MenuBarStatusLabel: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        Text(displayText)
            .monospacedDigit()
            .frame(minWidth: 24, minHeight: 16, alignment: .center)
            .task { await store.startupIfNeeded() }
    }

    private var displayText: String {
        if store.isBusy {
            return store.menuBarApplyingText
        }
        return store.menuBarLabel
    }
}
