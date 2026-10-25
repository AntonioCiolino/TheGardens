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

    /// Optional asset catalog image for the large-logo style.
    /// Drop a logo into Assets as `SplashLogo` (or change this name) to use it.
    static let largeLogoAssetName = "SplashLogo"

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
            largeLogoContent
        }
    }

    @ViewBuilder
    private var largeLogoContent: some View {
        // Prefer a real asset when present; otherwise a bold placeholder mark.
        if UIImage(named: SplashBrandStyle.largeLogoAssetName) != nil {
            Image(SplashBrandStyle.largeLogoAssetName)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 240, maxHeight: 160)
                .accessibilityHidden(true)
        } else {
            VStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.78, green: 0.92, blue: 0.74),
                                Color(red: 0.35, green: 0.62, blue: 0.40),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 200, height: 120)
                    .overlay {
                        Text("GARDENS")
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
                            .tracking(3)
                            .foregroundStyle(Color(red: 0.11, green: 0.18, blue: 0.13))
                    }
                Text("Add SplashLogo to Assets to replace this")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
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
