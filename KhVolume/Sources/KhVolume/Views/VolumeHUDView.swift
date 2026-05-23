import AppKit
import SwiftUI

struct VolumeHUDView: View {
    let level: Double
    let maxLevel: Double
    let isMuted: Bool
    let isCommitting: Bool

    private var fraction: Double {
        guard maxLevel > 0 else { return 0 }
        return min(1, max(0, level / maxLevel))
    }

    private var levelText: String {
        if isMuted { return "—" }
        return "\(Int(level.rounded()))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(levelText)
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(isCommitting ? 0.65 : 1))

            HStack(spacing: 10) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(isCommitting ? 0.5 : 0.85))
                    .frame(width: 14)

                VolumeHUDTrack(
                    fraction: isMuted ? 0 : fraction,
                    isDisabled: isCommitting
                )

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(isCommitting ? 0.5 : 0.85))
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 300)
        .animation(.easeInOut(duration: 0.15), value: isCommitting)
        .background {
            VolumeHUDBackground()
        }
    }
}

private struct VolumeHUDTrack: View {
    let fraction: Double
    var isDisabled: Bool = false
    private let tickCount = 16

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(isDisabled ? 0.14 : 0.22))
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.white.opacity(isDisabled ? 0.55 : 0.92))
                        .frame(width: max(0, geo.size.width * fraction), height: 3)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 3)

            HStack(spacing: 0) {
                ForEach(0..<tickCount, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(isDisabled ? 0.08 : 0.14))
                        .frame(width: 2, height: 2)
                    if index < tickCount - 1 {
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}

private struct VolumeHUDBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.wantsLayer = true
        view.layer?.cornerRadius = 18
        view.layer?.cornerCurve = .continuous
        view.layer?.borderWidth = 0.5
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
