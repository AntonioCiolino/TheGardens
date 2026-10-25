import SwiftUI
import AuthenticationServices

struct SignInView: View {
    @EnvironmentObject private var session: GardensSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("Inventory syncs plant-by-plant in the cloud so every iPhone on the team sees the same catalog, arrivals, and care history. Access uses Sign in with Apple — you need an Apple ID (iCloud), not a Google login.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if session.isCloudEnabled {
                if let user = session.user {
                    Section("Signed in") {
                        Text(user.displayName ?? "Apple ID")
                        if let email = user.email {
                            Text(email)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Apple ID connected (email may be hidden)")
                                .foregroundStyle(.secondary)
                        }
                        Button("Sign out", role: .destructive) {
                            session.signOut()
                        }
                    }
                } else {
                    Section {
                        Button {
                            Task { await session.signInWithApple() }
                        } label: {
                            Label("Sign in with Apple", systemImage: "apple.logo")
                        }
                    } footer: {
                        Text("Each teammate signs in once with their Apple ID / iCloud account. After that, adds and care logs sync live. This app is built for iPhone.")
                    }
                }
            } else {
                Section("Cloud sync not configured") {
                    Text("Add your Firebase `GoogleService-Info.plist` and enable Sign in with Apple (see docs/firestore-setup.md). Until then the app keeps using on-device SwiftData only.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if let status = session.statusMessage {
                Section("Status") {
                    Text(status)
                }
            }
        }
        .navigationTitle("Team sync")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Sync error", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}
