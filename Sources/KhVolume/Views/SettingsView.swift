import AppKit
import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @Bindable var store: SpeakerStore
    let loginItem: LoginItem

    var body: some View {
        Form {
            Section("General") {
                Toggle("Open KH Volume at login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if let message = loginItem.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("Volume") {
                LabeledContent("Volume limit") {
                    HStack(spacing: 12) {
                        Slider(value: $store.config.levelLimit, in: SpeakerOutput.levelRange)
                        Text("\(Int(store.config.levelLimit.rounded())) dB")
                            .monospacedDigit()
                            .frame(width: 52, alignment: .trailing)
                    }
                }
                .onChange(of: store.config.levelLimit) { _, _ in store.saveConfig() }

                Picker("Volume step", selection: $store.config.levelStep) {
                    Text("1 dB").tag(1.0)
                    Text("3 dB").tag(3.0)
                    Text("6 dB").tag(6.0)
                }
                .onChange(of: store.config.levelStep) { _, _ in store.saveConfig() }
            }

            Section("Shortcuts") {
                KeyboardShortcuts.Recorder("Volume Up", name: .volumeUp)
                KeyboardShortcuts.Recorder("Volume Down", name: .volumeDown)
                KeyboardShortcuts.Recorder("Mute", name: .muteToggle)
            }

            Section("Advanced") {
                Toggle("Allow increasing volume when left/right levels differ", isOn: $store.config.allowsIncreaseWhileUnbalanced)
                    .onChange(of: store.config.allowsIncreaseWhileUnbalanced) { _, _ in store.saveConfig() }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(minWidth: 420)
        .padding()
        .background {
            SettingsWindowLifecycleView()
                .frame(width: 0, height: 0)
        }
        .onAppear {
            loginItem.refresh()
        }
    }
}

private struct SettingsWindowLifecycleView: NSViewRepresentable {
    func makeNSView(context: Context) -> LifecycleView {
        LifecycleView()
    }

    func updateNSView(_ nsView: LifecycleView, context: Context) {}

    final class LifecycleView: NSView {
        private weak var observedWindow: NSWindow?
        private var closeObserver: NSObjectProtocol?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observe(window)
        }

        deinit {
            removeCloseObserver()
        }

        private func observe(_ window: NSWindow?) {
            guard observedWindow !== window else { return }
            removeCloseObserver()
            observedWindow = window

            guard let window else { return }
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    SettingsWindowPresenter.settingsWindowDidClose()
                }
            }
        }

        private func removeCloseObserver() {
            if let closeObserver {
                NotificationCenter.default.removeObserver(closeObserver)
                self.closeObserver = nil
            }
        }
    }
}
