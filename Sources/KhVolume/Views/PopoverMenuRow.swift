import SwiftUI

/// Menu row with macOS Sound-menu-style hover highlight.
struct PopoverMenuRow: View {
    let title: String
    var isSelected: Bool = false
    var isKeyboardFocused: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(highlightFill)
        }
        .onHover { isHovered = $0 }
    }

    private var highlightFill: Color {
        guard isEnabled else { return .clear }
        if isHovered || isKeyboardFocused {
            return Color(nsColor: .selectedContentBackgroundColor).opacity(0.85)
        }
        return Color.clear
    }
}
