import Foundation

struct ImageItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let groupId: String
    let prompt: String
    let timestamp: Date
}
