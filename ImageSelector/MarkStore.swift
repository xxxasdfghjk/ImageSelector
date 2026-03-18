import Foundation

/// マーク情報を Application Support に永続化するユーティリティ
///
/// 保存先: ~/Library/Application Support/ImageSelector/marks.json
/// キー構造: { "フォルダの絶対パス": { "ファイル名": "red" | "blue" } }
/// noneのものは保存しない（マークなし＝キーなし）
struct MarkStore {

    // MARK: - 保存先

    private static var storeURL: URL? {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return nil }

        let dir = appSupport.appendingPathComponent("ImageSelector", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("marks.json")
    }

    // MARK: - 内部データ型

    // ディスク上の全データ: folderPath -> (filename -> markRawValue)
    private typealias RawData = [String: [String: String]]

    // MARK: - 保存

    static func save(groups: [ImageGroup], folderURL: URL) {
        guard let storeURL else { return }

        var allData = loadRaw()
        let folderKey = folderURL.path

        var folderMarks: [String: String] = [:]
        for group in groups {
            for item in group.images where item.mark != .none {
                folderMarks[item.url.lastPathComponent] = item.mark.rawValue
            }
        }

        if folderMarks.isEmpty {
            allData.removeValue(forKey: folderKey)
        } else {
            allData[folderKey] = folderMarks
        }

        guard let data = try? JSONEncoder().encode(allData) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    // MARK: - 読み込み

    /// 指定フォルダのマーク情報を返す: [filename: ImageMark]
    static func load(folderURL: URL) -> [String: ImageMark] {
        let raw = loadRaw()
        guard let folderMarks = raw[folderURL.path] else { return [:] }
        return folderMarks.compactMapValues { ImageMark(rawValue: $0) }
    }

    // MARK: - Private

    private static func loadRaw() -> RawData {
        guard let storeURL,
              let data = try? Data(contentsOf: storeURL),
              let decoded = try? JSONDecoder().decode(RawData.self, from: data)
        else { return [:] }
        return decoded
    }
}
