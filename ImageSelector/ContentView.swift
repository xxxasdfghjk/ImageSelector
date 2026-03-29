import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var store: ImageStore
    @State private var selectedFolder: URL?
    @State private var rootNodes: [FolderNode] = []
    @State private var restoreCancellable: AnyCancellable?
    @State private var showFolderSearch = false
    @State private var lastShiftTime: Date = .distantPast

    // トースト（Rキーリスキャン用）
    @State private var showRescanToast = false
    @State private var rescanToastMessage = ""

    var body: some View {
        NavigationSplitView {
            // ── カラム1: フォルダツリー ──
            VStack(spacing: 0) {
                FolderTreeView(roots: rootNodes, selectedFolder: $selectedFolder, searchActive: showFolderSearch)
                    .environmentObject(store)

                Divider()

                Button {
                    selectRootFolder()
                } label: {
                    Label("フォルダを開く", systemImage: "folder.badge.plus")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
                .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 0)
                    .strokeBorder(Color.accentColor.opacity(store.activePanel == .folder ? 0.6 : 0), lineWidth: 2)
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)

        } content: {
            // ── カラム2: グループリスト / モード切替 ──
            SidebarView()
                .environmentObject(store)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(Color.accentColor.opacity(store.activePanel == .group ? 0.6 : 0), lineWidth: 2)
                )
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)

        } detail: {
            // ── カラム3: 画像表示エリア（モードは SidebarView のセグメントで切替）──
            switch store.viewMode {
            case .group:
                if let group = store.selectedGroup {
                    ImageGridView(group: group)
                        .environmentObject(store)
                } else {
                    emptyPlaceholder
                }
            case .list:
                if store.groups.isEmpty {
                    emptyPlaceholder
                } else {
                    ImageListView()
                        .environmentObject(store)
                }
            }
        }
        .onAppear {
            restoreOrLoadDefault()
        }
        .overlay {
            if showFolderSearch {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showFolderSearch = false }

                    VStack {
                        Spacer().frame(height: 80)
                        FolderSearchView(
                            isPresented: $showFolderSearch,
                            rootNodes: rootNodes
                        ) { node in
                            selectedFolder = node.url
                            store.loadFolder(url: node.url)
                            store.activePanel = .folder
                            expandToNode(node)
                        }
                        Spacer()
                    }
                }
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: showFolderSearch)
            }
        }
        // リスキャン完了トースト
        .overlay(alignment: .bottom) {
            if showRescanToast {
                Text(rescanToastMessage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(Color.black.opacity(0.75)))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showRescanToast)
        .background(TabKeyMonitor { store.togglePanel() })
        .background(ShiftDoubleMonitor(lastShiftTime: $lastShiftTime) { showFolderSearch = true })
        .background(RescanKeyMonitor { rescanFolderTree() })
        .onDisappear { saveSession() }
        .onReceive(NotificationCenter.default.publisher(for: .saveSession)) { _ in saveSession() }
        .onChange(of: showFolderSearch) { active in store.isSearchActive = active }
    }

    // MARK: - 空プレースホルダー

    private var emptyPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("フォルダを選択してください")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - フォルダツリー再スキャン（R キー）

    private func rescanFolderTree() {
        guard !rootNodes.isEmpty else { return }
        rootNodes[0].rescan { addedCount in
            let msg = addedCount > 0
                ? "ツリーを更新しました（\(addedCount)件追加）"
                : "新規フォルダはありませんでした"
            rescanToastMessage = msg
            showRescanToast = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { showRescanToast = false }
        }
    }

    // MARK: - セッション復元

    private func restoreOrLoadDefault() {
        if let url = SessionStore.restoreRoot() {
            restoreSession(rootURL: url)
        } else {
            loadDefaultRoot()
        }
    }

    private func restoreSession(rootURL: URL) {
        let imageFolderURL = SessionStore.restoreSelectedFolder()
        let expandedPaths  = SessionStore.restoreExpanded()
        let prevGroupID    = SessionStore.restoreSelectedGroupID()

        let node = FolderNode(url: rootURL)
        rootNodes = [node]
        node.restoreExpanded(paths: expandedPaths) {
            self.selectedFolder = imageFolderURL
            self.store.activePanel = .folder
        }

        guard let imageURL = imageFolderURL else { return }
        store.loadFolder(url: imageURL)

        var cancellable: AnyCancellable?
        cancellable = store.$groups
            .filter { !$0.isEmpty }
            .first()
            .receive(on: DispatchQueue.main)
            .sink { groups in
                defer { cancellable = nil }
                guard let id = prevGroupID,
                      let group = groups.first(where: { $0.id == id }) else { return }
                self.store.selectedGroup = group
                group.focusedImage = group.images.first
                self.store.lastGroupMoveDelta = 1
            }
        self.restoreCancellable = cancellable
    }

    private func expandToNode(_ target: FolderNode) {
        func expand(nodes: [FolderNode], path: [String]) -> Bool {
            guard !path.isEmpty else { return false }
            for node in nodes {
                if node.url.path == path[0] {
                    if path.count == 1 { return true }
                    node.isExpanded = true
                    node.loadChildren()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        _ = expand(nodes: node.children ?? [], path: Array(path.dropFirst()))
                    }
                    return true
                }
            }
            return false
        }
        let targetPath = target.url.path
        let rootPath = rootNodes.first?.url.path ?? ""
        guard targetPath.hasPrefix(rootPath) else { return }
        let relative = String(targetPath.dropFirst(rootPath.count))
        var components = [rootPath]
        var current = rootPath
        for part in relative.split(separator: "/") {
            current += "/" + part
            components.append(current)
        }
        _ = expand(nodes: rootNodes, path: components)
    }

    private func saveSession() {
        guard let root = rootNodes.first else { return }
        SessionStore.saveRoot(url: root.url)
        SessionStore.saveExpanded(urls: root.collectExpanded())
        if let folder = selectedFolder {
            SessionStore.saveSelectedFolder(url: folder)
        }
    }

    private func loadDefaultRoot() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")
        let panel = NSOpenPanel()
        panel.message = "開始フォルダを選択してください（そのまま「開く」でDownloadsを使用）"
        panel.prompt = "開く"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = downloads
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { setRoot(url: url) }
    }

    private func selectRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "開く"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRoot(url: url)
    }

    private func setRoot(url: URL) {
        let node = FolderNode(url: url)
        node.loadChildren(expandAfterLoad: true)
        rootNodes = [node]
        selectedFolder = nil
        store.groups = []
        store.selectedGroup = nil
    }
}

