import Foundation

// 設定ファイル(~/Library/Application Support/LiveWallpaper/*.txt)の読み書きと
// YouTube URL / ID の解析を集約する。AppKit 非依存(native-host と共有する)
public enum WallpaperSource {
    public static let supportDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LiveWallpaper")
    public static let configURL = supportDir.appendingPathComponent("youtube-url.txt")
    public static let volumeURL = supportDir.appendingPathComponent("volume.txt")
    public static let playlistURL = supportDir.appendingPathComponent("playlist.txt")
    public static let largestOnlyURL = supportDir.appendingPathComponent("largest-only.txt")
    public static let qualityURL = supportDir.appendingPathComponent("quality.txt")
    public static let stateURL = supportDir.appendingPathComponent("state.json")
    public static let panelHiddenURL = supportDir.appendingPathComponent("panel-hidden.txt")
    public static let batteryPauseOffURL = supportDir.appendingPathComponent("battery-pause-off.txt")
    public static let panelOriginURL = supportDir.appendingPathComponent("panel-origin.txt")
    public static let fitModeURL = supportDir.appendingPathComponent("fit-mode.txt")

    public static let allowedQualities = ["small", "medium", "large", "hd720", "hd1080", "hd1440", "hd2160"]

    // 画質上限。既定は hd1080、"auto" 指定で無制限(vq は YouTube 側のベストエフォート)
    public static func maxQuality() -> String? {
        let raw = ((try? String(contentsOf: qualityURL, encoding: .utf8)) ?? "hd1080")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw == "auto" {
            return nil
        }
        return allowedQualities.contains(raw) ? raw : "hd1080"
    }

