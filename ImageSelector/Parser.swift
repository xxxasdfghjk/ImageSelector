import Foundation

struct Parser {
    // 対応する画像拡張子
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "tiff", "bmp", "heic"]

    static func parse(url: URL) -> ImageItem? {
        // 画像ファイルでなければ黙って無視
        guard imageExtensions.contains(url.pathExtension.lowercased()) else { return nil }

        let filename = url.deletingPathExtension().lastPathComponent

        // ① 先頭5桁ID
        guard filename.count > 5 else { return nil }
        let id = String(filename.prefix(5))

        // ② 時刻 (_hhmmss)
        let timePattern = #"_([0-9]{6})$"#
        guard let timeMatch = filename.range(of: timePattern, options: .regularExpression) else {
            print("time not found:", filename)
            return nil
        }

        let time = String(filename[timeMatch]).dropFirst() // "_"除去

        // ③ 日付 (yyyy-mm-dd)
        let datePattern = #"([0-9]{4}-[0-9]{2}-[0-9]{2})"#
        guard let dateMatch = filename.range(of: datePattern, options: .regularExpression) else {
            print("date not found:", filename)
            return nil
        }

        let date = String(filename[dateMatch])

        // ④ プロンプト（IDと日付の間）
        let promptStart = filename.index(filename.startIndex, offsetBy: 5)
        let promptEnd = dateMatch.lowerBound

        let prompt = String(filename[promptStart..<promptEnd])

        // ⑤ Date化
        let dateTimeStr = date + time
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-ddHHmmss"

        guard let parsedDate = formatter.date(from: dateTimeStr) else {
            print("date parse failed:", filename)
            return nil
        }

        return ImageItem(
            url: url,
            groupId: id,
            prompt: prompt,
            timestamp: parsedDate
        )
    }
}
