import Foundation

// 診断ログ: ~/Library/Logs/LiveWallpaper/wallpaper.log に
// 「タイムスタンプ イベント種別 key=value ...」の 1 行形式で追記する。
// 「なぜ壁紙が止まったか」を後から追うためのもので、失敗しても本体動作には影響させない
public enum DiagnosticLog {
    public static let logDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/LiveWallpaper")
    public static let logURL = logDirectory.appendingPathComponent("wallpaper.log")

    // ローテーション閾値: 1MB を超えたら .old へ退避して書き直す
    static let rotationLimit = 1024 * 1024

    private static let queue = DispatchQueue(label: "com.local.livewallpaper.diagnostic-log")

    private static let timestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    // details は表示順を保つためタプル配列で受ける(例: [("event", "stalled"), ("count", "2")])
    public static func log(_ event: String, _ details: [(String, String)] = []) {
        let timestamp = timestampFormatter.string(from: Date())
        let fields = details.map { "\($0.0)=\(sanitize($0.1))" }.joined(separator: " ")
        let line = fields.isEmpty ? "\(timestamp) \(event)\n" : "\(timestamp) \(event) \(fields)\n"
        queue.async {
            append(line)
        }
    }

    // 改行を潰して 1 行 1 イベントを保証する
    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
    }

    private static func append(_ line: String) {
        guard let data = line.data(using: .utf8) else {
            return
        }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        rotateIfNeeded()
        if let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }

    private static func rotateIfNeeded() {
        let fileManager = FileManager.default
        guard let size = (try? fileManager.attributesOfItem(atPath: logURL.path))?[.size] as? Int,
              size > rotationLimit else {
            return
        }
        let oldURL = logDirectory.appendingPathComponent("wallpaper.log.old")
        try? fileManager.removeItem(at: oldURL)
        try? fileManager.moveItem(at: logURL, to: oldURL)
    }
}
