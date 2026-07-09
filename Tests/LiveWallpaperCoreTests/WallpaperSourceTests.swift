import XCTest
@testable import LiveWallpaperCore

final class ParseTimeParamTests: XCTestCase {
    func test数字のみは秒として解釈する() {
        XCTAssertEqual(WallpaperSource.parseTimeParam("180"), 180)
        XCTAssertEqual(WallpaperSource.parseTimeParam("1"), 1)
    }

    func test秒サフィックス付き() {
        XCTAssertEqual(WallpaperSource.parseTimeParam("180s"), 180)
    }

    func test分秒の複合形式() {
        XCTAssertEqual(WallpaperSource.parseTimeParam("3m20s"), 200)
        XCTAssertEqual(WallpaperSource.parseTimeParam("1h2m3s"), 3723)
        XCTAssertEqual(WallpaperSource.parseTimeParam("1h"), 3600)
        XCTAssertEqual(WallpaperSource.parseTimeParam("2m"), 120)
    }

    func testサフィックスなしの端数は秒として加算する() {
        XCTAssertEqual(WallpaperSource.parseTimeParam("1m30"), 90)
    }

    func testゼロ以下はnil() {
        XCTAssertNil(WallpaperSource.parseTimeParam("0"))
        XCTAssertNil(WallpaperSource.parseTimeParam("-30"))
        XCTAssertNil(WallpaperSource.parseTimeParam("0s"))
    }

    func test不正な文字はnil() {
        XCTAssertNil(WallpaperSource.parseTimeParam("abc"))
        XCTAssertNil(WallpaperSource.parseTimeParam("1x30"))
        XCTAssertNil(WallpaperSource.parseTimeParam(""))
    }
}

final class YouTubeIDTests: XCTestCase {
    private func id(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        return WallpaperSource.youtubeID(from: url)
    }

