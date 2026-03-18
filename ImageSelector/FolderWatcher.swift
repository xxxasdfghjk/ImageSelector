import Foundation

/// 指定フォルダをカーネルレベルで監視し、変化があったらコールバックを呼ぶ
final class FolderWatcher {
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    /// フォルダ監視を開始
    /// - Parameters:
    ///   - url: 監視するフォルダのURL
    ///   - debounce: 連続変化をまとめる待機時間（秒）
    ///   - onChange: 変化検知時に**メインスレッド**で呼ばれるコールバック
    func start(url: URL, debounce: TimeInterval = 0.5, onChange: @escaping () -> Void) {
        stop()

        fileDescriptor = open(url.path, O_EVTONLY)
        guard fileDescriptor >= 0 else {
            print("[FolderWatcher] open failed: \(url.path)")
            return
        }

        var debounceItem: DispatchWorkItem?

        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete, .attrib],
            queue: DispatchQueue.global(qos: .utility)
        )

        source?.setEventHandler {
            debounceItem?.cancel()
            let item = DispatchWorkItem {
                DispatchQueue.main.async { onChange() }
            }
            debounceItem = item
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + debounce, execute: item
            )
        }

        source?.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptor, fd >= 0 {
                close(fd)
                self?.fileDescriptor = -1
            }
        }

        source?.resume()
        print("[FolderWatcher] 監視開始: \(url.lastPathComponent)")
    }

    func stop() {
        source?.cancel()
        source = nil
    }

    deinit { stop() }
}
