import SwiftUI

struct ImageCellView: View {
    let item: ImageItem
    let isFocused: Bool

    // キャッシュから同期取得（LazyVGrid のセルなので軽量に）
    private var thumbnail: NSImage? {
        ImageCache.shared.thumbnail(for: item.url)
    }

    var body: some View {
        ZStack {
            if let thumb = thumbnail {
                Image(nsImage: thumb)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.gray.opacity(0.3)
            }

            // 赤マーク
            if item.mark == .red {
                Color.red.opacity(0.25)
                VStack {
                    HStack {
                        Spacer()
                        markCircle(color: .red, size: 26)
                            .padding(4)
                    }
                    Spacer()
                }
            }

            // 青マーク
            if item.mark == .blue {
                VStack {
                    HStack {
                        Spacer()
                        markCircle(color: .blue, size: 22)
                            .padding(4)
                    }
                    Spacer()
                }
            }
        }
        .frame(width: 100, height: 100)
        .clipped()
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(
                    isFocused        ? Color.yellow :
                    item.mark == .red  ? Color.red.opacity(0.8) :
                    item.mark == .blue ? Color.blue.opacity(0.6) :
                    Color.gray.opacity(0.4),
                    lineWidth: isFocused ? 3 : item.mark != .none ? 2 : 1
                )
        )
    }

    private func markCircle(color: Color, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(color).frame(width: size, height: size)
            Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: size, height: size)
        }
    }
}
