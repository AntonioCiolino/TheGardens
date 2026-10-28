import AVFoundation
import SwiftUI

/// Live camera preview that detects QR codes via AVFoundation.
struct PlantQRScannerView: UIViewRepresentable {
    var isActive: Bool = true
    var onCode: (String) -> Void

    func makeUIView(context: Context) -> ScannerPreviewView {
        let view = ScannerPreviewView()
        view.onCode = onCode
        context.coordinator.preview = view
        context.coordinator.isActive = isActive
        return view
    }

    func updateUIView(_ uiView: ScannerPreviewView, context: Context) {
        uiView.onCode = onCode
        guard context.coordinator.isActive != isActive else { return }
        context.coordinator.isActive = isActive
        if isActive {
            uiView.start()
        } else {
            uiView.stop()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var preview: ScannerPreviewView?
        var isActive = true
    }
}

final class ScannerPreviewView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var lastEmitted: String?
    private var lastEmitAt: Date = .distantPast
    private let sessionQueue = DispatchQueue(label: "gardens.qr.scanner")

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    private var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        videoPreviewLayer.videoGravity = .resizeAspectFill
        configureSession()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        sessionQueue.async { [session] in
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            start()
        } else {
            stop()
        }
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.session.startRunning()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high

        guard
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
            let input = try? AVCaptureDeviceInput(device: device),
            session.canAddInput(input)
        else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        if output.availableMetadataObjectTypes.contains(.qr) {
            output.metadataObjectTypes = [.qr]
        }

        session.commitConfiguration()
        videoPreviewLayer.session = session
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard
            let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
            object.type == .qr,
            let value = object.stringValue,
            !value.isEmpty
        else { return }

        // Debounce identical codes
        let now = Date()
        if value == lastEmitted, now.timeIntervalSince(lastEmitAt) < 1.5 {
            return
        }
        lastEmitted = value
        lastEmitAt = now
        onCode?(value)
    }
}

enum CameraPermission {
    static func ensureAuthorized() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
