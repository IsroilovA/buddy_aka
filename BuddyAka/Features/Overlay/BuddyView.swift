import SwiftUI

struct BuddyView: View {
    @Environment(BuddySettings.self) private var settings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Image(systemName: "cursorarrow")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(settings.color.color)
                .shadow(color: .white, radius: 0.6, x:  0.9, y:  0.9)
                .shadow(color: .white, radius: 0.6, x: -0.9, y: -0.9)
                .shadow(color: .white, radius: 0.6, x:  0.9, y: -0.9)
                .shadow(color: .white, radius: 0.6, x: -0.9, y:  0.9)
                .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1.5)

            Text(verbatim: "BuddyAka")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous).fill(settings.color.color)
                )
                .overlay(
                    Capsule(style: .continuous).strokeBorder(.white.opacity(0.55), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                .padding(.leading, 14)
        }
    }
}
