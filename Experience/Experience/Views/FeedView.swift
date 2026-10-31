import SwiftUI
import UIKit
import ExperienceCore

struct FeedView: View {
    @EnvironmentObject private var session: ExperienceSession
    @EnvironmentObject private var geofence: GardenGeofenceMonitor
    @State private var showingComposer = false
    @State private var showingScanner = false
    @State private var scannedPlant: ScannedPlant?

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 22) {
                    header
                    if let status = session.statusMessage {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let location = geofence.statusMessage {
                        Text(location)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = session.errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if session.isLoading && session.posts.isEmpty {
                        ProgressView("Loading posts")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if session.posts.isEmpty {
                        Text("Nothing posted yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        ForEach(session.posts) { post in
                            PostCard(post: post)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemBackground))
            .gardensBrandWatermark()
            .navigationTitle("The Gardens Experience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel("Scan a plant")
                    Button {
                        showingComposer = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New post")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Preview welcome") { geofence.previewWelcome() }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .refreshable { await session.refresh() }
            .sheet(isPresented: $showingComposer) {
                ComposePostView { text, image in
                    try await session.publish(text: text, imageData: image)
                }
            }
            .fullScreenCover(isPresented: $showingScanner) {
                PlantScanCover { id in
                    scannedPlant = ScannedPlant(id: id)
                    showingScanner = false
                }
            }
            .fullScreenCover(item: $scannedPlant) { plant in
                GuestPlantView(instanceID: plant.id) {
                    scannedPlant = nil
                }
            }
            .overlay {
                if let place = geofence.welcomePlace {
                    WelcomeBounceOverlay(placeName: place.name) {
                        geofence.dismissWelcome()
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            BrandLogo(height: 96)
            Text("The Gardens Experience")
                .font(.title2.weight(.semibold))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct ScannedPlant: Identifiable {
    let id: UUID
}

private struct PostCard: View {
    let post: Post

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageData = post.imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
                    .clipped()
            }
            if !post.text.isEmpty {
                Text(post.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            HStack {
                if let authorRecordName = post.authorRecordName, !authorRecordName.isEmpty {
                    Text("iCloud")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(post.createdAt, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            if post.pendingUpload {
                Text("Waiting to sync")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private extension View {
    func gardensBrandWatermark() -> some View {
        background { BrandWatermark() }
    }
}
