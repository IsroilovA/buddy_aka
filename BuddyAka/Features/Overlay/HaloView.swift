import SwiftUI

struct HaloView: View {
    let diameter: CGFloat
    @Environment(BuddySettings.self) private var settings
    @State private var pulse = false

    var body: some View {
        Circle()
            .stroke(settings.color.color.opacity(0.7), lineWidth: 4)
            .frame(width: diameter, height: diameter)
            .scaleEffect(pulse ? 1.12 : 0.92)
            .opacity(pulse ? 0.35 : 0.85)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
