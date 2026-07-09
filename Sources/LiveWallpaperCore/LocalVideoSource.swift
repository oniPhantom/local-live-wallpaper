import Foundation

// youtube-url.txt の内容から「YouTube ソース / ローカル動画ファイルソース」を判定する。
// 文字列判定は純粋関数として実装し、~ 展開・存在チェックは呼び出し側で分離できるようにしている
public enum LocalVideoSource {
    // AVPlayerLayer で再生するローカル動画の対応拡張子(大文字小文字無視)
    public static let supportedExtensions: Set<String> = ["mp4", "mov", "m4v"]

    // 再生ソースの種別
    public enum Kind: Equatable {
        // 従来どおり YouTube(URL / 動画 ID)として扱う
        case youtube
        // ローカル動画ファイル(path は ~ 未展開)
        case localVideo(path: String)
    }

    public static func kind(of raw: String) -> Kind {
        if let path = localPath(from: raw) {
            return .localVideo(path: path)
        }
        return .youtube
    }

    // ローカル動画と判定できればパス(~ 未展開)を返し、それ以外は nil。
    // 対象: file:// URL、または / か ~ で始まる絶対パスで、拡張子が mp4 / mov / m4v。
    // 相対パスはローカル扱いしない(YouTube の動画 ID 直接指定と区別できないため)
    public static func localPath(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let path: String
        if trimmed.lowercased().hasPrefix("file://") {
            guard let url = URL(string: trimmed), url.isFileURL, !url.path.isEmpty else {
                return nil
            }
            path = url.path
        } else if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            path = trimmed
        } else {
            return nil
        }
        let ext = (path as NSString).pathExtension.lowercased()
        guard supportedExtensions.contains(ext) else {
            return nil
        }
        return path
    }

    // ~ / ~/ をホームディレクトリに展開する(存在チェックはしない)。
    // home を差し替えられるようにしてテスト可能にしている
    public static func expandTilde(_ path: String, home: String = NSHomeDirectory()) -> String {
        guard path.hasPrefix("~") else {
            return path
        }
        if path == "~" {
            return home
        }
        if path.hasPrefix("~/") {
            return home + path.dropFirst(1)
        }
        // ~user 形式は非対応(そのまま返す)
        return path
    }

    // 判定済みパスを再生用の file URL にする(~ 展開込み)
    public static func fileURL(for path: String) -> URL {
        URL(fileURLWithPath: expandTilde(path))
    }
}
