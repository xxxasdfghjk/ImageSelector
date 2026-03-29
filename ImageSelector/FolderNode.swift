import Foundation
import Combine

/// フォルダツリーの1ノード
final class FolderNode: ObservableObject, Identifiable {
    let id: URL          // URLをIDに使用
    let url: URL
    let name: String

    @Published var children: [FolderNode]?   // nil = 未展開, [] = 子なし
    @Published var isExpanded: Bool = false

    init(url: URL) {
        self.url  = url
        self.name = url.lastPathComponent
        self.id   = url
    }

    /// 子フォルダを読み込む
    /// - Parameter expandAfterLoad: 読み込み完了後に isExpanded を true にする
    func loadChildren(expandAfterLoad: Bool = false) {
        print("[FolderNode] loadChildren called: \(url.lastPathComponent) expandAfterLoad=\(expandAfterLoad) children=\(children == nil ? "nil" : "\(children!.count)件")")
        guard children == nil else {
            print("[FolderNode] already loaded, skip. isExpanded=\(isExpanded)")
            if expandAfterLoad { isExpanded = true }
            return
        }
        let fm = FileManager.default

        do {
            let contents = try fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            print("[FolderNode] contentsOfDirectory 成功: \(contents.count)件 in \(url.path)")

            let dirs = contents
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
                .map { FolderNode(url: $0) }

            print("[FolderNode] サブフォルダ数: \(dirs.count)")

            DispatchQueue.main.async {
                print("[FolderNode] main.async: children をセット \(dirs.count)件, expandAfterLoad=\(expandAfterLoad)")
                self.children = dirs
                if expandAfterLoad { self.isExpanded = true }
                print("[FolderNode] セット後 isExpanded=\(self.isExpanded) children=\(self.children?.count ?? -1)件")
            }
        } catch {
            print("[FolderNode] contentsOfDirectory 失敗: \(error)")
            DispatchQueue.main.async {
                self.children = []
                if expandAfterLoad { self.isExpanded = true }
            }
        }
    }

    // MARK: - 再スキャン

    /// ツリー全体を再スキャンして新規フォルダを追加する（読み込み済みのノードのみ対象）
    /// - Parameter completion: メインスレッドで呼ばれる完了コールバック。追加されたフォルダ数を渡す。
    func rescan(completion: @escaping (Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            var addedCount = 0
            self.rescanRecursive(added: &addedCount)
            DispatchQueue.main.async {
                completion(addedCount)
            }
        }
    }

    /// 再帰的にスキャン（バックグラウンドスレッドで呼ぶこと）
    private func rescanRecursive(added: inout Int) {
        let fm = FileManager.default

        guard let currentChildren = children else {
            // まだ一度も展開されていないノードはスキップ
            return
        }

        // 現在のディスク上のサブフォルダ一覧を取得
        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let diskDirs = contents
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        // 既存の子URLセット
        let existingURLs = Set(currentChildren.map { $0.url })

        // 新規フォルダを検出
        let newDirs = diskDirs.filter { !existingURLs.contains($0) }

        if !newDirs.isEmpty {
            let newNodes = newDirs.map { FolderNode(url: $0) }
            added += newNodes.count

            DispatchQueue.main.sync {
                var merged = currentChildren + newNodes
                merged.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.children = merged
            }
        }

        // 削除されたフォルダを除去
        let diskURLSet = Set(diskDirs.map { $0 })
        let removedURLs = existingURLs.subtracting(diskURLSet)
        if !removedURLs.isEmpty {
            DispatchQueue.main.sync {
                self.children = self.children?.filter { !removedURLs.contains($0.url) }
            }
        }

        // 既存の子を再帰的にスキャン（展開済みのみ）
        // ※ main.sync 後に children を再取得してイテレート
        let latestChildren: [FolderNode] = {
            var result: [FolderNode] = []
            DispatchQueue.main.sync { result = self.children ?? [] }
            return result
        }()

        for child in latestChildren {
            child.rescanRecursive(added: &added)
        }
    }

    /// 画像ファイルを含むかチェック（フォルダに画像があるか表示用）
    var hasImages: Bool {
        let fm = FileManager.default
        let exts: Set<String> = ["png","jpg","jpeg","webp","gif","tiff","heic"]
        return ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .contains { exts.contains($0.pathExtension.lowercased()) }
    }
}

extension FolderNode {
    /// 展開済みノードのURLを再帰的に収集
    func collectExpanded() -> [URL] {
        guard isExpanded else { return [] }
        var result = [url]
        for child in children ?? [] {
            result += child.collectExpanded()
        }
        return result
    }

    /// 保存された展開パスに従って再帰的に展開
    func restoreExpanded(paths: Set<String>, completion: @escaping () -> Void) {
        guard paths.contains(url.path) else {
            completion()
            return
        }
        loadChildren(expandAfterLoad: true)
        // 子のロード完了を待って再帰
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for child in self.children ?? [] {
                child.restoreExpanded(paths: paths) {}
            }
            completion()
        }
    }
}
