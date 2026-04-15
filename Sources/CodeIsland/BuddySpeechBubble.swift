import SwiftUI

/// Notch overlay that appears below the menubar showing the buddy
/// ASCII sprite + a little speech bubble. Auto-dismisses, click to close.
struct BuddySpeechBubble: View {
    let speech: BuddySpeech
    let buddy: BuddyInfo?
    let onDismiss: () -> Void

    @State private var entered = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Mascot — falls back to a generic blob silhouette if no buddy
            Group {
                if let buddy {
                    BuddyASCIIView(buddy: buddy)
                        .padding(.top, 2)
                } else {
                    Image(systemName: "pawprint.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(minWidth: 56, alignment: .center)

            // Speech bubble
            VStack(alignment: .leading, spacing: 4) {
                Text(speech.text)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let name = buddy?.name {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(buddy?.rarity.color ?? .white.opacity(0.4))
                            .frame(width: 5, height: 5)
                        Text(name.lowercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
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
