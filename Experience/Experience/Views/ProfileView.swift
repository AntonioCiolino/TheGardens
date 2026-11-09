import SwiftUI

/// Where a guest sets the name shown on posts they share.
/// Mirrors the Gardens Intake profile screen so both apps set a name the same way.
/// Bound to the same `experience.authorName` key the composer reads, so the two stay in sync.
struct ExperienceProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("experience.authorName") private var authorName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Your name", text: $authorName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Your name")
                } footer: {
                    Text("Shown on posts you share with the garden. Optional, and stored on this iPhone.")
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
