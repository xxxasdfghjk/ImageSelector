import Foundation
import SwiftUI
import Combine

enum ActivePanel { case folder, group }

class ImageStore: ObservableObject {
    @Published var groups: [ImageGroup] = []
    @Published var selectedGroup: ImageGroup?

    private var folderURL: URL?
    private var saveCancellable: AnyCancellable?
    private let watcher = FolderWatcher()
    @Published var lastGroupMoveDelta: Int = 1  // 最後の移動方向（正=下、負=上）
    @Published var activePanel: ActivePanel = .folder  // フォーカス中のパネル

    // MARK: - フォルダ読み込み

    func loadFolder(url: URL) {
        // 以前のスコープを解放してから新しいフォルダを登録
        folderURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }

        let items = files.compactMap { Parser.parse(url: $0) }
        let grouped = Dictionary(grouping: items) { $0.groupId }

        // 保存済みマークを読み込む
        let savedMarks = MarkStore.load(folderURL: url)

        let groups = grouped.map { entry -> ImageGroup in
            let key = entry.key
            let rawItems = entry.value
            let sorted = rawItems
                .sorted { $0.timestamp < $1.timestamp }
                .map { item -> ImageItem in
                    // ファイル名でマークを復元
                    var restored = item
                    if let mark = savedMarks[item.url.lastPathComponent] {
                        restored.mark = mark
                    }
                    return restored
                }
            return ImageGroup(id: key, images: sorted, prompt: rawItems[0].prompt)
        }

        let sortedGroups = groups.sorted { $0.id < $1.id }

        DispatchQueue.main.async {
            self.groups = sortedGroups
            self.selectedGroup = sortedGroups.first
            self.selectedGroup?.focusedImage = sortedGroups.first?.images.first
            // activePanel はここでは変更しない（フォルダツリー側のフォーカスを維持）

            // グループのマーク変更を監視して自動保存
            self.observeMarkChanges()

            // フォルダの変化をリアルタイム監視
            self.watcher.start(url: url) { [weak self] in
                guard let self, let url = self.folderURL else { return }
                print("[ImageStore] フォルダ変化を検知、リロード: \(url.lastPathComponent)")
                self.reloadFolder(url: url)
            }
        }
    }

    /// マーク情報を保持したままファイル一覧だけ更新する
    private func reloadFolder(url: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return }

        let items = files.compactMap { Parser.parse(url: $0) }
        let grouped = Dictionary(grouping: items) { $0.groupId }
        let savedMarks = MarkStore.load(folderURL: url)

        // 既存グループのマーク情報を保持するため現在の状態を退避
        var existingMarks: [String: ImageMark] = [:]
        for group in groups {
            for item in group.images where item.mark != .none {
                existingMarks[item.url.lastPathComponent] = item.mark
            }
        }

        let newGroups = grouped.map { entry -> ImageGroup in
            let key = entry.key
            let rawItems = entry.value
            let sorted = rawItems
                .sorted { $0.timestamp < $1.timestamp }
                .map { item -> ImageItem in
                    var restored = item
                    // メモリ上のマーク → 保存済みマークの順で優先
                    restored.mark = existingMarks[item.url.lastPathComponent]
                        ?? savedMarks[item.url.lastPathComponent]
                        ?? .none
                    return restored
                }
            return ImageGroup(id: key, images: sorted, prompt: rawItems[0].prompt)
        }

        let sortedGroups = newGroups.sorted { $0.id < $1.id }

        // 選択中グループを維持
        let prevSelectedID = self.selectedGroup?.id
        let prevFocusedURL = self.selectedGroup?.focusedImage?.url

        self.groups = sortedGroups
        self.selectedGroup = sortedGroups.first { $0.id == prevSelectedID } ?? sortedGroups.first
        if let focusURL = prevFocusedURL {
            self.selectedGroup?.focusedImage = self.selectedGroup?.images.first { $0.url == focusURL }
                ?? self.selectedGroup?.images.first
        } else {
            self.selectedGroup?.focusedImage = self.selectedGroup?.images.first
        }
        self.observeMarkChanges()
    }

    // MARK: - マーク変更の監視と自動保存

    private func observeMarkChanges() {
        // 全グループの objectWillChange をマージして監視
        let publishers = groups.map { $0.objectWillChange.map { _ in () }.eraseToAnyPublisher() }
        guard !publishers.isEmpty else { return }

        saveCancellable = Publishers.MergeMany(publishers)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.saveMarks()
            }
    }

    private func saveMarks() {
        guard let url = folderURL else { return }
        MarkStore.save(groups: groups, folderURL: url)
    }

    // MARK: - 操作

    func setMark(_ mark: ImageMark) {
        guard let group = selectedGroup,
              let item = group.focusedImage else { return }
        group.setMark(mark, for: item)
    }

    func moveFocus(by delta: Int) {
        guard let group = selectedGroup else { return }
        let images = group.images
        guard !images.isEmpty else { return }
        let current = group.focusedImage.flatMap { images.firstIndex(of: $0) } ?? 0
        // 端でラップアラウンド
        let next = (current + delta + images.count) % images.count
        group.focusedImage = images[next]
    }

    func moveGroup(by delta: Int) {
        guard !groups.isEmpty else { return }
        lastGroupMoveDelta = delta
        activePanel = .group
        let current = selectedGroup.flatMap { g in groups.firstIndex(where: { $0.id == g.id }) } ?? 0
        let next = max(0, min(groups.count - 1, current + delta))
        selectedGroup = groups[next]
        if selectedGroup?.focusedImage == nil {
            selectedGroup?.focusedImage = selectedGroup?.images.first
        }
        // 切替先をプリフェッチ
        if let urls = selectedGroup?.images.map({ $0.url }) {
            ImageCache.shared.prefetch(urls: urls)
        }
        // 次のグループも先読み
        let nextNext = min(next + 1, groups.count - 1)
        if nextNext != next {
            ImageCache.shared.prefetch(urls: groups[nextNext].images.map { $0.url })
        }
    }
}

