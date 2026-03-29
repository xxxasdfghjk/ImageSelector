import Foundation
import SwiftUI
import Combine

enum ActivePanel { case folder, group }

// MARK: - 表示モード（SidebarView と ContentView で共有）
enum ViewMode { case group, list }

class ImageStore: ObservableObject {
    @Published var groups: [ImageGroup] = []
    @Published var selectedGroup: ImageGroup? {
        didSet { SessionStore.saveSelectedGroup(id: selectedGroup?.id) }
    }

    private var folderURL: URL?
    private var saveCancellable: AnyCancellable?
    private let watcher = FolderWatcher()
    @Published var lastGroupMoveDelta: Int = 1
    @Published var activePanel: ActivePanel = .folder
    @Published var isSearchActive: Bool = false

    /// グループビュー ↔ 一覧ビューの切り替え
    @Published var viewMode: ViewMode = .group

    // 一覧ビューで選択中のアイテム
    @Published var listSelectedItem: ImageItem? = nil

    // MARK: - フォルダ読み込み

    func loadFolder(url: URL, completion: (() -> Void)? = nil) {
        folderURL?.stopAccessingSecurityScopedResource()
        _ = url.startAccessingSecurityScopedResource()
        folderURL = url
        SessionStore.saveSelectedFolder(url: url)

        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        ) else { return }

        let items = files.compactMap { Parser.parse(url: $0) }
        let grouped = Dictionary(grouping: items) { $0.groupId }
        let savedMarks = MarkStore.load(folderURL: url)

        let groups = grouped.map { entry -> ImageGroup in
            let key = entry.key
            let rawItems = entry.value
            let sorted = rawItems
                .sorted { $0.timestamp < $1.timestamp }
                .map { item -> ImageItem in
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
            self.listSelectedItem = sortedGroups.first?.images.first
            self.observeMarkChanges()
            self.watcher.start(url: url) { [weak self] in
                guard let self, let url = self.folderURL else { return }
                print("[ImageStore] フォルダ変化を検知、リロード: \(url.lastPathComponent)")
                self.reloadFolder(url: url)
            }
            completion?()
        }
    }

    private func reloadFolder(url: URL) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return }

        let items = files.compactMap { Parser.parse(url: $0) }
        let grouped = Dictionary(grouping: items) { $0.groupId }
        let savedMarks = MarkStore.load(folderURL: url)

        var existingMarks: [String: ImageMark] = [:]
        for group in groups {
            for item in group.images where item.mark != .none {
                existingMarks[item.url.lastPathComponent] = item.mark
            }
        }

        let existingIDs = Set(groups.map { $0.id })
        let newIDs = Set(grouped.keys)

        for group in groups {
            guard let rawItems = grouped[group.id] else { continue }
            let sorted = rawItems
                .sorted { $0.timestamp < $1.timestamp }
                .map { item -> ImageItem in
                    var r = item
                    r.mark = existingMarks[item.url.lastPathComponent]
                        ?? savedMarks[item.url.lastPathComponent]
                        ?? .none
                    return r
                }
            if group.images.map { $0.url } != sorted.map { $0.url } {
                group.images = sorted
            }
        }

        let addedIDs = newIDs.subtracting(existingIDs)
        let addedGroups: [ImageGroup] = addedIDs.compactMap { key in
            guard let rawItems = grouped[key] else { return nil }
            let sorted = rawItems
                .sorted { $0.timestamp < $1.timestamp }
                .map { item -> ImageItem in
                    var r = item
                    r.mark = existingMarks[item.url.lastPathComponent]
                        ?? savedMarks[item.url.lastPathComponent]
                        ?? .none
                    return r
                }
            return ImageGroup(id: key, images: sorted, prompt: rawItems[0].prompt)
        }

        let removedIDs = existingIDs.subtracting(newIDs)

        if !addedGroups.isEmpty || !removedIDs.isEmpty {
            var updated = groups.filter { !removedIDs.contains($0.id) }
            updated.append(contentsOf: addedGroups)
            updated.sort { $0.id < $1.id }
            groups = updated
        }

        if let prevSelectedID = selectedGroup?.id,
           let still = groups.first(where: { $0.id == prevSelectedID }) {
            selectedGroup = still
            if let focusURL = still.focusedImage?.url {
                still.focusedImage = still.images.first { $0.url == focusURL } ?? still.images.first
            }
        } else {
            selectedGroup = groups.first
            selectedGroup?.focusedImage = selectedGroup?.images.first
        }

        observeMarkChanges()
    }

    // MARK: - マーク監視・保存

    private func observeMarkChanges() {
        let publishers = groups.map { $0.objectWillChange.map { _ in () }.eraseToAnyPublisher() }
        guard !publishers.isEmpty else { return }
        saveCancellable = Publishers.MergeMany(publishers)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.saveMarks() }
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
        if let urls = selectedGroup?.images.map({ $0.url }) {
            ImageCache.shared.prefetch(urls: urls)
        }
        let nextNext = min(next + 1, groups.count - 1)
        if nextNext != next {
            ImageCache.shared.prefetch(urls: groups[nextNext].images.map { $0.url })
        }
    }

    // MARK: - 一覧ビュー: マーク・移動

    /// 一覧ビュー用: listSelectedItem にマークを付ける
    func setListMark(_ mark: ImageMark) {
        guard let item = listSelectedItem else { return }
        guard let group = groups.first(where: { $0.id == item.groupId }) else { return }
        group.setMark(mark, for: item)
        // listSelectedItem の mark を同期
        if let updated = group.images.first(where: { $0.id == item.id }) {
            listSelectedItem = updated
        }
    }

    /// 一覧ビュー用: ソート済みアイテム列の中で delta 移動
    func moveListItem(by delta: Int, in sortedItems: [ImageItem]) {
        guard !sortedItems.isEmpty else { return }
        let current = listSelectedItem.flatMap { sel in
            sortedItems.firstIndex(where: { $0.id == sel.id })
        } ?? 0
        let next = max(0, min(sortedItems.count - 1, current + delta))
        listSelectedItem = sortedItems[next]
    }
}

extension ImageStore {
    func jumpToNextUnmarked() {
        guard !groups.isEmpty else { return }
        let current = selectedGroup.flatMap { g in groups.firstIndex(where: { $0.id == g.id }) } ?? 0
        let count = groups.count
        let searchOrder = Array((current + 1 ..< count)) + Array((0 ..< current))
        guard let found = searchOrder.first(where: { !groups[$0].hasRedMark }) else { return }
        selectedGroup = groups[found]
        if selectedGroup?.focusedImage == nil {
            selectedGroup?.focusedImage = selectedGroup?.images.first
        }
    }
}

extension ImageStore {
    @discardableResult
    func moveRedMarkedFiles(to destination: URL) -> Int {
        let fm = FileManager.default
        var movedCount = 0
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            print("移動先フォルダの作成に失敗:", error)
            return 0
        }
        for group in groups {
            for item in group.images where item.mark == .red {
                var dest = destination.appendingPathComponent(item.url.lastPathComponent)
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
        if let url = folderURL { loadFolder(url: url) }
        return movedCount
    }
}

extension ImageStore {
    func copyRedGroupIDs() {
        let ids = groups.filter { $0.hasRedMark }.map { $0.id }.joined(separator: ",")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ids, forType: .string)
    }
}

extension ImageStore {
    func togglePanel() {
        activePanel = activePanel == .folder ? .group : .folder
    }
}
