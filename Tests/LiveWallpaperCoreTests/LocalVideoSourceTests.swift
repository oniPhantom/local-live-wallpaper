import XCTest
@testable import LiveWallpaperCore

final class LocalVideoSourceKindTests: XCTestCase {
    func testYouTubeURL各形式はyoutube判定() {
        XCTAssertEqual(LocalVideoSource.kind(of: "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "https://youtu.be/dQw4w9WgXcQ"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "https://www.youtube.com/shorts/abc123XYZ_-"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "https://www.youtube.com/embed/dQw4w9WgXcQ"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "https://www.youtube.com/playlist?list=PL123"), .youtube)
        // 動画 ID 直接指定も従来どおり YouTube 側で扱う
        XCTAssertEqual(LocalVideoSource.kind(of: "dQw4w9WgXcQ"), .youtube)
    }

    func testFileURLはローカル判定() {
        XCTAssertEqual(
            LocalVideoSource.kind(of: "file:///Users/test/Movies/loop.mp4"),
            .localVideo(path: "/Users/test/Movies/loop.mp4")
        )
        // パーセントエンコードされたスペースは展開される
        XCTAssertEqual(
            LocalVideoSource.kind(of: "file:///Users/test/My%20Movies/loop.mov"),
            .localVideo(path: "/Users/test/My Movies/loop.mov")
        )
    }

    func test絶対パスの対応拡張子はローカル判定() {
        XCTAssertEqual(LocalVideoSource.kind(of: "/Users/test/loop.mp4"), .localVideo(path: "/Users/test/loop.mp4"))
        XCTAssertEqual(LocalVideoSource.kind(of: "/Users/test/loop.mov"), .localVideo(path: "/Users/test/loop.mov"))
        XCTAssertEqual(LocalVideoSource.kind(of: "/Users/test/loop.m4v"), .localVideo(path: "/Users/test/loop.m4v"))
    }

    func test拡張子は大文字小文字を無視する() {
        XCTAssertEqual(LocalVideoSource.kind(of: "/Users/test/LOOP.MP4"), .localVideo(path: "/Users/test/LOOP.MP4"))
        XCTAssertEqual(LocalVideoSource.kind(of: "/Users/test/loop.MoV"), .localVideo(path: "/Users/test/loop.MoV"))
    }

    func testスペースを含むパスもローカル判定() {
        XCTAssertEqual(
            LocalVideoSource.kind(of: "/Users/test/My Movies/loop 1.mp4"),
            .localVideo(path: "/Users/test/My Movies/loop 1.mp4")
        )
    }

    func testチルダ始まりは未展開のままローカル判定() {
        XCTAssertEqual(LocalVideoSource.kind(of: "~/Movies/loop.mp4"), .localVideo(path: "~/Movies/loop.mp4"))
    }

    func test前後の空白は除去して判定する() {
        XCTAssertEqual(LocalVideoSource.kind(of: "  /Users/test/loop.mp4\n"), .localVideo(path: "/Users/test/loop.mp4"))
    }

    func test非対応拡張子はローカル判定しない() {
        XCTAssertEqual(LocalVideoSource.kind(of: "/Users/test/loop.avi"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "/Users/test/loop.mkv"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "file:///Users/test/loop.webm"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "/Users/test/loop"), .youtube)
        XCTAssertNil(LocalVideoSource.localPath(from: "/Users/test/loop.avi"))
    }

    func test相対パスは拒否する() {
        XCTAssertEqual(LocalVideoSource.kind(of: "Movies/loop.mp4"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "./loop.mp4"), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "../loop.mp4"), .youtube)
        XCTAssertNil(LocalVideoSource.localPath(from: "loop.mp4"))
    }

    func test空文字はyoutube扱い() {
        XCTAssertEqual(LocalVideoSource.kind(of: ""), .youtube)
        XCTAssertEqual(LocalVideoSource.kind(of: "   \n"), .youtube)
    }
}

final class LocalVideoSourceExpandTildeTests: XCTestCase {
    func testチルダスラッシュを展開する() {
        XCTAssertEqual(
            LocalVideoSource.expandTilde("~/Movies/loop.mp4", home: "/Users/test"),
            "/Users/test/Movies/loop.mp4"
        )
    }

    func testチルダ単体はホームを返す() {
        XCTAssertEqual(LocalVideoSource.expandTilde("~", home: "/Users/test"), "/Users/test")
    }

    func testチルダ以外はそのまま返す() {
        XCTAssertEqual(
            LocalVideoSource.expandTilde("/Users/test/loop.mp4", home: "/Users/other"),
            "/Users/test/loop.mp4"
        )
    }

    func testチルダユーザー形式は非対応でそのまま返す() {
        XCTAssertEqual(
            LocalVideoSource.expandTilde("~alice/loop.mp4", home: "/Users/test"),
            "~alice/loop.mp4"
        )
    }

    func testFileURLはチルダ展開込みで構築する() {
        XCTAssertEqual(
            LocalVideoSource.fileURL(for: "/Users/test/loop.mp4").path,
            "/Users/test/loop.mp4"
        )
        XCTAssertTrue(LocalVideoSource.fileURL(for: "~/Movies/loop.mp4").path.hasSuffix("/Movies/loop.mp4"))
        XCTAssertFalse(LocalVideoSource.fileURL(for: "~/Movies/loop.mp4").path.hasPrefix("~"))
    }
}
