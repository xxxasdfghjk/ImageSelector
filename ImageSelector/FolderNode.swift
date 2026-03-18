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

        // contentsOfDirectory の生の結果とエラーを確認
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

    /// 画像ファイルを含むかチェック（フォルダに画像があるか表示用）
    var hasImages: Bool {
        let fm = FileManager.default
        let exts: Set<String> = ["png","jpg","jpeg","webp","gif","tiff","heic"]
        return ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? [])
            .contains { exts.contains($0.pathExtension.lowercased()) }
    }
}
