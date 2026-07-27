import SwiftUI

extension ProfileTint {
    /// System colors adapt to light and dark appearance; the low opacity used
    /// at the call sites keeps them as a hint rather than a highlight.
    var color: Color? {
        switch self {
        case .none: nil
        case .blue: .blue
        case .purple: .purple
        // The stored raw value stays "teal" for saved customizations, but the
        // rendered color is cyan: system teal is too close to green once the
        // card fill and stripe lighten it.
        case .teal: .cyan
        case .green: .green
        case .orange: .orange
        case .pink: .pink
        case .graphite: .gray
        }
    }

    var localizedName: String {
        switch self {
        case .none: "No color"
        case .blue: "Blue"
        case .purple: "Purple"
        case .teal: "Cyan"
        case .green: "Green"
        case .orange: "Orange"
        case .pink: "Pink"
        case .graphite: "Graphite"
        }
    }
}

/// Background for a provider card: the standard quaternary wash plus, for a
/// tinted account, a whisper-light fill and a small saturated edge stripe.
/// The stripe is what tells neighboring hues apart — at fill opacities this
/// low the hues themselves are indistinguishable.
struct ProviderCardBackground: View {
    let tint: ProfileTint

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary.opacity(0.45))
            if let color = tint.color {
                RoundedRectangle(cornerRadius: 10)
                    .fill(color.opacity(0.08))
                Capsule()
                    .fill(color.opacity(0.8))
                    .frame(width: 3)
                    .padding(.vertical, 8)
                    .padding(.leading, 5)
            }
        }
    }
}

struct ProfileTintPicker: View {
    @Binding var selection: ProfileTint

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProfileTint.allCases, id: \.self) { tint in
                Button {
                    selection = tint
                } label: {
                    swatch(tint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tint.localizedName)
                .accessibilityAddTraits(selection == tint ? [.isSelected] : [])
            }
        }
    }

    @ViewBuilder
    private func swatch(_ tint: ProfileTint) -> some View {
        ZStack {
            // Swatches stay fully saturated — hues are only distinguishable
            // at tiny sizes when they aren't washed out by opacity.
            Circle()
                .fill(tint.color ?? Color.clear)
            if tint == .none {
                Circle()
                    .strokeBorder(.quaternary, lineWidth: 1)
                Image(systemName: "slash.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            if selection == tint {
                Circle()
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .frame(width: 14, height: 14)
        .contentShape(Circle())
    }
}
