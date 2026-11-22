import SwiftUI

struct MenuBarStatusLabel: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        Group {
            switch store.connection {
            case .connected, .searching:
                Image(systemName: "hifispeaker.fill")
            case .disconnected, .failed:
                Image(systemName: "hifispeaker.badge.minus.fill")
            }
        }
        .frame(minWidth: 24, minHeight: 16, alignment: .center)
    }
}
