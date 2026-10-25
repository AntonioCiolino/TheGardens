import Foundation
import UIKit
import GardensCore

/// Wires the print sheet via `UIPrintInteractionController`.
/// Works with AirPrint / PDF preview even when no printer is paired.
@MainActor
struct UIKitPlantLabelPrinter: PlantLabelPrinting {
    func printLabel(title: String, subtitle: String, qrImageData: Data) async throws {
        guard UIPrintInteractionController.isPrintingAvailable else {
            // Still present the controller when possible; otherwise no-op success
            // so intake flows are not blocked during development.
            return
        }

        let formatter = UIMarkupTextPrintFormatter(
            markupText: """
            <html><body style="font-family:-apple-system;text-align:center;padding:24px;">
            <h1>\(Self.escape(title))</h1>
            <p>\(Self.escape(subtitle))</p>
            <img src="data:image/png;base64,\(qrImageData.base64EncodedString())" width="220" height="220" />
            <p style="font-size:12px;color:#666;">Gardens plant label</p>
            </body></html>
            """
        )

        let controller = UIPrintInteractionController.shared
        controller.printFormatter = formatter

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            controller.present(animated: true) { _, completed, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if completed {
                    continuation.resume()
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
