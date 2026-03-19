import Foundation

/// 起動間をまたいでセッション状態を保存・復元する
struct SessionStore {
    private static let rootBookmarkKey  = "rootFolderBookmark"
    private static let expandedURLsKey  = "expandedFolderURLs"
    private static let selectedGroupKey = "selectedGroupID"
    private static let selectedFolderKey  = "selectedFolderBookmark"

    // MARK: - ルートフォルダ

    static func saveRoot(url: URL) {
        guard let data = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        UserDefaults.standard.set(data, forKey: rootBookmarkKey)
    }

    /// 保存済みルートフォルダを復元。アクセス権も取得して返す。
    static func restoreRoot() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: rootBookmarkKey) else { return nil }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if isStale { saveRoot(url: url) } // ブックマークを更新
        return url
    }

    // MARK: - 展開済みフォルダ

    static func saveExpanded(urls: [URL]) {
        let paths = urls.map { $0.path }
        UserDefaults.standard.set(paths, forKey: expandedURLsKey)
    }

    static func restoreExpanded() -> Set<String> {
        let paths = UserDefaults.standard.stringArray(forKey: expandedURLsKey) ?? []
        return Set(paths)
    }

    // MARK: - 選択フォルダ（画像が入っていたフォルダ）

    static func saveSelectedFolder(url: URL) {
        print("[SessionStore] saveSelectedFolder: \(url.path)")
        UserDefaults.standard.set(url.path, forKey: selectedFolderKey)
        UserDefaults.standard.synchronize()
    }

    static func restoreSelectedFolder() -> URL? {
        let raw = UserDefaults.standard.string(forKey: selectedFolderKey)
        print("[SessionStore] restoreSelectedFolder raw=\(raw ?? "nil")")
        guard let path = raw else { return nil }
        guard FileManager.default.isReadableFile(atPath: path) else {
            print("[SessionStore] selectedFolder not readable: \(path)")
            return nil
        }
        return URL(fileURLWithPath: path)
    }

    // MARK: - 選択グループ

    static func saveSelectedGroup(id: String?) {
        UserDefaults.standard.set(id, forKey: selectedGroupKey)
    }

    static func restoreSelectedGroupID() -> String? {
        UserDefaults.standard.string(forKey: selectedGroupKey)
    }
}