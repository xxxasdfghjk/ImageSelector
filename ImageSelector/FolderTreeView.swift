import SwiftUI
import AppKit

struct FolderTreeView: View {
    @EnvironmentObject var store: ImageStore
    let roots: [FolderNode]
    @Binding var selectedFolder: URL?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(roots) { node in
                        FolderRowView(node: node, selectedFolder: $selectedFolder, depth: 0)
                            .environmentObject(store)
                    }
                }
                .padding(.vertical, 4)
            }

            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(store.activePanel == .folder ? Color.accentColor : Color.clear, lineWidth: 2)
                    .padding(1)
            )
            .background(
                FolderKeyMonitor(
                    roots: roots,
                    isActive: store.activePanel == .folder,
                    selectedFolder: $selectedFolder,
                    onSelect: { url in
                        selectedFolder = url
                        store.loadFolder(url: url)
                        store.activePanel = .folder
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { proxy.scrollTo(url, anchor: .center) }
                    }
                )
            )

        }
    }
}

// MARK: - キーボードナビゲーション

private struct FolderKeyMonitor: NSViewRepresentable {
    let roots: [FolderNode]
    var isActive: Bool
    @Binding var selectedFolder: URL?
    var onSelect: (URL) -> Void
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.roots = roots
        context.coordinator.isActive = isActive
        context.coordinator.onSelect = onSelect
    }
    func makeCoordinator() -> Coordinator {
        Coordinator(roots: roots, isActive: isActive, selectedFolder: _selectedFolder, onSelect: onSelect)
    }

    class Coordinator {
        var roots: [FolderNode]
        var isActive: Bool
        var selectedFolder: Binding<URL?>
        var onSelect: (URL) -> Void
        var monitor: Any?

        init(roots: [FolderNode], isActive: Bool, selectedFolder: Binding<URL?>, onSelect: @escaping (URL) -> Void) {
            self.roots = roots
            self.isActive = isActive
            self.selectedFolder = selectedFolder
            self.onSelect = onSelect

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handle(event)
            }
        }

        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }

        func handle(_ event: NSEvent) -> NSEvent? {
            guard isActive else { return event }
            let flat = flatVisible(roots)
            guard !flat.isEmpty else { return event }

            switch event.keyCode {
            case 48: // Tab → パネル切り替え
                DispatchQueue.main.async { self.selectedFolder.wrappedValue.map { _ in } }
                // store への参照が必要なため onSelect 経由でトグル
                // ここでは特別処理：Tab は素通しにして ContentView で拾う
                return event
            case 125: // ↓
                move(by: +1, in: flat)
                return nil
            case 126: // ↑
                move(by: -1, in: flat)
                return nil
            case 124: // → 展開
                if let node = flat.first(where: { $0.url == selectedFolder.wrappedValue }) {
                    DispatchQueue.main.async {
                        if !node.isExpanded {
                            node.isExpanded = true
                            node.loadChildren()
                        }
                    }
                }
                return nil
            case 123: // ← 折りたたみ
                if let node = flat.first(where: { $0.url == selectedFolder.wrappedValue }) {
                    DispatchQueue.main.async {
                        node.isExpanded = false
                    }
                }
                return nil
            default:
                // [0-9a-z] の頭文字ジャンプ
                guard let ch = event.characters?.lowercased().first,
                      ch.isLetter || ch.isNumber else { return event }
                jumpToPrefix(ch, in: flat)
                return nil
            }
        }

        // 現在表示されているノードをフラットに列挙
        func flatVisible(_ nodes: [FolderNode]) -> [FolderNode] {
            nodes.flatMap { node -> [FolderNode] in
                if node.isExpanded, let children = node.children, !children.isEmpty {
                    return [node] + flatVisible(children)
                }
                return [node]
            }
        }

        func move(by delta: Int, in flat: [FolderNode]) {
            let current = flat.firstIndex { $0.url == selectedFolder.wrappedValue }
            let next: Int
            if let c = current {
                next = max(0, min(flat.count - 1, c + delta))
            } else {
                next = delta > 0 ? 0 : flat.count - 1
            }
            onSelect(flat[next].url)
        }

        func jumpToPrefix(_ ch: Character, in flat: [FolderNode]) {
            let currentIdx = flat.firstIndex { $0.url == selectedFolder.wrappedValue }
            let startIdx = (currentIdx.map { $0 + 1 }) ?? 0

            // 現在位置より後ろ → なければ先頭から折り返し
            let searchOrder = Array(startIdx..<flat.count) + Array(0..<startIdx)
            if let found = searchOrder.first(where: { flat[$0].name.lowercased().hasPrefix(String(ch)) }) {
                onSelect(flat[found].url)
            }
        }
    }
}

// MARK: - 再帰行ビュー

private struct FolderRowView: View {
    @EnvironmentObject var store: ImageStore
    @ObservedObject var node: FolderNode
    @Binding var selectedFolder: URL?
    let depth: Int

    var isSelected: Bool { selectedFolder == node.url }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 2) {
                Spacer().frame(width: CGFloat(depth) * 16 + 6)

                // 展開矢印
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        node.isExpanded.toggle()
                        if node.isExpanded { node.loadChildren() }
                    }
                } label: {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 14, height: 14)
                        .opacity(hasExpandableChildren ? 1 : 0)
                }
                .buttonStyle(.plain)

                // フォルダ名
                HStack(spacing: 5) {
                    Image(systemName: isSelected ? "folder.fill" : "folder")
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? .white : .accentColor)

                    Text(node.name)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(isSelected ? .white : .primary)

                    Spacer()

                    if node.hasImages {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.9) : Color.accentColor.opacity(0.7))
                            .frame(width: 5, height: 5)
                            .padding(.trailing, 6)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    isSelected
                        ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor)
                        : nil
                )
                .contentShape(Rectangle())
                .id(node.url)
                .onTapGesture {
                    selectedFolder = node.url
                    store.loadFolder(url: node.url)
                    store.activePanel = .folder
                    if !node.isExpanded {
                        node.isExpanded = true
                        node.loadChildren()
                    }
                }
            }
            .padding(.horizontal, 4)

            // 子フォルダ（展開中のみ）
            if node.isExpanded, let children = node.children, !children.isEmpty {
                ForEach(children) { child in
                    FolderRowView(node: child, selectedFolder: $selectedFolder, depth: depth + 1)
                        .environmentObject(store)
                }
            }
        }
    }

    private var hasExpandableChildren: Bool {
        if node.children == nil { return true }
        return !node.children!.isEmpty
    }
}