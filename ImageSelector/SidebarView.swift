import SwiftUI
import Combine

struct SidebarView: View {
    @EnvironmentObject var store: ImageStore
    @State private var showToast = false
    @State private var toastMessage = ""

    private var hasRedMarked: Bool { store.groups.contains { $0.hasRedMark } }

    var body: some View {
        VStack(spacing: 0) {
            GroupListView()
                .environmentObject(store)

            Divider()

            // ── ボタン行 ──
            HStack(spacing: 8) {
                Button {
                    store.copyRedGroupIDs()
                    toast("コピーしました！")
                } label: {
                    Label("番号コピー", systemImage: "doc.on.clipboard")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!hasRedMarked)

                Button {
                    presentMovePanel()
                } label: {
                    Label("一括移動", systemImage: "folder.badge.plus")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasRedMarked)
            }
            .padding(.horizontal, 10)
            .padding(.top, 6)

            ProgressFooter(groups: store.groups)
        }
        .toast(isShowing: $showToast, message: toastMessage)
    }

    private func toast(_ message: String) {
        toastMessage = message
        showToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { showToast = false }
    }

    private func presentMovePanel() {
        let panel = NSOpenPanel()
        panel.title = "移動先フォルダを選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "移動"
        let defaultURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/booth")
        panel.directoryURL = defaultURL
        guard panel.runModal() == .OK, let dest = panel.url else { return }
        let accessing = dest.startAccessingSecurityScopedResource()
        defer { if accessing { dest.stopAccessingSecurityScopedResource() } }
        let count = store.moveRedMarkedFiles(to: dest)
        toast("\(count)件を移動しました")
    }
}

// MARK: - グループリスト（切り出し）

private struct GroupListView: View {
    @EnvironmentObject var store: ImageStore
    @State private var listHeight: CGFloat = 0
    @State private var scrollOffset: Int = 0  // 現在の先頭アイテムのインデックス概算

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(store.groups.enumerated()), id: \.element.id) { index, group in
                    GroupRow(group: group, isSelected: store.selectedGroup?.id == group.id)
                        .id(group.id)
                        .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
                        .listRowBackground(rowBackground(for: group))
                        .contentShape(Rectangle())
                        .onTapGesture { handleTap(group: group) }
                }
            }
            .listStyle(.sidebar)
            .overlay(focusBorder)
            .overlay(
                GeometryReader { geo in
                    Color.clear.onAppear { listHeight = geo.size.height }
                        .onChange(of: geo.size.height) { listHeight = $0 }
                }
            )
            .onTapGesture { store.activePanel = .group }
            .onChange(of: store.selectedGroup?.id) { _ in
                scrollIfNeeded(proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private func rowBackground(for group: ImageGroup) -> some View {
        if store.selectedGroup?.id == group.id {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.18))
                .padding(.vertical, 1)
        }
    }

    private var focusBorder: some View {
        RoundedRectangle(cornerRadius: 6)
            .stroke(store.activePanel == .group ? Color.accentColor : Color.clear, lineWidth: 2)
            .padding(1)
            .allowsHitTesting(false)
    }

    private func handleTap(group: ImageGroup) {
        store.lastGroupMoveDelta = 0
        store.activePanel = .group
        store.selectedGroup = group
        if group.focusedImage == nil {
            group.focusedImage = group.images.first
        }
    }

    private func scrollIfNeeded(proxy: ScrollViewProxy) {
        let delta = store.lastGroupMoveDelta
        guard delta != 0,
              let selectedIndex = store.groups.firstIndex(where: { $0.id == store.selectedGroup?.id })
        else { return }

        let rowHeight: CGFloat = 36
        let visibleCount = max(3, Int(listHeight / rowHeight))
        // デッドゾーン: 上20% / 下20% を超えたときだけスクロール
        let triggerZone = max(1, Int(Double(visibleCount) * 0.2))

        if delta < 0 {
            // 上移動: 選択行が「現在の先頭 + triggerZone」より上に行ったらスクロール
            let topThreshold = scrollOffset + triggerZone
            if selectedIndex < topThreshold {
                let newTop = max(0, selectedIndex - triggerZone)
                let anchorIndex = min(newTop + visibleCount - 1, store.groups.count - 1)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    proxy.scrollTo(store.groups[newTop].id, anchor: .top)
                }
                scrollOffset = newTop
            }
        } else {
            // 下移動: 選択行が「現在の末尾 - triggerZone」より下に行ったらスクロール
            let bottomThreshold = scrollOffset + visibleCount - 1 - triggerZone
            if selectedIndex > bottomThreshold {
                let newTop = max(0, selectedIndex - visibleCount + 1 + triggerZone)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    proxy.scrollTo(store.groups[min(newTop + visibleCount - 1, store.groups.count - 1)].id, anchor: .bottom)
                }
                scrollOffset = newTop
            }
        }
    }

}

// MARK: - グループ行

private struct GroupRow: View {
    @ObservedObject var group: ImageGroup
    let isSelected: Bool

    var redCount: Int { group.images.filter { $0.mark == .red }.count }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(redCount > 0 ? Color.red : Color.clear)
                    .frame(width: 24, height: 18)
                if redCount > 0 {
                    Text("\(redCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(group.id)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundColor(isSelected ? .accentColor : .primary)

                if !group.prompt.isEmpty {
                    Text(group.prompt)
                        .font(.caption)
                        .foregroundColor(isSelected ? .accentColor.opacity(0.8) : .secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            // 画像枚数
            Text("\(group.images.count)")
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(isSelected ? .accentColor.opacity(0.7) : .secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }
}

// MARK: - フッター：進捗表示

private struct ProgressFooter: View {
    let groups: [ImageGroup]

    @State private var redCount = 0
    @State private var markedGroups = 0
    @State private var totalGroups = 0

    var percent: Int {
        guard totalGroups > 0 else { return 0 }
        return Int(Double(markedGroups) / Double(totalGroups) * 100)
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.2))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.red.opacity(0.75))
                        .frame(width: totalGroups > 0
                               ? geo.size.width * CGFloat(markedGroups) / CGFloat(totalGroups)
                               : 0)
                        .animation(.easeInOut(duration: 0.2), value: markedGroups)
                }
            }
            .frame(height: 5)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(markedGroups) / \(totalGroups) グループ")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Text("画像 \(redCount) 枚")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(markedGroups > 0 ? .red : .secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { recalculate() }
        .onReceive(
            Publishers.MergeMany(groups.map { $0.objectWillChange.map { _ in () }.eraseToAnyPublisher() })
        ) { _ in recalculate() }
    }

    private func recalculate() {
        let allImages = groups.flatMap { $0.images }
        redCount     = allImages.filter { $0.mark == .red }.count
        markedGroups = groups.filter { $0.hasRedMark }.count
        totalGroups  = groups.count
    }
}