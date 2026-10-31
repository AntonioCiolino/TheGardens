import SwiftUI
import PhotosUI
import ExperienceCore

struct ComposePostView: View {
    var onPublish: (String, Data?) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var isPosting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        photoSlot
                    }
                    TextField("Write something", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .textFieldStyle(.plain)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") { Task { await publish() } }
                        .disabled(isPosting || !canPost)
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else {
                    imageData = nil
                    return
                }
                Task {
                    imageData = try? await item.loadTransferable(type: Data.self)
                }
            }
        }
    }

    private var canPost: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || imageData?.isEmpty == false
    }

    @ViewBuilder
    private var photoSlot: some View {
        if let imageData, let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
                .frame(height: 180)
                .overlay {
                    Label("Add a photo", systemImage: "photo")
                        .foregroundStyle(.secondary)
                }
        }
    }

    private func publish() async {
        isPosting = true
        errorMessage = nil
        let prepared = imageData.flatMap { PostImage.jpegData(from: $0) } ?? imageData
        do {
            try await onPublish(text, prepared)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isPosting = false
        }
    }
}
