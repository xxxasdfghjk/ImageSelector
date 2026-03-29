import SwiftUI

// MARK: - ソート軸

enum ListSortKey: String, CaseIterable {
    case name = "名前"
    case date = "更新日付"
}

enum ListSortOrder {
    case ascending, descending
}

// MARK: - ImageListView

/// 全グループの画像を Finder 詳細表示風に縦一覧するビュー
struct ImageListView: View {
    @EnvironmentObject var store: ImageStore

    @State private var sortKey:   ListSortKey   = .name
    @State private var sortOrder: ListSortOrder = .ascending

    // 全グループの画像をフラット化してソートしたもの
    var sortedItems: [ImageItem] {
        let all = store.groups.flatMap { $0.images }
        return all.sorted { a, b in
            switch sortKey {
            case .name:
                let cmp = a.url.lastPathComponent
                    .localizedStandardCompare(b.url.lastPathComponent)
                return sortOrder == .ascending
                    ? cmp == .orderedAscending
                    : cmp == .orderedDescending
            case .date:
                return sortOrder == .ascending
                    ? a.timestamp < b.timestamp
                    : a.timestamp > b.timestamp
            }
        }
    }

    var body: some View {
        HSplitView {
            // ── 左: ファイル一覧 ──
            VStack(spacing: 0) {
                // ヘッダー（ソートボタン）
                HStack(spacing: 0) {
                    Text("").frame(width: 56) // サムネイル列

                    Divider().frame(height: 24)

                    SortHeaderButton(label: "名前", key: .name, current: sortKey, order: sortOrder) {
                        toggle(.name)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Divider().frame(height: 24)

                    SortHeaderButton(label: "更新日付", key: .date, current: sortKey, order: sortOrder) {
                        toggle(.date)
                    }
                    .frame(width: 150, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .frame(height: 28)
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // リスト本体
                ScrollViewReader { proxy in
                    List {
                        ForEach(sortedItems) { item in
                            ImageListRow(
                                item: item,
                                isSelected: store.listSelectedItem?.id == item.id
                            )
                            .tag(item)
                            .id(item.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                            .listRowBackground(
                                store.listSelectedItem?.id == item.id
                                    ? Color.accentColor.opacity(0.15)
                                    : Color.clear
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                store.listSelectedItem = item
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: store.listSelectedItem) { item in
                        if let id = item?.id {
                            withAnimation { proxy.scrollTo(id, anchor: .center) }
                        }
                    }
                }
            }
            .frame(minWidth: 320)

            // ── 右: プレビュー ──
            ZStack {
                Color.black

                if let item = store.listSelectedItem {
                    VStack(spacing: 0) {
                        AsyncPreviewImage(url: item.url)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // メタ情報フッター
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.url.lastPathComponent)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .truncationMode(.middle)

                            HStack(spacing: 16) {
                                Label(formattedDate(item.timestamp), systemImage: "calendar")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.7))

                                if !item.prompt.isEmpty {
                                    Label(item.prompt, systemImage: "text.bubble")
                                        .font(.system(size: 11))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.black.opacity(0.6))
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.3))
                        Text("画像を選択してください")
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            .frame(minWidth: 200)
        }
        .onAppear {
            // 初期選択
            if store.listSelectedItem == nil {
                store.listSelectedItem = sortedItems.first
            }
        }
        .background(
            ListKeyMonitor { event in
                handleKey(event)
            }
        )
    }

    // MARK: - helpers

    private func toggle(_ key: ListSortKey) {
        if sortKey == key {
            sortOrder = sortOrder == .ascending ? .descending : .ascending
        } else {
            sortKey = key
            sortOrder = .ascending
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return fmt.string(from: date)
    }

    // ↑↓ キーで行移動（store 経由）
    private func handleKey(_ event: NSEvent) -> Bool {
        guard store.activePanel != .folder, !store.isSearchActive else { return false }
        switch event.keyCode {
        case 18: store.setListMark(.red);                          return true  // 1
        case 19: store.setListMark(.none);                         return true  // 2
        case 20: store.setListMark(.blue);                         return true  // 3
        case 125: store.moveListItem(by: +1, in: sortedItems);     return true  // ↓
        case 126: store.moveListItem(by: -1, in: sortedItems); return true  // ↑
        default: return false
        }
    }
}

// MARK: - ソートヘッダーボタン

private struct SortHeaderButton: View {
    let label: String
    let key: ListSortKey
    let current: ListSortKey
    let order: ListSortOrder
    let action: () -> Void

    var isActive: Bool { current == key }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(label)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                if isActive {
                    Image(systemName: order == .ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 行ビュー

private struct ImageListRow: View {
    let item: ImageItem
    let isSelected: Bool

    @State private var thumbnail: NSImage? = nil

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: 0) {
            // サムネイル
            ZStack {
                Color.gray.opacity(0.1)
                if let thumb = thumbnail {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.5)
                }
            }
            .frame(width: 48, height: 36)
            .clipped()
            .cornerRadius(3)
            .padding(.leading, 4)
            .padding(.trailing, 8)

            // マークインジケーター
            Circle()
                .fill(markColor)
                .frame(width: 7, height: 7)
                .opacity(item.mark == .none ? 0 : 1)
                .padding(.trailing, 6)

            // ファイル名
            Text(item.url.lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(isSelected ? .accentColor : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // 更新日付
            Text(Self.dateFormatter.string(from: item.timestamp))
                .font(.system(size: 11).monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 150, alignment: .leading)
                .padding(.trailing, 8)
        }
        .frame(height: 44)
        .onAppear { loadThumb() }
        .onChange(of: item.url) { _ in loadThumb() }
    }

    private var markColor: Color {
        switch item.mark {
        case .red:  return .red
        case .blue: return .blue
        case .none: return .clear
        }
    }

    private func loadThumb() {
        ImageCache.shared.thumbnail(for: item.url) { img in thumbnail = img }
    }
}

// MARK: - キーモニター（一覧ビュー用）

private struct ListKeyMonitor: NSViewRepresentable {
    var handler: (NSEvent) -> Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.handler = handler }
    func makeCoordinator() -> Coordinator { Coordinator(handler: handler) }

    class Coordinator {
        var monitor: Any?
        var handler: (NSEvent) -> Bool
        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handler(event) ? nil : event
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}
