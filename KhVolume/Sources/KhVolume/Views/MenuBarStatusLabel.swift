import SwiftUI

struct MenuBarStatusLabel: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        Group {
            if store.connection == .disconnected {
                Image(systemName: "hifispeaker.badge.minus.fill")
            } else {
                Image(systemName: "hifispeaker.fill")
            }
        }
        .frame(minWidth: 24, minHeight: 16, alignment: .center)
        .task { await store.startupIfNeeded() }
    }
}
