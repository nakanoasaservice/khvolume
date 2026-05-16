import SwiftUI
import KeyboardShortcuts

struct SoundSettingsView: View {
    @Bindable var store: SpeakerStore

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open KH Volume at login", isOn: $store.config.launchAtLogin)
                    .onChange(of: store.config.launchAtLogin) { _, _ in
                        store.saveConfig()
                    }
                if let message = store.launchAtLoginMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !LaunchAtLogin.serviceIsEnabled {
                    Text("Install a signed KhVolume.app in /Applications to enable Open at Login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Volume") {
                LabeledContent("Volume limit") {
                    HStack(spacing: 12) {
                        Slider(value: $store.config.maxVolumeLimit, in: 0...120)
                        Text("\(Int(store.config.maxVolumeLimit.rounded())) dB")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                .onChange(of: store.config.maxVolumeLimit) { _, _ in store.saveConfig() }

                Picker("Volume step", selection: $store.config.volumeStep) {
                    Text("1 dB").tag(1.0)
                    Text("3 dB").tag(3.0)
                    Text("6 dB").tag(6.0)
                }
                .onChange(of: store.config.volumeStep) { _, _ in store.saveConfig() }
            }

            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Volume Up", name: .volumeUp)
                KeyboardShortcuts.Recorder("Volume Down", name: .volumeDown)
                KeyboardShortcuts.Recorder("Mute", name: .muteToggle)
            }

            Section("Advanced") {
                Toggle("Allow increasing volume when left/right levels differ", isOn: $store.config.allowForceOnMismatch)
                    .onChange(of: store.config.allowForceOnMismatch) { _, _ in store.saveConfig() }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 420)
        .padding()
        .onAppear {
            store.reconcileLaunchAtLoginFromService()
        }
    }
}
