import SwiftUI

/// Splash brand treatments. Add asset names here when real logos land in Assets.
enum SplashBrandStyle: String, CaseIterable, Identifiable, Sendable {
    case leafMark
    case wordmark
    case largeLogo

    var id: String { rawValue }

    /// Display name for settings / future picker.
    var title: String {
        switch self {
        case .leafMark: return "Leaf mark"
        case .wordmark: return "Wordmark"
        case .largeLogo: return "Large logo"
        }
    }

    static func random() -> SplashBrandStyle {
        allCases.randomElement() ?? .leafMark
    }
}

/// Brief brand splash shown on launch. Style can be fixed or randomized.
struct SplashView: View {
    var style: SplashBrandStyle = .random()

    var body: some View {
        ZStack {
            background

            Circle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 320, height: 320)
                .blur(radius: 40)
                .offset(x: 80, y: -160)

            VStack(spacing: 18) {
                logo
                if style != .largeLogo {
                    Text("Gardens")
                        .font(.system(size: 44, weight: .bold, design: .serif))
                        .foregroundStyle(.white)
                }
                Text("Plant intake")
                    .font(.subheadline.weight(.medium))
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.65))
            }
            .padding(.horizontal, 28)
        }
        .accessibilityLabel("Gardens")
    }

    @ViewBuilder
    private var logo: some View {
        switch style {
        case .leafMark:
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

        case .wordmark:
            Text("G")
                .font(.system(size: 72, weight: .bold, design: .serif))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(red: 0.85, green: 0.94, blue: 0.82),
                            Color(red: 0.55, green: 0.78, blue: 0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 96, height: 96)
                .background(Circle().fill(Color.white.opacity(0.1)))

        case .largeLogo:
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 300)
                .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
                .accessibilityHidden(true)
        }
    }

    private var background: some View {
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
    }
}
