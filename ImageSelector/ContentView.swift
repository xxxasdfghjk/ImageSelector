import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var store: ImageStore
    @State private var selectedFolder: URL?
    @State private var rootNodes: [FolderNode] = []
    @State private var restoreCancellable: AnyCancellable?

    var body: some View {
        NavigationSplitView {
            // ── カラム1: フォルダツリー ──
            VStack(spacing: 0) {
                FolderTreeView(roots: rootNodes, selectedFolder: $selectedFolder)
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
            // ── カラム2: グループリスト（既存 SidebarView）──
            SidebarView()
                .environmentObject(store)
                .overlay(
                    RoundedRectangle(cornerRadius: 0)
                        .strokeBorder(Color.accentColor.opacity(store.activePanel == .group ? 0.6 : 0), lineWidth: 2)
                )
                .navigationSplitViewColumnWidth(min: 160, ideal: 200)

        } detail: {
            // ── カラム3: 画像グリッド ──
            if let group = store.selectedGroup {
                ImageGridView(group: group)
                    .environmentObject(store)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("フォルダを選択してください")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            restoreOrLoadDefault()
        }
        .background(
            TabKeyMonitor { store.togglePanel() }
        )
        .onDisappear { saveSession() }
        .onReceive(NotificationCenter.default.publisher(for: .saveSession)) { _ in
            saveSession()
        }

    }

    // MARK: - 初期ルート（~/Downloads）

    // MARK: - セッション復元

    private func restoreOrLoadDefault() {
        if let url = SessionStore.restoreRoot() {
            // 前回のルートを復元
            restoreSession(rootURL: url)
        } else {
            loadDefaultRoot()
        }
    }

    private func restoreSession(rootURL: URL) {
        let imageFolderURL = SessionStore.restoreSelectedFolder()
        let expandedPaths  = SessionStore.restoreExpanded()
        let prevGroupID    = SessionStore.restoreSelectedGroupID()

        print("[Restore] rootURL=\(rootURL.path)")
        print("[Restore] imageFolderURL=\(imageFolderURL?.path ?? "nil")")
        print("[Restore] prevGroupID=\(prevGroupID ?? "nil")")

        // 1. ツリーを構築・展開
        let node = FolderNode(url: rootURL)
        rootNodes = [node]
        node.restoreExpanded(paths: expandedPaths) {
            print("[Restore] restoreExpanded done → selectedFolder=\(imageFolderURL?.lastPathComponent ?? "nil")")
            self.selectedFolder = imageFolderURL
            self.store.activePanel = .folder
        }

        // 2. 画像フォルダがあればロード、なければ何もしない
        guard let imageURL = imageFolderURL else {
            print("[Restore] imageFolderURL is nil, skip loadFolder")
            return
        }
        print("[Restore] loadFolder: \(imageURL.path)")
        store.loadFolder(url: imageURL)

        // 3. store.groups の変化を Combine で1回だけ受け取ってグループ復元
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
        // cancellable をインスタンス変数で保持
        self.restoreCancellable = cancellable
    }

    private func saveSession() {
        guard let root = rootNodes.first else { return }
        SessionStore.saveRoot(url: root.url)
        SessionStore.saveExpanded(urls: root.collectExpanded())
        // 選択中フォルダも保存（loadFolder 経由で保存済みのはずだが念のため）
        if let folder = selectedFolder {
            SessionStore.saveSelectedFolder(url: folder)
        }
    }

    private func loadDefaultRoot() {
        let downloads = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads")

        // NSOpenPanel で必ずユーザーに選択させる。
        // これがmacOSにプライバシー権限を付与させる唯一確実な方法。
        // Downloadsをあらかじめ選択状態にしておくので「開く」を押すだけでOK。
        let panel = NSOpenPanel()
        panel.message = "開始フォルダを選択してください（そのまま「開く」でDownloadsを使用）"
        panel.prompt = "開く"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.directoryURL = downloads
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            setRoot(url: url)
        }
        // キャンセル時は何もしない（空の状態のまま）
    }

    // MARK: - ルートフォルダ選択

    private func selectRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "開く"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setRoot(url: url)
    }

    private func setRoot(url: URL) {
        print("[ContentView] setRoot: \(url.path)")
        let node = FolderNode(url: url)
        node.loadChildren(expandAfterLoad: true)
        rootNodes = [node]
        print("[ContentView] rootNodes set: \(rootNodes.count)件")
        selectedFolder = nil
        store.groups = []
        store.selectedGroup = nil
    }
}

// MARK: - Tab キーでパネル切り替え

private struct TabKeyMonitor: NSViewRepresentable {
    var onTab: () -> Void

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onTab = onTab
    }
    func makeCoordinator() -> Coordinator { Coordinator(onTab: onTab) }

    class Coordinator {
        var onTab: () -> Void
        var monitor: Any?

        init(onTab: @escaping () -> Void) {
            self.onTab = onTab
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // keyCode 48 = Tab、修飾キーなし
                if event.keyCode == 48 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                    self?.onTab()
                    return nil
                }
                return event
            }
        }
        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}