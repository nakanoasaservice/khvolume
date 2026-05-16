import SwiftUI

struct MenuBarStatusLabel: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        Group {
            if let volumeText = store.menuBarHotkeyVolumeText {
                Text(volumeText)
                    .monospacedDigit()
            } else if store.status.connection == .disconnected {
                Text("!")
            } else {
                Image(systemName: "hifispeaker.fill")
            }
        }
        .frame(minWidth: 24, minHeight: 16, alignment: .center)
        .task { await store.startupIfNeeded() }
    }
}
