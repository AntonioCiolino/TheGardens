import SwiftUI
import UIKit
import ExperienceCore

struct FeedView: View {
    @EnvironmentObject private var session: ExperienceSession
    @EnvironmentObject private var geofence: GardenGeofenceMonitor
    @State private var showingComposer = false
    @State private var showingScanner = false
    @State private var showingGuidelines = false
    @State private var scannedPlant: ScannedPlant?
    @State private var showingNoteFromJen = false
    @State private var showingAbout = false
    @State private var showingModeratorTools = false
    @State private var showingProfile = false
    @AppStorage("experience.acceptedGuidelines") private var acceptedGuidelines = false

    /// Opens the composer, first requiring agreement to the community guidelines (App Store 1.2).
    private func startNewPost() {
        if acceptedGuidelines {
            showingComposer = true
        } else {
            showingGuidelines = true
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GardensSplashGreen.ignoresSafeArea()
                BrandWatermark(opacity: 0.16)
                ScrollView {
                    LazyVStack(spacing: 22) {
                        header
                        if let status = session.statusMessage {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(.white.opacity(0.75))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let error = session.errorMessage {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if session.isLoading && session.posts.isEmpty {
                            ProgressView("Loading posts")
                                .tint(.white)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 24)
                        } else if session.posts.isEmpty {
                            Text("Nothing posted yet.")
                                .foregroundStyle(.white.opacity(0.8))
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
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("The Gardens Experience")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingProfile = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                    .accessibilityLabel("Your name")
                    Button {
                        showingScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel("Scan a plant")
                    Button {
                        startNewPost()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New post")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("About this app") { showingAbout = true }
                        Button("Preview welcome") { geofence.previewWelcome() }
                        if session.isModerator {
                            Divider()
                            Button("Moderator tools") { showingModeratorTools = true }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("More")
                }
            }
            .refreshable { await session.refresh() }
            .fullScreenCover(isPresented: $showingNoteFromJen) {
                MessageFromJenSheet()
                    .task { await session.refreshMessageOfTheDay() }
            }
            .fullScreenCover(isPresented: $showingAbout) {
                AboutThisAppView()
            }
            .sheet(isPresented: $showingModeratorTools) {
                ModeratorToolsView()
            }
            .sheet(isPresented: $showingProfile) {
                ExperienceProfileView()
            }
            .sheet(isPresented: $showingComposer) {
                ComposePostView { text, image, name in
                    try await session.publish(text: text, imageData: image, authorName: name)
                }
            }
            .sheet(isPresented: $showingGuidelines) {
                CommunityGuidelinesView {
                    acceptedGuidelines = true
                    showingGuidelines = false
                    showingComposer = true
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
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Button {
                showingNoteFromJen = true
            } label: {
                BrandLogo(height: 96)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens a note from Jen")
            Text("The Gardens Experience")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }
}

private struct AboutThisAppView: View {
    @EnvironmentObject private var session: ExperienceSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GardensSplashGreen.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    BrandLogo(height: 88)
                    Text("About this app")
                        .font(.subheadline.weight(.medium))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("The Gardens Experience is a place to slow down. Look through what people have shared, leave a photo and a few words, and scan a plant label to see its name and how to care for it.")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text("When you are here, we are glad you are here. Jen keeps The Gardens on Woodburn Avenue in Cincinnati.")
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                    if let id = session.currentUserRecordName {
                        Text(session.isModerator ? "Moderator · \(id)" : "Signed in · \(id)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .padding(.top, 24)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 72)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)

            Button("Close") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GardensSplashGreen.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

private struct MessageFromJenSheet: View {
    @EnvironmentObject private var session: ExperienceSession
    @EnvironmentObject private var geofence: GardenGeofenceMonitor
    @Environment(\.dismiss) private var dismiss

    private var authorName: String {
        session.messageOfTheDay.authorName.isEmpty ? AppVoice.authorName : session.messageOfTheDay.authorName
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GardensSplashGreen.ignoresSafeArea()
            BotanicalCorners()

            ScrollView {
                VStack(spacing: 18) {
                    Text("A note from Jen")
                        .font(.subheadline.weight(.medium))
                        .tracking(1.4)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 6)

                    GrowingCaption(
                        text: session.messageOfTheDay.text,
                        font: .title3.weight(.semibold),
                        delay: 0.15,
                        roomy: true
                    )
                    GrowingCaption(
                        text: authorName,
                        font: .footnote.weight(.medium),
                        delay: 0.55
                    )

                    if let location = geofence.statusMessage {
                        Text(location)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 28)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 72)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .scrollContentBackground(.hidden)

            Button("Close") { dismiss() }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(GardensSplashGreen.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A note from \(authorName)")
    }
}

private struct CommunityGuidelinesView: View {
    var onAgree: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Before you post")
                        .font(.title2.weight(.semibold))

                    Text("The Gardens Experience is a shared, friendly space. By posting, you agree to our community guidelines and to the terms below.")
                        .foregroundStyle(.secondary)

                    guideline("Only share photos and words you have the right to share.")
                    guideline("No objectionable, abusive, hateful, or harassing content.")
                    guideline("No nudity, violence, or illegal content.")
                    guideline("Be kind. This is a place to slow down and enjoy the garden.")

                    Text("There is zero tolerance for objectionable content or abusive behavior. You can report any post or block anyone from the “…” menu on a post. We review reports and remove violating content, and may remove contributing users, within 24 hours.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding()
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Community guidelines")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("I agree") { onAgree() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func guideline(_ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: "leaf.fill")
                .foregroundStyle(.green)
        }
    }
}

private struct ModeratorToolsView: View {
    @EnvironmentObject private var session: ExperienceSession
    @Environment(\.dismiss) private var dismiss
    @State private var newModeratorID = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if session.flaggedPosts.isEmpty {
                        Text("No reported posts right now.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(session.flaggedPosts) { post in
                            FlaggedPostRow(
                                post: post,
                                reportCount: session.reportCount(for: post),
                                onRemove: {
                                    Task { await session.removePost(post) }
                                },
                                onReinstate: {
                                    Task { await session.reinstate(post) }
                                }
                            )
                        }
                    }
                } header: {
                    Text("Reported posts")
                } footer: {
                    Text("Posts with \(ModerationPolicy.autoHideReportThreshold) or more reports are hidden from guests until you act. Removing a post deletes it for everyone.")
                }

                Section {
                    ForEach(session.moderatorRecordNames, id: \.self) { name in
                        Text(name)
                            .font(.footnote)
                            .textSelection(.enabled)
                    }
                    HStack {
                        TextField("User record name", text: $newModeratorID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.footnote)
                        Button("Add") {
                            let id = newModeratorID.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !id.isEmpty else { return }
                            Task { await session.promoteModerator(userRecordName: id) }
                            newModeratorID = ""
                        }
                        .disabled(newModeratorID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                } header: {
                    Text("Moderators")
                } footer: {
                    Text("Add a teammate by their CloudKit user record name (shown on their About screen). They can moderate as soon as they reopen the app.")
                }
            }
            .navigationTitle("Moderator tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await session.refresh() }
        }
    }
}

private struct FlaggedPostRow: View {
    let post: Post
    var reportCount: Int
    var onRemove: () -> Void
    var onReinstate: () -> Void
    @State private var confirming = false

    private var authorLabel: String {
        let name = post.authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        if let id = post.authorRecordName, !id.isEmpty { return id }
        return "Unknown author"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Posted by")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(authorLabel)
                        .font(.footnote.weight(.medium))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text("\(reportCount) report\(reportCount == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            if let data = post.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, minHeight: 160, maxHeight: 160)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !post.text.isEmpty {
                Text(post.text).font(.subheadline)
            }
            HStack(spacing: 16) {
                Button {
                    onReinstate()
                } label: {
                    Label("Keep in feed", systemImage: "checkmark.circle")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .tint(.green)

                Button(role: .destructive) {
                    confirming = true
                } label: {
                    Label("Remove for everyone", systemImage: "trash")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .confirmationDialog("Remove this post for everyone?", isPresented: $confirming, titleVisibility: .visible) {
                    Button("Remove", role: .destructive, action: onRemove)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This deletes the post from the shared feed for all guests. This can’t be undone.")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ScannedPlant: Identifiable {
    let id: UUID
}

private struct PostCard: View {
    let post: Post
    @EnvironmentObject private var session: ExperienceSession
    @State private var zoomImage: UIImage?
    @State private var showingReportReasons = false
    @State private var showingBlockConfirm = false
    @State private var showingRemoveConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let imageData = post.imageData, let image = UIImage(data: imageData) {
                Button {
                    zoomImage = image
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, minHeight: 320, maxHeight: 320)
                        .clipped()
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo. Tap to zoom")
            }
            if !post.text.isEmpty {
                Text(post.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
            }
            HStack {
                if session.isAwaitingReview(post) {
                    Label("Reported", systemImage: "flag.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if !post.authorName.isEmpty {
                    Text(post.authorName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                } else if let authorRecordName = post.authorRecordName, !authorRecordName.isEmpty {
                    if session.isModerator {
                        Text(authorRecordName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("iCloud")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Text(post.createdAt, format: .relative(presentation: .named))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                moderationMenu
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
        .background(Color(red: 0.96, green: 0.97, blue: 0.95), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.colorScheme, .light)
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .confirmationDialog("Report this post", isPresented: $showingReportReasons, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.label) {
                    Task { await session.report(post, reason: reason) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We review reports and remove objectionable content within 24 hours.")
        }
        .confirmationDialog("Block this person?", isPresented: $showingBlockConfirm, titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                Task { await session.block(post) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won’t see any posts from this person on this iPhone.")
        }
        .confirmationDialog("Remove this post for everyone?", isPresented: $showingRemoveConfirm, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                Task { await session.removePost(post) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the post from the shared feed for all guests. This can’t be undone.")
        }
        .fullScreenCover(isPresented: Binding(
            get: { zoomImage != nil },
            set: { if !$0 { zoomImage = nil } }
        )) {
            if let zoomImage {
                PhotoZoomCover(image: zoomImage)
            }
        }
    }

    private var moderationMenu: some View {
        Menu {
            if session.isModerator {
                Button(role: .destructive) {
                    showingRemoveConfirm = true
                } label: {
                    Label("Remove post (moderator)", systemImage: "trash")
                }
                Divider()
            }
            Button(role: .destructive) {
                showingReportReasons = true
            } label: {
                Label("Report post", systemImage: "flag")
            }
            if let author = post.authorRecordName, !author.isEmpty {
                Button(role: .destructive) {
                    showingBlockConfirm = true
                } label: {
                    Label("Block this person", systemImage: "hand.raised")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Report or block")
    }
}

private struct PhotoZoomCover: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            PhotoZoomView(image: image)
                .ignoresSafeArea()
            Button("Close") { dismiss() }
                .font(.body.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())
                .padding()
        }
        .background(Color.black.ignoresSafeArea())
    }
}

private struct PhotoZoomView: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> PhotoZoomScrollView {
        PhotoZoomScrollView(image: image)
    }

    func updateUIView(_ view: PhotoZoomScrollView, context: Context) {}
}

private final class PhotoZoomScrollView: UIScrollView, UIScrollViewDelegate {
    private let imageView = UIImageView()

    init(image: UIImage) {
        super.init(frame: .zero)
        delegate = self
        minimumZoomScale = 1
        maximumZoomScale = 5
        bouncesZoom = true
        backgroundColor = .black
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        addSubview(imageView)
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        addGestureRecognizer(doubleTap)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard zoomScale == 1, bounds.width > 0, let image = imageView.image else { return }
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        let size = CGSize(width: image.size.width * fit, height: image.size.height * fit)
        imageView.frame = CGRect(origin: .zero, size: size)
        contentSize = size
        centerImage()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    private func centerImage() {
        let extraX = max(0, bounds.width - contentSize.width)
        let extraY = max(0, bounds.height - contentSize.height)
        contentInset = UIEdgeInsets(top: extraY / 2, left: extraX / 2, bottom: extraY / 2, right: extraX / 2)
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if zoomScale > 1 {
            setZoomScale(1, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: bounds.width / 2.5, height: bounds.height / 2.5)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}
