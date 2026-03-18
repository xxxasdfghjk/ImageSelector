import Foundation
 
enum ImageMark: String, Codable {
    case none
    case red
    case blue
}
 
struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let groupId: String
    let prompt: String
    let timestamp: Date
    var mark: ImageMark = .none
}
 
