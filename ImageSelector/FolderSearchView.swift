import SwiftUI

struct FolderSearchView: View {
    @Binding var isPresented: Bool
    let rootNodes: [FolderNode]
    var onSelect: (FolderNode) -> Void

    @State private var query = ""
    @State private var results: [FolderNode] = []
    @State private var selectedIndex = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // 検索入力欄
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("フォルダを検索...", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($isFocused)
                    .onSubmit { confirm() }
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)

            Divider()

            // サジェストリスト
            if results.isEmpty && !query.isEmpty {
                Text("見つかりません")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                    .padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(results.enumerated()), id: \.offset) { i, node in
                                ResultRow(
                                    node: node,
                                    isSelected: i == selectedIndex,
                                    query: query
                                )
                                .id(i)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedIndex = i
                                    confirm()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selectedIndex) { idx in
                        withAnimation { proxy.scrollTo(idx, anchor: .center) }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 8)
        )
        .frame(width: 480)
        .onAppear {
            isFocused = true
        }
        .onChange(of: query) { _ in search() }
        .background(
            SearchKeyMonitor(
                onUp:     { move(by: -1) },
                onDown:   { move(by: +1) },
                onEnter:  { confirm() },
                onEscape: { isPresented = false }
            )
        )
    }

    private func search() {
        guard !query.isEmpty else {
            results = []
            selectedIndex = 0
            return
        }
        let q = query.lowercased()
        var found: [FolderNode] = []
        collect(nodes: rootNodes, query: q, into: &found)
        // 前方一致を優先ソート
        found.sort {
            let a = $0.name.lowercased()
            let b = $1.name.lowercased()
            let aStart = a.hasPrefix(q)
            let bStart = b.hasPrefix(q)
            if aStart != bStart { return aStart }
            return a < b
        }
        results = Array(found.prefix(50))
        selectedIndex = 0
    }

    private func collect(nodes: [FolderNode], query: String, into result: inout [FolderNode]) {
        for node in nodes {
            if node.name.lowercased().contains(query) {
                result.append(node)
            }
            collect(nodes: node.children ?? [], query: query, into: &result)
        }
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = max(0, min(results.count - 1, selectedIndex + delta))
    }

    private func confirm() {
        guard !results.isEmpty, results.indices.contains(selectedIndex) else { return }
        onSelect(results[selectedIndex])
        isPresented = false
    }
}

// MARK: - 結果行

private struct ResultRow: View {
    let node: FolderNode
    let isSelected: Bool
    let query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .white : .accentColor)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                highlightedText(node.name, query: query, selected: isSelected)
                    .font(.system(size: 13))
                Text(node.url.path
                    .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isSelected ? Color.accentColor : Color.clear)
    }

    private func highlightedText(_ text: String, query: String, selected: Bool) -> some View {
        let lower = text.lowercased()
        let q = query.lowercased()
        guard let range = lower.range(of: q) else {
            return Text(text).foregroundColor(selected ? .white : .primary)
        }
        let before = String(text[text.startIndex..<range.lowerBound])
        let match  = String(text[range])
        let after  = String(text[range.upperBound...])
        return Text(before)
            .foregroundColor(selected ? .white : .primary)
        + Text(match)
            .foregroundColor(selected ? .yellow : .accentColor)
            .bold()
        + Text(after)
            .foregroundColor(selected ? .white : .primary)
    }
}

// MARK: - キーモニター

private struct SearchKeyMonitor: NSViewRepresentable {
    var onUp: () -> Void
    var onDown: () -> Void
    var onEnter: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onUp     = onUp
        context.coordinator.onDown   = onDown
        context.coordinator.onEnter  = onEnter
        context.coordinator.onEscape = onEscape
    }
    func makeCoordinator() -> Coordinator { Coordinator(onUp: onUp, onDown: onDown, onEnter: onEnter, onEscape: onEscape) }

    class Coordinator {
        var onUp: () -> Void
        var onDown: () -> Void
        var onEnter: () -> Void
        var onEscape: () -> Void
        var monitor: Any?

        init(onUp: @escaping () -> Void, onDown: @escaping () -> Void, onEnter: @escaping () -> Void, onEscape: @escaping () -> Void) {
            self.onUp = onUp; self.onDown = onDown; self.onEnter = onEnter; self.onEscape = onEscape
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                switch event.keyCode {
                case 125: self.onDown();   return nil
                case 126: self.onUp();     return nil
                case 36:  self.onEnter();  return nil  // Return
                case 53:  self.onEscape(); return nil  // Escape
                default:  return event
                }
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}