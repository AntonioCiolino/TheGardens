import SwiftUI
import PhotosUI
import UIKit
import ExperienceCore

struct ComposePostView: View {
    var onPublish: (String, Data?, String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @AppStorage("experience.authorName") private var authorName = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var showCamera = false
    @State private var isPosting = false
    @State private var errorMessage: String?
    @FocusState private var captionFocused: Bool
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photoSlot
                        .onTapGesture { captionFocused = false }
                    HStack(spacing: 12) {
                        Button {
                            showCamera = true
                        } label: {
                            Label(imageData == nil ? "Take photo" : "Retake", systemImage: "camera")
                        }
                        .buttonStyle(GardenPhotoButtonStyle())
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Choose photo", systemImage: "photo.on.rectangle")
                        }
                        .buttonStyle(GardenPhotoButtonStyle())
                    }
                    TextField("Your name (optional)", text: $authorName)
                        .textContentType(.name)
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .padding(12)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    TextField("Write a few words under the photo", text: $text, axis: .vertical)
                        .lineLimit(4...8)
                        .textFieldStyle(.plain)
                        .focused($captionFocused)
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
            .scrollDismissesKeyboard(.immediately)
            .scrollContentBackground(.hidden)
            .background(GardensSplashGreen.ignoresSafeArea())
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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        captionFocused = false
                        nameFocused = false
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    imageData = try? await item.loadTransferable(type: Data.self)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                PostCameraPicker { data in
                    imageData = data
                }
                .ignoresSafeArea()
            }
        }
    }

    private var canPost: Bool {
        imageData?.isEmpty == false && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                .fill(Color(red: 0.96, green: 0.97, blue: 0.95))
                .frame(height: 180)
                .overlay {
                    Label("Add a photo", systemImage: "camera")
                        .foregroundStyle(Color(red: 0.12, green: 0.18, blue: 0.13))
                }
        }
    }

    private func publish() async {
        isPosting = true
        errorMessage = nil
        let prepared = imageData.flatMap { PostImage.jpegData(from: $0) } ?? imageData
        let name = authorName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onPublish(text, prepared, name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isPosting = false
        }
    }
}

private struct GardenPhotoButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Color(red: 0.12, green: 0.18, blue: 0.13))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

private struct PostCameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: PostCameraPicker

        init(parent: PostCameraPicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.82) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }
    }
}