extension ImageStore {
    /// 現在のグループより後で、赤マークが1枚もないグループへジャンプ。
    /// 末尾まで見つからなければ先頭から折り返して探す。
    func jumpToNextUnmarked() {
        guard !groups.isEmpty else { return }
        let current = selectedGroup.flatMap { g in groups.firstIndex(where: { $0.id == g.id }) } ?? 0
        let count = groups.count

        // current+1 から末尾、なければ 0 から current まで探す
        let searchOrder = Array((current + 1 ..< count)) + Array((0 ..< current))
        guard let found = searchOrder.first(where: { !groups[$0].hasRedMark }) else { return }

        selectedGroup = groups[found]
        if selectedGroup?.focusedImage == nil {
            selectedGroup?.focusedImage = selectedGroup?.images.first
        }
    }
}

extension ImageStore {
    /// 赤マーク付きファイルを選択フォルダへ移動する
    /// - Returns: 移動したファイル数（エラー時は nil）
    @discardableResult
    func moveRedMarkedFiles(to destination: URL) -> Int {
        let fm = FileManager.default
        var movedCount = 0

        // 移動先フォルダがなければ作成
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            print("移動先フォルダの作成に失敗:", error)
            return 0
        }

        for group in groups {
            for item in group.images where item.mark == .red {
                var dest = destination.appendingPathComponent(item.url.lastPathComponent)
                // 同名ファイルが既にあればリネーム
                if fm.fileExists(atPath: dest.path) {
                    let base = item.url.deletingPathExtension().lastPathComponent
                    let ext  = item.url.pathExtension
                    dest = destination.appendingPathComponent("\(base)_moved.\(ext)")
                }
                do {
                    try fm.moveItem(at: item.url, to: dest)
                    movedCount += 1
                } catch {
                    print("移動失敗 \(item.url.lastPathComponent):", error)
                }
            }
        }

        // リロードしてUIを更新
        if let url = folderURL {
            loadFolder(url: url)
        }

        return movedCount
    }
}

extension ImageStore {
    /// 赤マーク済みグループIDをカンマ区切りでクリップボードにコピー
    func copyRedGroupIDs() {
        let ids = groups
            .filter { $0.hasRedMark }
            .map { $0.id }
            .joined(separator: ",")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ids, forType: .string)
    }
}

extension ImageStore {
    func togglePanel() {
        activePanel = activePanel == .folder ? .group : .folder
    }
}