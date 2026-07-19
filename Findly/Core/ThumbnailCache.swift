import UIKit
import ImageIO

/// Shared decoded-UIImage cache. Decodes via ImageIO at display resolution so the
/// full-resolution bitmap is never allocated. A 50 MB cost limit and automatic
/// memory-warning eviction keep RAM under control.
final class ThumbnailCache {

    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.totalCostLimit = 50 * 1024 * 1024 // 50 MB hard cap
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    /// Returns a UIImage for `id`, decoding from `data` at `targetSize` on first access.
    /// Subsequent calls with the same `id` return the cached bitmap without re-decoding.
    func image(for id: UUID, data: Data, targetSize: CGSize) -> UIImage? {
        let maxPixels = Int(max(targetSize.width, targetSize.height) * UIScreen.main.scale)
        let key = "\(id.uuidString)-\(maxPixels)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        cache.setObject(image, forKey: key, cost: cgImage.width * cgImage.height * 4)
        return image
    }

    func evict(_ id: UUID) {
        cache.removeObject(forKey: id.uuidString as NSString)
    }

    // MARK: - Thumbnail generation

    /// Generates a downsampled JPEG for storage as a thumbnail.
    /// Uses ImageIO to avoid decoding the full-resolution bitmap at any point.
    /// - Parameter maxPixels: Maximum pixels on the longest edge (default 560 → ≤280 pt @2×).
    static func makeThumbnailData(_ data: Data, maxPixels: Int = 560) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceShouldCache: false
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7)
    }
}
