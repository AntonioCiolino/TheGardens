import SwiftUI

/// Where a team member sets the name shown on plants they add and care notes they log.
/// Kept separate from Team sync so each screen has one responsibility.
struct ProfileView: View {
    @EnvironmentObject private var session: GardensSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section {
                TextField("Your name", text: $session.displayName)
                    .textInputAutocapitalization(.words)
            } header: {
                Text("Your name")
            } footer: {
                Text("Shown on plants you add and care notes you log, so the team can see who did what. Stored on this iPhone.")
            }
        }
        .navigationTitle("Profile")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}
