import SwiftUI
import UIKit

struct WelcomeBounceOverlay: View {
    let placeName: String
    var onDismiss: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(spacing: 14) {
                BrandLogo(height: 120)
                Text("We're glad you're here")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(placeName)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Continue", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 6)
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .padding(.horizontal, 32)
            .scaleEffect(shown ? 1 : 0.35)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.55)) {
                shown = true
            }
        }
    }
}
