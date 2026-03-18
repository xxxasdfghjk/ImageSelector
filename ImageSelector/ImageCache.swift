import AppKit
import ImageIO

/// サムネイル・プレビュー画像をメモリにキャッシュするシングルトン
/// ImageIO でダウンサイズしながら読み込むので、フル解像度を展開しない
final class ImageCache {
    static let shared = ImageCache()

    // サムネイル用（100×100相当）
    private let thumbCache = NSCache<NSURL, NSImage>()
    // プレビュー用（1200px相当）
    private let previewCache = NSCache<NSURL, NSImage>()

    private let queue = DispatchQueue(label: "ImageCache", qos: .userInitiated, attributes: .concurrent)

    private init() {
        thumbCache.countLimit = 500        // 最大500枚
        previewCache.countLimit = 30       // プレビューは重いので少なめ
        thumbCache.totalCostLimit   = 100 * 1024 * 1024  // 100MB
        previewCache.totalCostLimit = 300 * 1024 * 1024  // 300MB
    }

    // MARK: - サムネイル（同期・キャッシュ済みならすぐ返る）

    func thumbnail(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let img = loadImage(url: url, maxPixelSize: 200) else { return nil }
        thumbCache.setObject(img, forKey: key)
        return img
    }

    // MARK: - プレビュー（非同期・完了後にコールバック）

    func preview(for url: URL, completion: @escaping (NSImage?) -> Void) {
        let key = url as NSURL
        if let cached = previewCache.object(forKey: key) {
            completion(cached)
            return
        }
        queue.async {
            let img = self.loadImage(url: url, maxPixelSize: 1600)
            if let img {
                self.previewCache.setObject(img, forKey: key)
            }
            DispatchQueue.main.async { completion(img) }
        }
    }

    // MARK: - プリフェッチ（バックグラウンドで先読み）

    func prefetch(urls: [URL]) {
        queue.async {
            for url in urls {
                let key = url as NSURL
                guard self.thumbCache.object(forKey: key) == nil else { continue }
                if let img = self.loadImage(url: url, maxPixelSize: 200) {
                    self.thumbCache.setObject(img, forKey: key)
                }
            }
        }
    }

    func clearPreview(for url: URL) {
        previewCache.removeObject(forKey: url as NSURL)
    }

    // MARK: - ImageIO でダウンサイズ読み込み

    private func loadImage(url: URL, maxPixelSize: Int) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cgImage, size: .zero)
    }
}
