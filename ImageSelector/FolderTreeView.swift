import SwiftUI

struct FolderTreeView: View {
    @EnvironmentObject var store: ImageStore
    let roots: [FolderNode]
    @Binding var selectedFolder: URL?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                let _ = print("[FolderTreeView] roots=\(roots.count)件, roots=\(roots.map { $0.name })")
                ForEach(roots) { node in
                    let _ = print("[FolderTreeView] render root: \(node.name) isExpanded=\(node.isExpanded) children=\(node.children == nil ? "nil" : "\(node.children!.count)件")")
                    FolderRowView(node: node, selectedFolder: $selectedFolder, depth: 0)
                        .environmentObject(store)
                }
            }
            .padding(.vertical, 4)
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
            // この行
            HStack(spacing: 2) {
                // インデント
                Spacer().frame(width: CGFloat(depth) * 16 + 6)

                // 展開矢印
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
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

                // フォルダアイコン + 名前
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
                .onTapGesture {
                    selectedFolder = node.url
                    store.loadFolder(url: node.url)
                    // タップで未展開なら展開も行う
                    if !node.isExpanded {
                        node.isExpanded = true
                        node.loadChildren()
                    }
                }
            }
            .padding(.horizontal, 4)

            // 子フォルダ（展開中のみ）
            let _ = print("[FolderRowView] \(node.name) isExpanded=\(node.isExpanded) children=\(node.children == nil ? "nil" : "\(node.children!.count)件")")
            if node.isExpanded, let children = node.children, !children.isEmpty {
                let _ = print("[FolderRowView] 子を描画: \(children.count)件")
                ForEach(children) { child in
                    FolderRowView(node: child, selectedFolder: $selectedFolder, depth: depth + 1)
                        .environmentObject(store)
                }
            } else {
                let _ = print("[FolderRowView] 子を描画しない: isExpanded=\(node.isExpanded) children=\(node.children == nil ? "nil" : "\(node.children!.count)件")")
            }
        }
    }

    private var hasExpandableChildren: Bool {
        // 子が未ロードなら「あるかもしれない」として矢印を表示
        if node.children == nil { return true }
        return !(node.children!.isEmpty)
    }
}
