import Foundation
import CoreImage.CIFilterBuiltins
import UIKit

/// Enables export of public encryption + signing keys as a QR code for trusted third-party recovery.
/// The private keys never leave the device — only the public keys are exported.
class KeyRecoveryService {
    // MARK: - Recovery Bundle

    struct RecoveryBundle: Codable {
        let rsaPublicKey: Data           // RSA-4096 public key (for key wrapping)
        let signingPublicKey: Data       // P256 signing public key (for signature verification)
        let deviceName: String
        let exportDate: Date
    }

    // MARK: - Public API

    /// Creates a recovery bundle containing both public keys from the encryption service.
    static func createRecoveryBundle(from encryptionService: EncryptionService) -> RecoveryBundle? {
        guard let rsaKey = encryptionService.exportPublicKey(),
              let signingKey = encryptionService.exportSigningPublicKey() else {
            debugLog("[KeyRecovery] Failed to export keys — keys not yet generated")
            return nil
        }

        return RecoveryBundle(
            rsaPublicKey: rsaKey,
            signingPublicKey: signingKey,
            deviceName: UIDevice.current.name,
            exportDate: Date()
        )
    }

    /// Generates a QR code image from a recovery bundle.
    static func generateQRCode(from bundle: RecoveryBundle) -> UIImage? {
        guard let jsonData = try? JSONEncoder().encode(bundle) else { return nil }
        let base64 = jsonData.base64EncodedString()

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(base64.utf8)
        filter.correctionLevel = "H" // High error correction (30%)

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for display (QR codes are tiny by default)
        let scale: CGFloat = 10
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    /// Imports a recovery bundle from a Base64-encoded QR string (for future scanner feature).
    static func importBundle(from qrString: String) -> RecoveryBundle? {
        guard let data = Data(base64Encoded: qrString),
              let bundle = try? JSONDecoder().decode(RecoveryBundle.self, from: data) else {
            return nil
        }
        return bundle
    }
}
