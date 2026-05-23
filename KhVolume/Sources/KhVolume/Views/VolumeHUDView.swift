import AppKit
import SwiftUI

struct VolumeHUDView: View {
    let deviceName: String
    let level: Double
    let maxLevel: Double
    let isMuted: Bool

    private var fraction: Double {
        guard maxLevel > 0 else { return 0 }
        return min(1, max(0, level / maxLevel))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(deviceName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 10) {
                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 14)

                VolumeHUDTrack(fraction: isMuted ? 0 : fraction)

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(width: 300)
        .background {
            VolumeHUDBackground()
        }
    }
}

private struct VolumeHUDTrack: View {
    let fraction: Double
    private let tickCount = 16

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(height: 3)

                    Capsule()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: max(0, geo.size.width * fraction), height: 3)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 3)

            HStack(spacing: 0) {
                ForEach(0..<tickCount, id: \.self) { index in
                    Circle()
                        .fill(Color.white.opacity(0.32))
                        .frame(width: 2.5, height: 2.5)
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