    func testWatchURL() {
        XCTAssertEqual(id("https://www.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(id("https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&t=30s"), "dQw4w9WgXcQ")
    }

    func testYoutuBe短縮URL() {
        XCTAssertEqual(id("https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(id("https://youtu.be/dQw4w9WgXcQ?t=90"), "dQw4w9WgXcQ")
    }

    func testShortsURL() {
        XCTAssertEqual(id("https://www.youtube.com/shorts/abc123XYZ_-"), "abc123XYZ_-")
    }

    func testEmbedURL() {
        XCTAssertEqual(id("https://www.youtube.com/embed/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testLiveURL() {
        XCTAssertEqual(id("https://www.youtube.com/live/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testNocookieドメイン() {
        XCTAssertEqual(id("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testモバイルなどのサブドメイン() {
        XCTAssertEqual(id("https://m.youtube.com/watch?v=dQw4w9WgXcQ"), "dQw4w9WgXcQ")
    }

    func testYouTube以外のURLはnil() {
        XCTAssertNil(id("https://example.com/watch?v=dQw4w9WgXcQ"))
        XCTAssertNil(id("https://www.youtube.com/feed/playlists"))
    }

    func test文字列からのvideoID解析() {
        XCTAssertEqual(WallpaperSource.videoID(from: "https://youtu.be/dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        // URL でなければ ID 直接指定として扱う
        XCTAssertEqual(WallpaperSource.videoID(from: "dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertNil(WallpaperSource.videoID(from: "not a video id"))
    }
}

final class SanitizeIDTests: XCTestCase {
    func test有効なIDはそのまま返す() {
        XCTAssertEqual(WallpaperSource.sanitizeID("dQw4w9WgXcQ"), "dQw4w9WgXcQ")
        XCTAssertEqual(WallpaperSource.sanitizeID("abc_DEF-123"), "abc_DEF-123")
    }

    func test前後の空白は除去する() {
        XCTAssertEqual(WallpaperSource.sanitizeID("  dQw4w9WgXcQ\n"), "dQw4w9WgXcQ")
    }

    func test不正な文字を含むIDはnil() {
        XCTAssertNil(WallpaperSource.sanitizeID("abc def"))
        XCTAssertNil(WallpaperSource.sanitizeID("abc/def"))
        XCTAssertNil(WallpaperSource.sanitizeID("<script>"))
        XCTAssertNil(WallpaperSource.sanitizeID(""))
        XCTAssertNil(WallpaperSource.sanitizeID("   "))
    }
}

final class WatchURLTests: XCTestCase {
    private func queryItems(_ url: URL?) -> [String: String] {
        guard let url,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return [:]
        }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    func test単一動画() {
        let url = WatchURL.build(videoID: "dQw4w9WgXcQ", playlistID: nil, videoIDs: [], startSeconds: nil)
        XCTAssertEqual(url?.host, "www.youtube.com")
        XCTAssertEqual(url?.path, "/watch")
        XCTAssertEqual(queryItems(url)["v"], "dQw4w9WgXcQ")
    }

    func test動画とプレイリストの組み合わせ() {
        let url = WatchURL.build(videoID: "dQw4w9WgXcQ", playlistID: "PL123", videoIDs: [], startSeconds: nil)
        XCTAssertEqual(url?.path, "/watch")
        XCTAssertEqual(queryItems(url)["v"], "dQw4w9WgXcQ")
        XCTAssertEqual(queryItems(url)["list"], "PL123")
    }

    func testプレイリストのみ() {
        let url = WatchURL.build(videoID: nil, playlistID: "PL123", videoIDs: [], startSeconds: nil)
        XCTAssertEqual(url?.path, "/playlist")
        XCTAssertEqual(queryItems(url)["list"], "PL123")
        XCTAssertEqual(queryItems(url)["playnext"], "1")
    }

    func test複数IDはwatch_videosで匿名プレイリスト化する() {
        let url = WatchURL.build(videoID: nil, playlistID: nil, videoIDs: ["aaa", "bbb", "ccc"], startSeconds: nil)
        XCTAssertEqual(url?.path, "/watch_videos")
        XCTAssertEqual(queryItems(url)["video_ids"], "aaa,bbb,ccc")
    }

    func test複数IDのうち不正なIDは除外する() {
        let url = WatchURL.build(videoID: nil, playlistID: nil, videoIDs: ["aaa", "b b", "ccc"], startSeconds: nil)
        XCTAssertEqual(queryItems(url)["video_ids"], "aaa,ccc")
    }

    func test明示IDが1件なら単一watchにする() {
        let url = WatchURL.build(videoID: nil, playlistID: nil, videoIDs: ["aaa"], startSeconds: nil)
        XCTAssertEqual(url?.path, "/watch")
        XCTAssertEqual(queryItems(url)["v"], "aaa")
    }

    func testTパラメータ付き() {
        let url = WatchURL.build(videoID: "dQw4w9WgXcQ", playlistID: nil, videoIDs: [], startSeconds: 200)
        XCTAssertEqual(queryItems(url)["t"], "200s")
    }

    func testゼロ秒のTパラメータは付けない() {
        let url = WatchURL.build(videoID: "dQw4w9WgXcQ", playlistID: nil, videoIDs: [], startSeconds: 0)
        XCTAssertNil(queryItems(url)["t"])
    }

    func testソースなしはnil() {
        XCTAssertNil(WatchURL.build(videoID: nil, playlistID: nil, videoIDs: [], startSeconds: nil))
    }
}

// 再構築時に再生中の動画から再開するためのプレイリスト回転
final class RotatedPlaylistTests: XCTestCase {
    func test途中のIDを先頭に回転する() {
        XCTAssertEqual(
            WallpaperSource.rotated(["a", "b", "c", "d"], toStartAt: "c"),
            ["c", "d", "a", "b"]
        )
    }

    func test先頭のIDならそのまま() {
        XCTAssertEqual(
            WallpaperSource.rotated(["a", "b", "c"], toStartAt: "a"),
            ["a", "b", "c"]
        )
    }

    func test含まれないIDならそのまま() {
        XCTAssertEqual(
            WallpaperSource.rotated(["a", "b", "c"], toStartAt: "x"),
            ["a", "b", "c"]
        )
    }

    func test末尾のIDを先頭に回転する() {
        XCTAssertEqual(
            WallpaperSource.rotated(["a", "b", "c"], toStartAt: "c"),
            ["c", "a", "b"]
        )
    }

    func test空配列はそのまま() {
        XCTAssertEqual(WallpaperSource.rotated([], toStartAt: "a"), [])
    }
}
