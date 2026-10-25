import Foundation
import UIKit
import GardensCore

/// Wires the print sheet via `UIPrintInteractionController`.
/// Works with AirPrint / PDF preview even when no printer is paired.
@MainActor
struct UIKitPlantLabelPrinter: PlantLabelPrinting {
    func printLabel(title: String, subtitle: String, qrImageData: Data) async throws {
        try await printLabels(title: title, subtitle: subtitle, qrImageDataList: [qrImageData])
    }

    func printLabels(title: String, subtitle: String, qrImageDataList: [Data]) async throws {
        guard !qrImageDataList.isEmpty else { return }

        let imagesHTML = qrImageDataList.enumerated().map { index, data in
            """
            <div style="page-break-after:always;text-align:center;padding:24px 0;">
              <h2 style="margin:0 0 4px;">\(Self.escape(title))</h2>
              <p style="margin:0 0 12px;color:#555;">\(Self.escape(subtitle)) · \(index + 1)/\(qrImageDataList.count)</p>
              <img src="data:image/png;base64,\(data.base64EncodedString())" width="220" height="220" />
              <p style="font-size:12px;color:#666;">Gardens plant label</p>
            </div>
            """
        }.joined()

        let formatter = UIMarkupTextPrintFormatter(
            markupText: """
            <html><body style="font-family:-apple-system;">
            \(imagesHTML)
            </body></html>
            """
        )

        let controller = UIPrintInteractionController.shared
        controller.printFormatter = formatter

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controller.present(animated: true) { _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