// MARK: - Tab キーでパネル切り替え

private struct TabKeyMonitor: NSViewRepresentable {
    var onTab: () -> Void
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onTab = onTab }
    func makeCoordinator() -> Coordinator { Coordinator(onTab: onTab) }

    class Coordinator {
        var onTab: () -> Void
        var monitor: Any?
        init(onTab: @escaping () -> Void) {
            self.onTab = onTab
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if event.keyCode == 48 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                    self?.onTab(); return nil
                }
                return event
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

// MARK: - Shift 二連打検出

private struct ShiftDoubleMonitor: NSViewRepresentable {
    @Binding var lastShiftTime: Date
    var onDoubleShift: () -> Void
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.lastShiftTime = _lastShiftTime
        context.coordinator.onDoubleShift = onDoubleShift
    }
    func makeCoordinator() -> Coordinator { Coordinator(lastShiftTime: _lastShiftTime, onDoubleShift: onDoubleShift) }

    class Coordinator {
        var lastShiftTime: Binding<Date>
        var onDoubleShift: () -> Void
        var monitor: Any?
        init(lastShiftTime: Binding<Date>, onDoubleShift: @escaping () -> Void) {
            self.lastShiftTime = lastShiftTime
            self.onDoubleShift = onDoubleShift
            monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                guard let self else { return event }
                guard event.modifierFlags.contains(.shift) else { return event }
                let now = Date()
                let interval = now.timeIntervalSince(self.lastShiftTime.wrappedValue)
                if interval < 0.4 {
                    DispatchQueue.main.async { self.onDoubleShift() }
                    self.lastShiftTime.wrappedValue = .distantPast
                } else {
                    self.lastShiftTime.wrappedValue = now
                }
                return event
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

// MARK: - R キー: フォルダツリー再スキャン

private struct RescanKeyMonitor: NSViewRepresentable {
    var onRescan: () -> Void
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) { context.coordinator.onRescan = onRescan }
    func makeCoordinator() -> Coordinator { Coordinator(onRescan: onRescan) }

    class Coordinator {
        var onRescan: () -> Void
        var monitor: Any?
        init(onRescan: @escaping () -> Void) {
            self.onRescan = onRescan
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // keyCode 15 = R、修飾キーなし
                if event.keyCode == 15 &&
                   event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                    DispatchQueue.main.async { self?.onRescan() }
                    return nil
                }
                return event
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}
