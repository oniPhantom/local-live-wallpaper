import Foundation

// watch ページの URL 構築。複数 ID は watch_videos で匿名プレイリスト化する
public enum WatchURL {
    public static func build(videoID: String?, playlistID: String?, videoIDs: [String], startSeconds: Int?) -> URL? {
        let explicitIDs = videoIDs.compactMap(WallpaperSource.sanitizeID)
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        var items: [URLQueryItem] = []
        if explicitIDs.count > 1 {
            components.path = "/watch_videos"
            items.append(URLQueryItem(name: "video_ids", value: explicitIDs.joined(separator: ",")))
        } else if let videoID = videoID ?? explicitIDs.first {
            components.path = "/watch"
            items.append(URLQueryItem(name: "v", value: videoID))
            if let playlistID {
                items.append(URLQueryItem(name: "list", value: playlistID))
            }
        } else if let playlistID {
            components.path = "/playlist"
            items.append(URLQueryItem(name: "list", value: playlistID))
            items.append(URLQueryItem(name: "playnext", value: "1"))
        } else {
            return nil
        }
        if let startSeconds, startSeconds > 0 {
            items.append(URLQueryItem(name: "t", value: "\(startSeconds)s"))
        }
        components.queryItems = items
        return components.url
    }
}
