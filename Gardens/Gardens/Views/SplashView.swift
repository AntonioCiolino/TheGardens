import SwiftUI

/// Splash layout variants — the tall G monogram is always shown.
enum SplashBrandStyle: String, CaseIterable, Identifiable, Sendable {
    case centered
    case lifted
    case softGlow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .centered: return "Centered logo"
        case .lifted: return "Lifted logo"
        case .softGlow: return "Soft glow"
        }
    }

    static func random() -> SplashBrandStyle {
        allCases.randomElement() ?? .centered
    }
}

/// Launch splash. The full oval mark stays in the asset catalog; this screen shows the G.
struct SplashView: View {
    var style: SplashBrandStyle = .random()

    var body: some View {
        ZStack {
            background

            if style == .softGlow {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 340, height: 340)
                    .blur(radius: 50)
                    .offset(y: -20)
            }

            VStack(spacing: 22) {
                Image("QRMonogram")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: logoWidth, maxHeight: 340)
                    .padding(.horizontal, 36)
                    .padding(.vertical, 28)
                    .background {
                        Capsule()
                            .fill(Color(red: 0.94, green: 0.93, blue: 0.88))
                    }
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
                    .offset(y: style == .lifted ? -24 : 0)
                    .accessibilityHidden(true)

                Text("Plant intake")
                    .font(.subheadline.weight(.medium))
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.horizontal, 32)
        }
        .accessibilityLabel("The Gardens")
    }

    private var logoWidth: CGFloat {
        switch style {
        case .centered: return 240
        case .lifted: return 260
        case .softGlow: return 250
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
