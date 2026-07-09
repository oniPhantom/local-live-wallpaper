import Foundation

// YouTube のログイン状態判定(純粋ロジック)。
// WKWebsiteDataStore の cookie 一覧から youtube.com ドメインの LOGIN_INFO cookie を探す。
// LOGIN_INFO は Google アカウントでログインしたときのみ発行される永続 cookie で、
// ログアウト・「ログイン情報を消去」で消えるため、ログイン済みかどうかの目印に使える
public enum YouTubeLogin {
    // ログイン済みとみなす cookie 名
    public static let loginCookieName = "LOGIN_INFO"

    // cookie 一覧(名前とドメイン)からログイン済みかを判定する
    public static func isLoggedIn(cookies: [(name: String, domain: String)]) -> Bool {
        cookies.contains { isLoginCookie(name: $0.name, domain: $0.domain) }
    }

    // youtube.com(サブドメイン・先頭ドット付きを含む)の LOGIN_INFO cookie か
    public static func isLoginCookie(name: String, domain: String) -> Bool {
        guard name == loginCookieName else {
            return false
        }
        var normalized = domain.lowercased()
        if normalized.hasPrefix(".") {
            normalized = String(normalized.dropFirst())
        }
        return normalized == "youtube.com" || normalized.hasSuffix(".youtube.com")
    }
}
