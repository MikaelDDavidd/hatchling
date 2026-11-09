import SwiftUI

/// Notch overlay that appears below the menubar with Hatch speaking as the user's buddy.
/// Auto-dismisses, click to close.
struct BuddySpeechBubble: View {
    let speech: BuddySpeech
    let buddy: BuddyInfo?
    let onDismiss: () -> Void

    @State private var entered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Hatch speaks for the buddy; the hands float outside the block, so leave room.
            MascotView(source: "claude", status: .idle, size: 46, global: true)
                .padding(.horizontal, 12)
                .padding(.top, 2)

            // Speech bubble
            VStack(alignment: .leading, spacing: 4) {
                Text(speech.text)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let name = buddy?.name {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(buddy?.rarity.color ?? .white.opacity(0.4))
                            .frame(width: 5, height: 5)
                        Text(name)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                // Tail pointing back to the mascot
                Triangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 8, height: 12)
                    .offset(x: -7, y: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .scaleEffect(entered ? 1.0 : 0.94)
        .opacity(entered ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                entered = true
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
