import SwiftUI

struct ImageGridView: View {
    @ObservedObject var group: ImageGroup
    @EnvironmentObject var store: ImageStore
    @State private var showToast = false
    @State private var toastMessage = "コピーしました！"

    var body: some View {
        VStack(spacing: 0) {
            // ── 上: 大きなプレビュー ──
            ZStack {
                Color.black

                if let focused = group.focusedImage {
                    AsyncPreviewImage(url: focused.url)
                } else {
                    Text("画像を選択してください")
                        .foregroundColor(.white)
                }

                // マークバッジ（右上）
                if let focused = group.focusedImage, focused.mark != .none {
                    VStack {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(focused.mark == .red ? Color.red : Color.blue)
                                .frame(width: 36, height: 36)
                                .padding(12)
                        }
                        Spacer()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // ── 下: サムネイル横並び ──
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(group.images) { item in
                            ImageCellView(
                                item: item,
                                isFocused: group.focusedImage == item
                            )
                            .id(item.id)
                            .onTapGesture {
                                group.focusedImage = item
                            }
                        }
                    }
                    .padding(8)
                }
                .frame(height: 120)
                .background(Color(NSColor.windowBackgroundColor))
                .onChange(of: group.focusedImage) { newItem in
                    if let id = newItem?.id {
                        withAnimation {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .navigationTitle("\(group.id) \(group.prompt)")
        .onAppear {
            ImageCache.shared.prefetch(urls: group.images.map(\.url))
        }
        .onChange(of: group.id) { _ in
            ImageCache.shared.prefetch(urls: group.images.map(\.url))
        }
        .background(
            KeyMonitorView { event in
                handleKeyEvent(event)
            }
        )
        .toast(isShowing: $showToast, message: toastMessage)
    }

    private func showToast(_ message: String, duration: Double = 1.8) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { showToast = false }
    }

    private func presentMovePanel() {
        let panel = NSOpenPanel()
        panel.title = "移動先フォルダを選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "移動"

        // デフォルトを ~/Desktop/booth に設定
        let defaultURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/booth")
        panel.directoryURL = defaultURL

        guard panel.runModal() == .OK, let dest = panel.url else { return }

        // Sandbox 環境でのアクセス権を確保
        let accessing = dest.startAccessingSecurityScopedResource()
        defer { if accessing { dest.stopAccessingSecurityScopedResource() } }

        let count = store.moveRedMarkedFiles(to: dest)
        showToast("\(count)件を移動しました")
    }

    // true を返すとイベントを消費（ビープなし）、false で素通し
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // フォルダツリーがアクティブなときは全キーを素通し
        guard store.activePanel != .folder else { return false }

        // Cmd+Shift+C: 赤マーク済みグループIDをクリップボードへ
        let cmdShift: NSEvent.ModifierFlags = [.shift, .command]
        if event.keyCode == 8 && event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(cmdShift) {
            let ids = store.groups
                .filter { $0.hasRedMark }
                .map { $0.id }
                .joined(separator: ",")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ids, forType: .string)
            showToast("コピーしました！")
            return true  // Cmd+Shift+C
        }
        switch event.keyCode {
        case 18: store.setMark(.red);           return true  // 1
        case 19: store.setMark(.none);          return true  // 2
        case 20: store.setMark(.blue);          return true  // 3
        case 123: store.moveFocus(by: -1);      return true  // ←
        case 124: store.moveFocus(by:  1);      return true  // →
        case 125: store.moveGroup(by:  1);      return true  // ↓
        case 126: store.moveGroup(by: -1);      return true  // ↑
        case 45:  store.jumpToNextUnmarked();   return true  // n
        case 46:  presentMovePanel();           return true  // m
        default: return false
        }
    }
}

// MARK: - ビープ音を出さずにキーを処理するラッパー

struct KeyMonitorView: NSViewRepresentable {
    var handler: (NSEvent) -> Bool  // true = 消費、false = 素通し

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(handler: handler) }

    class Coordinator {
        var monitor: Any?
        var handler: (NSEvent) -> Bool

        init(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
            // nil を返すとイベントが NSWindow.keyDown に届かず
            // interpretKeyEvents も呼ばれないのでビープが鳴らない
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                return self.handler(event) ? nil : event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}