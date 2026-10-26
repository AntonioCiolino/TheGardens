import SwiftUI
import UIKit

struct SignInView: View {
    @EnvironmentObject private var session: GardensSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var testResult: String?
    @State private var isTesting = false

    var body: some View {
        List {
            Section {
                Text("Team inventory lives in iCloud. Each plant and each care update is its own record. Every iPhone needs an Apple ID signed into iCloud.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let user = session.user {
                Section("Connected") {
                    Text(user.displayName ?? "iCloud")
                    Text("Apple ID / iCloud is active on this iPhone.")
                        .foregroundStyle(.secondary)
                    Button("Use this phone only", role: .destructive) {
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
                            openURL(url)
                        }
                    } label: {
                        Label("Open Settings", systemImage: "gear")
                    }
                } footer: {
                    Text("If you aren’t signed into iCloud, open Settings → [your name] and sign in with your Apple ID. Then return here and tap Connect iCloud.")
                }
            }

            if !hasSyncTestPlant {
                Section {
                    Button {
                        isTesting = true
                        testResult = nil
                        Task {
                            let result = await session.writeTestRecord()
                            testResult = result
                            isTesting = false
                        }
                    } label: {
                        HStack {
                            Label("Write test plant + care note", systemImage: "leaf.circle")
                            if isTesting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.footnote)
                            .foregroundStyle(testResult.hasPrefix("Test OK") ? Color.primary : Color.red)
                    }
                } header: {
                    Text("Test a record")
                } footer: {
                    Text("Creates one “Gardens Sync Test” plant. This section hides once that plant is in the list.")
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
        .task {
            await session.refreshAccount()
        }
    }

    private var hasSyncTestPlant: Bool {
        session.instances.contains {
            $0.catalog.name == "Gardens Sync Test"
                && $0.catalog.genus.caseInsensitiveCompare("Testus") == .orderedSame
        }
    }
}
