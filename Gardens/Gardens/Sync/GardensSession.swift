import Foundation
import SwiftUI
import SwiftData
import AuthenticationServices
import FirebaseAuth
import FirebaseFirestore
import GardensCore

struct GardensUser: Equatable {
    var id: String
    var email: String?
    var displayName: String?
}

/// App-wide auth + plant repository.
/// Cloud path: Firestore + **Sign in with Apple** (Apple ID / iCloud account required).
/// Offline path: on-device SwiftData until someone signs in.
@MainActor
final class GardensSession: ObservableObject {
    @Published private(set) var user: GardensUser?
    @Published private(set) var instances: [PlantInstanceDetail] = []
    @Published private(set) var isCloudEnabled: Bool
    @Published private(set) var isListening = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private var modelContext: ModelContext?
    private var firestoreRepo: FirestorePlantRepository?
    private var localRepo: SwiftDataPlantRepository?
    private var instancesListener: ListenerRegistration?
    private var authListener: AuthStateDidChangeListenerHandle?
    private let appleSignIn = AppleSignInCoordinator()

    var repository: any PlantRepository {
        if isCloudEnabled, user != nil, let firestoreRepo {
            return firestoreRepo
        }
        guard let localRepo else {
            fatalError("GardensSession missing local repository — call attach(modelContext:) first.")
        }
        return localRepo
    }

    var usesSharedCloud: Bool {
        isCloudEnabled && user != nil
    }

    init() {
        isCloudEnabled = FirebaseBootstrap.configureIfNeeded()
        if isCloudEnabled {
            firestoreRepo = FirestorePlantRepository()
            authListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
                Task { @MainActor in
                    self?.applyAuthUser(user)
                }
            }
            applyAuthUser(Auth.auth().currentUser)
        }
    }

    func attach(modelContext: ModelContext) {
        self.modelContext = modelContext
        localRepo = SwiftDataPlantRepository(modelContext: modelContext)
        if !usesSharedCloud {
            Task { await refreshLocalInstances() }
        }
    }

    // MARK: - Auth (Apple ID / iCloud — not Google)

    func signInWithApple() async {
        errorMessage = nil
        guard isCloudEnabled else {
            errorMessage = "Add a real GoogleService-Info.plist to enable cloud sync."
            return
        }

        do {
            let (appleCredential, rawNonce) = try await appleSignIn.signIn()
            guard
                let tokenData = appleCredential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = AppleSignInError.missingIdentityToken.localizedDescription
                return
            }

            let oauth = OAuthProvider.appleCredential(
                withIDToken: idToken,
                rawNonce: rawNonce,
                fullName: appleCredential.fullName
            )
            let authResult = try await Auth.auth().signIn(with: oauth)
            applyAuthUser(authResult.user)
            statusMessage = "Signed in with Apple — inventory syncs live for your team."
        } catch {
            // User cancelled the sheet — stay quiet.
            let ns = error as NSError
            if ns.domain == ASAuthorizationError.errorDomain,
               ns.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func signOut() {
        do {
            try Auth.auth().signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
        stopListening()
        user = nil
        Task { await refreshLocalInstances() }
    }

    // MARK: - Data

    func refresh() async {
        if usesSharedCloud {
            await refreshCloudInstances()
        } else {
            await refreshLocalInstances()
        }
    }

    private func applyAuthUser(_ firebaseUser: User?) {
        if let firebaseUser {
            user = GardensUser(
                id: firebaseUser.uid,
                email: firebaseUser.email,
                displayName: firebaseUser.displayName
            )
            startListening()
        } else {
            user = nil
            stopListening()
            instances = []
        }
    }

    private func startListening() {
        guard usesSharedCloud, let firestoreRepo else { return }
        stopListening()
        isListening = true

        instancesListener = firestoreRepo.listenToInstances { [weak self] docs in
            guard let self else { return }
            Task { await self.applyInstanceDocuments(docs) }
        }
    }

    private func stopListening() {
        instancesListener?.remove()
        instancesListener = nil
        isListening = false
    }

    private func applyInstanceDocuments(_ docs: [QueryDocumentSnapshot]) async {
        guard let firestoreRepo else { return }
        do {
            let catalog = try await firestoreRepo.fetchCatalog()
            let catalogByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
            var built: [PlantInstanceDetail] = []
            for doc in docs {
                if let detail = await firestoreRepo.detail(from: doc, catalogByID: catalogByID) {
                    built.append(detail)
                }
            }
            instances = built
            statusMessage = "Live sync · \(built.count) plant\(built.count == 1 ? "" : "s")"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCloudInstances() async {
        guard let firestoreRepo else { return }
        do {
            instances = try await firestoreRepo.fetchInstances()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshLocalInstances() async {
        guard let localRepo else { return }
        do {
            instances = try await localRepo.fetchInstances()
            statusMessage = isCloudEnabled
                ? "Local only — sign in with Apple to share with your team"
                : "On-device SwiftData (Firebase not configured)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
