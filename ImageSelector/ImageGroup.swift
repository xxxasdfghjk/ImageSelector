import Foundation
import Combine
 
class ImageGroup: ObservableObject, Identifiable {
    let id: String
    let prompt: String
    @Published var images: [ImageItem]
 
    @Published var focusedImage: ImageItem?
 
    var hasRedMark: Bool {
        images.contains { $0.mark == .red }
    }
 
    init(id: String, images: [ImageItem], prompt: String) {
        self.id = id
        self.images = images
        self.prompt = prompt
    }
 
    func setMark(_ mark: ImageMark, for item: ImageItem) {
        guard let idx = images.firstIndex(of: item) else { return }
        images[idx].mark = mark
        // focusedImageも同期
        if focusedImage == item {
            focusedImage = images[idx]
        }
    }
}
