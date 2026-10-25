import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

/// Presents Sign in with Apple and returns the identity token + nonce Firebase needs.
@MainActor
final class AppleSignInCoordinator: NSObject {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private(set) var currentNonce: String?

    func signIn() async throws -> (credential: ASAuthorizationAppleIDCredential, rawNonce: String) {
        let nonce = Self.randomNonce()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        let credential: ASAuthorizationAppleIDCredential = try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }

        guard let rawNonce = currentNonce else {
            throw AppleSignInError.missingNonce
        }
        return (credential, rawNonce)
    }

    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var random: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                if status != errSecSuccess {
                    fatalError("Unable to generate nonce")
                }
                return random
            }
            for random in randoms where remaining > 0 {
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

enum AppleSignInError: LocalizedError {
    case missingNonce
    case missingIdentityToken
    case unexpectedCredential

    var errorDescription: String? {
        switch self {
        case .missingNonce: return "Sign in with Apple is missing a security nonce."
        case .missingIdentityToken: return "Apple didn’t return an identity token."
        case .unexpectedCredential: return "Unexpected Sign in with Apple credential."
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerDelegate {
    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        Task { @MainActor in
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                continuation?.resume(throwing: AppleSignInError.unexpectedCredential)
                continuation = nil
                return
            }
            continuation?.resume(returning: credential)
            continuation = nil
        }
    }

    nonisolated func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}

extension AppleSignInCoordinator: ASAuthorizationControllerPresentationContextProviding {
    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Called on main by the system during performRequests().
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let window = scene?.windows.first(where: \.isKeyWindow) ?? scene?.windows.first {
            return window
        }
        return UIWindow()
    }
}
