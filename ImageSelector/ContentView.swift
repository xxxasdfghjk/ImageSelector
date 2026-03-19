import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var store: ImageStore
    @State private var selectedFolder: URL?
    @State private var rootNodes: [FolderNode] = []

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
            loadDefaultRoot()
        }
        .background(
            TabKeyMonitor { store.togglePanel() }
        )

    }

    // MARK: - 初期ルート（~/Downloads）

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