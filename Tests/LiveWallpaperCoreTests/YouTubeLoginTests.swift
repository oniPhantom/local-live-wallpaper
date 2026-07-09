import XCTest
@testable import LiveWallpaperCore

final class YouTubeLoginTests: XCTestCase {
    func testYouTubeドメインのLOGIN_INFOでログイン済み() {
        XCTAssertTrue(YouTubeLogin.isLoggedIn(cookies: [
            (name: "LOGIN_INFO", domain: ".youtube.com"),
        ]))
        XCTAssertTrue(YouTubeLogin.isLoggedIn(cookies: [
            (name: "PREF", domain: ".youtube.com"),
            (name: "LOGIN_INFO", domain: "www.youtube.com"),
        ]))
    }

    func testドメイン表記ゆれを許容する() {
        XCTAssertTrue(YouTubeLogin.isLoginCookie(name: "LOGIN_INFO", domain: "youtube.com"))
        XCTAssertTrue(YouTubeLogin.isLoginCookie(name: "LOGIN_INFO", domain: ".youtube.com"))
        XCTAssertTrue(YouTubeLogin.isLoginCookie(name: "LOGIN_INFO", domain: "m.youtube.com"))
        XCTAssertTrue(YouTubeLogin.isLoginCookie(name: "LOGIN_INFO", domain: ".YouTube.com"))
    }

    func testLOGIN_INFO以外の名前は不一致() {
        XCTAssertFalse(YouTubeLogin.isLoggedIn(cookies: [
            (name: "PREF", domain: ".youtube.com"),
            (name: "VISITOR_INFO1_LIVE", domain: ".youtube.com"),
        ]))
        XCTAssertFalse(YouTubeLogin.isLoginCookie(name: "login_info", domain: ".youtube.com"))
    }

    func testYouTube以外のドメインは不一致() {
        XCTAssertFalse(YouTubeLogin.isLoginCookie(name: "LOGIN_INFO", domain: ".google.com"))
        XCTAssertFalse(YouTubeLogin.isLoginCookie(name: "LOGIN_INFO", domain: "fake-youtube.com"))
        XCTAssertFalse(YouTubeLogin.isLoginCookie(name: "LOGIN_INFO", domain: "youtube.com.evil.example"))
    }

    func testCookieなしは未ログイン() {
        XCTAssertFalse(YouTubeLogin.isLoggedIn(cookies: []))
    }
}
