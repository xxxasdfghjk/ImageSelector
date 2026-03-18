import SwiftUI

struct AsyncPreviewImage: View {
    let url: URL

    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .onAppear { load(url: url) }
        .onChange(of: url) { newURL in load(url: newURL) }
    }

    private func load(url: URL) {
        // image = nil をしない → 前の画像を表示したまま新しい画像が来たら差し替え
        ImageCache.shared.preview(for: url) { img in
            image = img
        }
    }
}
