import AppKit
import ImageIO

final class ImageCache {
    static let shared = ImageCache()

    private let thumbCache = NSCache<NSURL, NSImage>()
    private let previewCache = NSCache<NSURL, NSImage>()

    // サムネイル用: 並列数を制限してI/Oを詰まらせない
    private let thumbQueue = DispatchQueue(
        label: "ImageCache.thumb",
        qos: .userInteractive,
        attributes: .concurrent
    )
    private let previewQueue = DispatchQueue(
        label: "ImageCache.preview",
        qos: .userInitiated,
        attributes: .concurrent
    )
    // 同じURLへの重複リクエストを防ぐセット
    private var inFlight = Set<URL>()
    private let inFlightLock = NSLock()

    private init() {
        thumbCache.countLimit = 800
        previewCache.countLimit = 40
        thumbCache.totalCostLimit   = 150 * 1024 * 1024
        previewCache.totalCostLimit = 400 * 1024 * 1024
    }

    // MARK: - サムネイル（非同期）

    func thumbnail(for url: URL, completion: @escaping (NSImage?) -> Void) {
        let key = url as NSURL

        // キャッシュヒット → 即返す
        if let cached = thumbCache.object(forKey: key) {
            completion(cached)
            return
        }

        // 重複リクエスト防止
        inFlightLock.lock()
        let alreadyLoading = inFlight.contains(url)
        if !alreadyLoading { inFlight.insert(url) }
        inFlightLock.unlock()
        guard !alreadyLoading else { return }

        thumbQueue.async { [weak self] in
            guard let self else { return }
            let img = self.loadImage(url: url, maxPixelSize: 200)
            if let img {
                self.thumbCache.setObject(img, forKey: key)
            }
            self.inFlightLock.lock()
            self.inFlight.remove(url)
            self.inFlightLock.unlock()
            DispatchQueue.main.async { completion(img) }
        }
    }

    // MARK: - プレビュー（非同期）

    func preview(for url: URL, completion: @escaping (NSImage?) -> Void) {
        let key = url as NSURL
        if let cached = previewCache.object(forKey: key) {
            completion(cached)
            return
        }
        previewQueue.async { [weak self] in
            guard let self else { return }
            let img = self.loadImage(url: url, maxPixelSize: 1600)
            if let img { self.previewCache.setObject(img, forKey: key) }
            DispatchQueue.main.async { completion(img) }
        }
    }

    // MARK: - プリフェッチ（並列）

    func prefetch(urls: [URL]) {
        // DispatchGroup で並列ロード（最大8並列）
        let semaphore = DispatchSemaphore(value: 8)
        for url in urls {
            let key = url as NSURL
            guard thumbCache.object(forKey: key) == nil else { continue }
            thumbQueue.async { [weak self] in
                semaphore.wait()
                defer { semaphore.signal() }
                guard let self else { return }
                guard self.thumbCache.object(forKey: key) == nil else { return }
                if let img = self.loadImage(url: url, maxPixelSize: 200) {
                    self.thumbCache.setObject(img, forKey: key)
                }
            }
        }
    }

    func clearPreview(for url: URL) {
        previewCache.removeObject(forKey: url as NSURL)
    }

    // MARK: - ImageIO ダウンサイズ読み込み

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