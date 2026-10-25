import SwiftUI

struct SignInView: View {
    @EnvironmentObject private var session: GardensSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                Text("Gardens inventory syncs record-by-record in Firestore so everyone on your Google Workspace team sees the same plants and care history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if session.isCloudEnabled {
                if let user = session.user {
                    Section("Signed in") {
                        Text(user.displayName ?? "Gardens user")
                        if let email = user.email {
                            Text(email)
                                .foregroundStyle(.secondary)
                        }
                        Button("Sign out", role: .destructive) {
                            session.signOut()
                        }
                    }
                } else {
                    Section {
                        Button {
                            Task { await session.signInWithGoogle() }
                        } label: {
                            Label("Continue with Google", systemImage: "person.crop.circle.badge.checkmark")
                        }
                    } footer: {
                        Text("Use your Workspace Google account. After sign-in, adds and care logs sync live to everyone signed into this Firebase project.")
                    }
                }
            } else {
                Section("Cloud sync not configured") {
                    Text("Add your Firebase `GoogleService-Info.plist` (see docs/firestore-setup.md), enable Google Sign-In, then rebuild. Until then the app keeps using on-device SwiftData only.")
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
