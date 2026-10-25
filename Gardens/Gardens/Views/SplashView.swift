import SwiftUI

/// Brief brand splash shown on launch before the plant list.
struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.11, green: 0.16, blue: 0.12),
                    Color(red: 0.18, green: 0.32, blue: 0.22),
                    Color(red: 0.22, green: 0.42, blue: 0.28),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            // Soft atmospheric wash
            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: 80, y: -160)

            VStack(spacing: 20) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.72, green: 0.88, blue: 0.70),
                                Color(red: 0.45, green: 0.72, blue: 0.48),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .symbolEffect(.pulse, options: .repeating.speed(0.4))

                Text("Gardens")
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .foregroundStyle(.white)

                Text("Plant intake")
                    .font(.subheadline.weight(.medium))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .accessibilityLabel("Gardens")
    }
}
