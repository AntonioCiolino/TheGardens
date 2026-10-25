import SwiftUI
import UIKit

struct SignInView: View {
    @EnvironmentObject private var session: GardensSession
    @Environment(\.dismiss) private var dismiss

    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Text("Team inventory lives in iCloud (CloudKit) — one record per plant and care update. Every iPhone needs an Apple ID signed into iCloud. There is no Google login or Google cloud for Gardens.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let user = session.user {
                Section("Connected") {
                    Text(user.displayName ?? "iCloud")
                    Text("Apple ID / iCloud is active on this iPhone.")
                        .foregroundStyle(.secondary)
                    Button("Use this phone only") {
                        session.signOutLocally()
                    }
                }
            } else {
                Section {
                    Button {
                        Task { await session.refreshAccount() }
                    } label: {
                        Label("Connect iCloud", systemImage: "icloud")
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                    }
                } footer: {
                    Text("If you aren’t signed into iCloud, open Settings → [your name] and sign in with your Apple ID. Then return here and tap Connect iCloud.")
                }
            }

            Section("Test a record") {
                Button {
                    isTesting = true
                    testResult = nil
                    Task {
                        testResult = await session.writeTestRecord()
                        isTesting = false
                    }
                } label: {
                    if isTesting {
                        ProgressView()
                    } else {
                        Label("Write test plant + care note", systemImage: "leaf.circle")
                    }
                }
                .disabled(isTesting)

                if let testResult {
                    Text(testResult)
                        .font(.footnote)
                        .foregroundStyle(testResult.hasPrefix("Test OK") ? .primary : .red)
                }
            } footer: {
                Text("Creates a “Gardens Sync Test” plant (genus Testus) and a care note. On iCloud it should show in CloudKit Console → Public Database, and on the main plant list.")
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
        .task {
            await session.refreshAccount()
        }
    }
}
