import UIKit

extension UIImage {
    /// Compress image for LLM transmission (JPEG at configured quality)
    func compressForLLM() -> Data? {
        return jpegData(compressionQuality: Constants.Video.jpegQuality)
    }

    /// Compress and resize image for optimal storage and transmission
    /// - Parameter maxWidth: Maximum width in pixels (default: 800)
    /// - Returns: Compressed PNG data
    func compressForStorage(maxWidth: CGFloat = 800) -> Data? {
        // Calculate scale to maintain aspect ratio
        let scale = min(maxWidth / size.width, 1.0)

        // Skip resize if already small enough
        guard scale < 1.0 else {
            return pngData()
        }

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        // Resize image
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        draw(in: CGRect(origin: .zero, size: newSize))
        guard let resized = UIGraphicsGetImageFromCurrentImageContext() else {
            return nil
        }

        return resized.pngData()
    }

    /// Get estimated memory size in MB
    var estimatedMemorySizeMB: Double {
        guard let cgImage = cgImage else { return 0 }
        let bytes = cgImage.bytesPerRow * cgImage.height
        return Double(bytes) / 1_048_576  // Convert to MB
    }
}