    public static func saveMaxQuality(_ quality: String) {
        let value = quality == "auto" || allowedQualities.contains(quality) ? quality : "hd1080"
        try? FileManager.default.createDirectory(at: qualityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (value + "\n").write(to: qualityURL, atomically: true, encoding: .utf8)
    }

    public static func saveState(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }

    public static func clearState() {
        try? FileManager.default.removeItem(at: stateURL)
    }

    public static func panelHidden() -> Bool {
        let raw = (try? String(contentsOf: panelHiddenURL, encoding: .utf8)) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    public static func savePanelHidden(_ hidden: Bool) {
        if hidden {
            try? FileManager.default.createDirectory(at: panelHiddenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "1\n".write(to: panelHiddenURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: panelHiddenURL)
        }
    }

    public static func pauseOnBattery() -> Bool {
        !FileManager.default.fileExists(atPath: batteryPauseOffURL.path)
    }

    // ユーザーがドラッグしたパネル位置(スクリーン座標の origin)
    public static func panelOrigin() -> NSPoint? {
        guard let raw = try? String(contentsOf: panelOriginURL, encoding: .utf8) else {
            return nil
        }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    public static func savePanelOrigin(_ point: NSPoint) {
        try? FileManager.default.createDirectory(at: panelOriginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(point.x),\(point.y)\n".write(to: panelOriginURL, atomically: true, encoding: .utf8)
    }

    // "contain": 動画全体を表示(FullHD は縦幅いっぱい・左右黒帯)/ "cover": 切り抜いて画面を埋める
    public static func fitMode() -> String {
        let raw = ((try? String(contentsOf: fitModeURL, encoding: .utf8)) ?? "contain")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw == "cover" ? "cover" : "contain"
    }

    public static func saveFitMode(_ mode: String) {
        try? FileManager.default.createDirectory(at: fitModeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ((mode == "cover" ? "cover" : "contain") + "\n").write(to: fitModeURL, atomically: true, encoding: .utf8)
    }

    public static func videoOnLargestScreenOnly() -> Bool {
        let raw = (try? String(contentsOf: largestOnlyURL, encoding: .utf8)) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    public static func saveVideoOnLargestScreenOnly(_ enabled: Bool) {
        if enabled {
            try? FileManager.default.createDirectory(at: largestOnlyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "1\n".write(to: largestOnlyURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: largestOnlyURL)
        }
    }

    public static func sanitizeID(_ raw: String) -> String? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    public static func playlistVideoIDs() -> [String] {
        guard let raw = try? String(contentsOf: playlistURL, encoding: .utf8) else {
            return []
        }
        return raw.split(whereSeparator: \.isNewline).compactMap { sanitizeID(String($0)) }
    }

    // 再構築時に「再生中だった動画」から再開できるよう、指定 ID が先頭になるまで回転させる。
    // ID が含まれない場合は順序を変えない(watch_videos の巡回順は保たれる)
    public static func rotated(_ ids: [String], toStartAt id: String) -> [String] {
        guard let index = ids.firstIndex(of: id), index > 0 else {
            return ids
        }
        return Array(ids[index...]) + Array(ids[..<index])
    }

    public static func saveYouTubeURL(_ url: String) {
        try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (url + "\n").write(to: configURL, atomically: true, encoding: .utf8)
    }

    public static func currentURLString() -> String {
        ((try? String(contentsOf: configURL, encoding: .utf8)) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func savePlaylist(_ videoIDs: [String]) {
        let ids = videoIDs.compactMap(sanitizeID)
        if ids.isEmpty {
            try? FileManager.default.removeItem(at: playlistURL)
            return
        }
        try? FileManager.default.createDirectory(at: playlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (ids.joined(separator: "\n") + "\n").write(to: playlistURL, atomically: true, encoding: .utf8)
    }

    public static func clear() {
        try? FileManager.default.removeItem(at: configURL)
        try? FileManager.default.removeItem(at: playlistURL)
    }

    public static func videoID(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let id = youtubeID(from: url) {
            return sanitizeID(id)
        }
        return sanitizeID(trimmed)
    }

    public static func youtubeID() -> String? {
        guard let url = youtubeURL() else {
            return nil
        }
        return youtubeID(from: url).flatMap(sanitizeID)
    }

    public static func youtubePlaylistID() -> String? {
        guard let url = youtubeURL() else {
            return nil
        }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "list" })?
            .value
            .flatMap(sanitizeID)
    }

    private static func youtubeURL() -> URL? {
        let args = ProcessInfo.processInfo.arguments.dropFirst()
        let raw = args.first ?? (try? String(contentsOf: configURL, encoding: .utf8))
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return url
    }

    public static func volume() -> Int {
        let raw = (try? String(contentsOf: volumeURL, encoding: .utf8)) ?? "0"
        return min(100, max(0, Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
    }

    // 再生 URL の t= / start= パラメータ("180s" "3m20s" "180" 形式)を秒に変換する
    public static func startSeconds() -> Int? {
        guard let url = youtubeURL(),
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "t" || $0.name == "start" })?
                .value else {
            return nil
        }
        return parseTimeParam(raw)
    }

    public static func parseTimeParam(_ raw: String) -> Int? {
        if let plain = Int(raw) {
            return plain > 0 ? plain : nil
        }
        var total = 0
        var value = 0
        for ch in raw {
            if let digit = ch.wholeNumberValue, (0...9).contains(digit) {
                value = value * 10 + digit
            } else if ch == "h" {
                total += value * 3600
                value = 0
            } else if ch == "m" {
                total += value * 60
                value = 0
            } else if ch == "s" {
                total += value
                value = 0
            } else {
                return nil
            }
        }
        total += value
        return total > 0 ? total : nil
    }

    public static func saveVolume(_ volume: Int) {
        try? FileManager.default.createDirectory(at: volumeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(min(100, max(0, volume)))\n".write(to: volumeURL, atomically: true, encoding: .utf8)
    }

    public static func youtubeID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        if host == "youtu.be" {
            return path.split(separator: "/").first.map(String.init)
        }

        if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if let queryID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?
                .value {
                return queryID
            }

            let parts = path.split(separator: "/").map(String.init)
            if let marker = parts.firstIndex(where: { ["embed", "shorts", "live"].contains($0) }),
               parts.indices.contains(marker + 1) {
                return parts[marker + 1]
            }
        }

        return nil
    }
}
