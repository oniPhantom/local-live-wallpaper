import Cocoa
import IOKit.ps
import WebKit

// 壁紙・ログインウィンドウ共通の Safari 相当 UA(WebView 判定によるログイン拒否を避ける)
let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

enum WallpaperSource {
    static let configURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/youtube-url.txt")
    static let volumeURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/volume.txt")
    static let playlistURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/playlist.txt")
    static let largestOnlyURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/largest-only.txt")
    static let qualityURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/quality.txt")
    static let stateURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/state.json")
    static let panelHiddenURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/panel-hidden.txt")
    static let batteryPauseOffURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/battery-pause-off.txt")

    static let allowedQualities = ["small", "medium", "large", "hd720", "hd1080", "hd1440", "hd2160"]

    // 画質上限。既定は hd1080、"auto" 指定で無制限(vq は YouTube 側のベストエフォート)
    static func maxQuality() -> String? {
        let raw = ((try? String(contentsOf: qualityURL, encoding: .utf8)) ?? "hd1080")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if raw == "auto" {
            return nil
        }
        return allowedQualities.contains(raw) ? raw : "hd1080"
    }

    static func saveMaxQuality(_ quality: String) {
        let value = quality == "auto" || allowedQualities.contains(quality) ? quality : "hd1080"
        try? FileManager.default.createDirectory(at: qualityURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (value + "\n").write(to: qualityURL, atomically: true, encoding: .utf8)
    }

    static func saveState(_ object: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            return
        }
        try? FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: stateURL, options: .atomic)
    }

    static func clearState() {
        try? FileManager.default.removeItem(at: stateURL)
    }

    static func panelHidden() -> Bool {
        let raw = (try? String(contentsOf: panelHiddenURL, encoding: .utf8)) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    static func savePanelHidden(_ hidden: Bool) {
        if hidden {
            try? FileManager.default.createDirectory(at: panelHiddenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "1\n".write(to: panelHiddenURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: panelHiddenURL)
        }
    }

    static func pauseOnBattery() -> Bool {
        !FileManager.default.fileExists(atPath: batteryPauseOffURL.path)
    }

    static let panelOriginURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/panel-origin.txt")

    // ユーザーがドラッグしたパネル位置(スクリーン座標の origin)
    static func panelOrigin() -> NSPoint? {
        guard let raw = try? String(contentsOf: panelOriginURL, encoding: .utf8) else {
            return nil
        }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ",")
        guard parts.count == 2, let x = Double(parts[0]), let y = Double(parts[1]) else {
            return nil
        }
        return NSPoint(x: x, y: y)
    }

    static func savePanelOrigin(_ point: NSPoint) {
        try? FileManager.default.createDirectory(at: panelOriginURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(point.x),\(point.y)\n".write(to: panelOriginURL, atomically: true, encoding: .utf8)
    }

    static let fitModeURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/fit-mode.txt")

    // "contain": 動画全体を表示(FullHD は縦幅いっぱい・左右黒帯)/ "cover": 切り抜いて画面を埋める
    static func fitMode() -> String {
        let raw = ((try? String(contentsOf: fitModeURL, encoding: .utf8)) ?? "contain")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return raw == "cover" ? "cover" : "contain"
    }

    static func saveFitMode(_ mode: String) {
        try? FileManager.default.createDirectory(at: fitModeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? ((mode == "cover" ? "cover" : "contain") + "\n").write(to: fitModeURL, atomically: true, encoding: .utf8)
    }

    static func videoOnLargestScreenOnly() -> Bool {
        let raw = (try? String(contentsOf: largestOnlyURL, encoding: .utf8)) ?? ""
        return raw.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    static func saveVideoOnLargestScreenOnly(_ enabled: Bool) {
        if enabled {
            try? FileManager.default.createDirectory(at: largestOnlyURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? "1\n".write(to: largestOnlyURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: largestOnlyURL)
        }
    }

    static func sanitizeID(_ raw: String) -> String? {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return trimmed
    }

    static func playlistVideoIDs() -> [String] {
        guard let raw = try? String(contentsOf: playlistURL, encoding: .utf8) else {
            return []
        }
        return raw.split(whereSeparator: \.isNewline).compactMap { sanitizeID(String($0)) }
    }

    static func saveYouTubeURL(_ url: String) {
        try? FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (url + "\n").write(to: configURL, atomically: true, encoding: .utf8)
    }

    static func savePlaylist(_ videoIDs: [String]) {
        let ids = videoIDs.compactMap(sanitizeID)
        if ids.isEmpty {
            try? FileManager.default.removeItem(at: playlistURL)
            return
        }
        try? FileManager.default.createDirectory(at: playlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (ids.joined(separator: "\n") + "\n").write(to: playlistURL, atomically: true, encoding: .utf8)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: configURL)
        try? FileManager.default.removeItem(at: playlistURL)
    }

    static func youtubeID() -> String? {
        guard let url = youtubeURL() else {
            return nil
        }
        return youtubeID(from: url).flatMap(sanitizeID)
    }

    static func youtubePlaylistID() -> String? {
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

    static func volume() -> Int {
        let raw = (try? String(contentsOf: volumeURL, encoding: .utf8)) ?? "0"
        return min(100, max(0, Int(raw.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0))
    }

    // 再生 URL の t= / start= パラメータ("180s" "3m20s" "180" 形式)を秒に変換する
    static func startSeconds() -> Int? {
        guard let url = youtubeURL(),
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "t" || $0.name == "start" })?
                .value else {
            return nil
        }
        return parseTimeParam(raw)
    }

    static func parseTimeParam(_ raw: String) -> Int? {
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

    static func saveVolume(_ volume: Int) {
        try? FileManager.default.createDirectory(at: volumeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? "\(min(100, max(0, volume)))\n".write(to: volumeURL, atomically: true, encoding: .utf8)
    }

    private static func youtubeID(from url: URL) -> String? {
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

// userContentController は handler を強参照するため、view 自身を直接渡すと循環参照になる
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    init(delegate: WKScriptMessageHandler) {
        self.delegate = delegate
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

final class YouTubeView: WKWebView, WKScriptMessageHandler {
    // event: "playing" | "error" | "stalled", code: YT エラーコード(error 時のみ)
    var onPlayerEvent: ((String, Int) -> Void)?

    init(frame: NSRect, videoID: String?, playlistID: String?, videoIDs: [String], volume: Int, startSeconds: Int?) {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        // 本物の watch ページを開き、CSS/JS を注入して動画だけを全画面表示する。
        // embed はログイン済みでもエラー 152 で拒否されるため watch 方式を採る
        let singleLoop = playlistID == nil && videoIDs.count <= 1
        config.userContentController.addUserScript(WKUserScript(
            source: Self.controlScript(volume: volume, singleLoop: singleLoop),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        super.init(frame: frame, configuration: config)
        configuration.userContentController.add(WeakScriptMessageHandler(delegate: self), name: "wallpaper")
        wantsLayer = true
        customUserAgent = safariUserAgent
        setValue(false, forKey: "drawsBackground")
        if let url = Self.watchURL(videoID: videoID, playlistID: playlistID, videoIDs: videoIDs, startSeconds: startSeconds) {
            load(URLRequest(url: url))
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let event = body["event"] as? String else {
            return
        }
        let code = (body["code"] as? NSNumber)?.intValue ?? 0
        onPlayerEvent?(event, code)
    }

    func setVolume(_ volume: Int) {
        evaluateJavaScript("setWallpaperVolume(\(min(100, max(0, volume))))")
    }

    func togglePlayback() {
        evaluateJavaScript("toggleWallpaperPlayback()")
    }

    func previousVideo() {
        evaluateJavaScript("previousWallpaperVideo()")
    }

    func nextVideo() {
        evaluateJavaScript("nextWallpaperVideo()")
    }

    func seek(to percent: Double) {
        let bounded = min(1.0, max(0.0, percent))
        evaluateJavaScript("seekWallpaperVideo(\(bounded))")
    }

    func setSubtitles(enabled: Bool) {
        evaluateJavaScript("setWallpaperSubtitles(\(enabled))")
    }

    func setQuality(_ quality: String) {
        let value = quality == "auto" || WallpaperSource.allowedQualities.contains(quality) ? quality : "hd1080"
        evaluateJavaScript("setWallpaperQuality('\(value)')")
    }

    func pause() {
        evaluateJavaScript("pauseWallpaperVideo()")
    }

    func resume() {
        evaluateJavaScript("resumeWallpaperVideo()")
    }

    func readStatus(_ completion: @escaping ([String: Any]?) -> Void) {
        evaluateJavaScript("wallpaperVideoStatus()") { result, _ in
            completion(result as? [String: Any])
        }
    }

    private var lastFitRect: [Double] = []
    private var lastFitMode = ""

    func invalidateFit() {
        lastFitRect = []
        lastFitMode = ""
    }

    // video の実描画 rect(ビューポート座標・top-left 原点)を画面に合わせるよう、
    // WKWebView のレイヤーを拡大・平行移動する。CSS と違い動画レイヤーごと変形される
    func applyFit(status: [String: Any]) {
        guard let rectNumbers = status["rect"] as? [NSNumber], rectNumbers.count == 4 else {
            return
        }
        let rect = rectNumbers.map(\.doubleValue)
        guard rect[2] > 1, rect[3] > 1 else {
            return
        }
        let mode = WallpaperSource.fitMode()
        if rect == lastFitRect && mode == lastFitMode {
            return
        }
        lastFitRect = rect
        lastFitMode = mode
        guard let layer else {
            return
        }
        let width = Double(bounds.width)
        let height = Double(bounds.height)
        // contain: 動画全体が収まる倍率(FullHD は縦幅いっぱい)/ cover: 画面を埋める倍率
        let scale = mode == "cover"
            ? max(width / rect[2], height / rect[3])
            : min(width / rect[2], height / rect[3])
        // レイヤー座標は左下原点なので top-left 基準の rect を変換する
        let rectBottom = height - rect[1] - rect[3]
        let tx = (width - rect[2] * scale) / 2 - rect[0] * scale
        let ty = (height - rect[3] * scale) / 2 - rectBottom * scale
        layer.anchorPoint = CGPoint(x: 0, y: 0)
        layer.position = CGPoint(x: 0, y: 0)
        var transform = CATransform3DMakeTranslation(CGFloat(tx), CGFloat(ty), 0)
        transform = CATransform3DScale(transform, CGFloat(scale), CGFloat(scale), 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = transform
        CATransaction.commit()
    }

    // watch ページの URL を構築する。複数 ID は watch_videos で匿名プレイリスト化
    private static func watchURL(videoID: String?, playlistID: String?, videoIDs: [String], startSeconds: Int?) -> URL? {
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

    // watch ページに注入する操作 JS。ページ UI を隠して <video> を全画面固定にし、
    // movie_player (watch ページの player API) と <video> 要素で操作する
    private static func controlScript(volume: Int, singleLoop: Bool) -> String {
        let quality = WallpaperSource.maxQuality().map { "'\($0)'" } ?? "null"
        return """
        (function() {
          if (window.__wallpaperInstalled) return;
          window.__wallpaperInstalled = true;
          var everPlayed = false;
          var pendingVolume = \(min(100, max(0, volume)));
          var singleLoop = \(singleLoop);
          var maxQuality = \(quality);
          function notifyNative(payload) {
            try { window.webkit.messageHandlers.wallpaper.postMessage(payload); } catch (e) {}
          }
          function moviePlayer() { return document.getElementById('movie_player'); }
          function videoEl() { return document.querySelector('#movie_player video, video'); }

          // ページ UI は隠して video だけ見せる。サイズ・位置は CSS では触らず、
          // native 側が video の実描画 rect を読んで WKWebView のレイヤーを変形して合わせる
          // (CSS で video を広げても WKWebView の動画レイヤーが追従せず崩れるため)
          var style = document.createElement('style');
          style.textContent = [
            'html, body { background: #000 !important; overflow: hidden !important; }',
            'ytd-app { visibility: hidden !important; }',
            '#movie_player video { visibility: visible !important; background: #000 !important; }'
          ].join('\\n');
          (document.head || document.documentElement).appendChild(style);

          // 音量変更は再生状態に影響させない(playVideo を呼ぶと一時停止中でも勝手に再生される)
          window.setWallpaperVolume = function(volume) {
            pendingVolume = volume;
            var p = moviePlayer();
            var v = videoEl();
            if (p && p.setVolume) {
              p.setVolume(volume);
              if (volume > 0) {
                if (p.unMute) p.unMute();
              } else if (p.mute) {
                p.mute();
              }
            } else if (v) {
              v.volume = Math.min(1, Math.max(0, volume / 100));
              v.muted = volume <= 0;
            }
          };
          window.pauseWallpaperVideo = function() {
            var p = moviePlayer();
            if (p && p.pauseVideo) { p.pauseVideo(); return; }
            var v = videoEl();
            if (v) v.pause();
          };
          window.resumeWallpaperVideo = function() {
            var p = moviePlayer();
            if (p && p.playVideo) { p.playVideo(); return; }
            var v = videoEl();
            if (v) v.play();
          };
          window.toggleWallpaperPlayback = function() {
            var v = videoEl();
            if (!v) return;
            if (v.paused || v.ended) {
              window.resumeWallpaperVideo();
            } else {
              window.pauseWallpaperVideo();
            }
          };
          window.previousWallpaperVideo = function() {
            var p = moviePlayer();
            if (p && p.previousVideo) p.previousVideo();
          };
          window.nextWallpaperVideo = function() {
            var p = moviePlayer();
            if (p && p.nextVideo) p.nextVideo();
          };
          // シークも再生状態は維持する(一時停止中なら止まったまま位置だけ動かす)
          window.seekWallpaperVideo = function(percent) {
            var v = videoEl();
            if (!v || !v.duration) return;
            v.currentTime = v.duration * Math.min(1, Math.max(0, percent));
          };
          window.setWallpaperSubtitles = function(enabled) {
            var p = moviePlayer();
            if (!p) return;
            if (enabled && p.loadModule) p.loadModule('captions');
            if (!enabled && p.unloadModule) p.unloadModule('captions');
          };
          window.setWallpaperQuality = function(q) {
            maxQuality = q === 'auto' ? null : q;
            var p = moviePlayer();
            if (!p || !p.setPlaybackQualityRange) return;
            try {
              if (q === 'auto') {
                p.setPlaybackQualityRange('auto');
              } else {
                p.setPlaybackQualityRange(q, q);
              }
            } catch (e) {}
          };
          window.wallpaperVideoStatus = function() {
            var v = videoEl();
            var status = {progress: 0, playing: false};
            if (v && v.duration > 0) status.progress = v.currentTime / v.duration;
            if (v) {
              status.playing = !v.paused && !v.ended;
              status.currentTime = v.currentTime || 0;
              status.duration = (isFinite(v.duration) && v.duration > 0) ? v.duration : 0;
              // フィット検証用: video の実描画位置とビューポートサイズ
              var r = v.getBoundingClientRect();
              status.rect = [Math.round(r.left), Math.round(r.top), Math.round(r.width), Math.round(r.height)];
              status.viewport = [window.innerWidth, window.innerHeight];
            }
            return status;
          };

          function watchVideo() {
            var v = videoEl();
            if (!v) {
              window.setTimeout(watchVideo, 500);
              return;
            }
            if (singleLoop) {
              v.loop = true;
            }
            v.addEventListener('playing', function() {
              if (!everPlayed) {
                everPlayed = true;
                notifyNative({event: 'playing', code: 0});
              }
              window.setWallpaperVolume(pendingVolume);
              var p = moviePlayer();
              if (maxQuality && p && p.setPlaybackQualityRange) {
                try { p.setPlaybackQualityRange(maxQuality, maxQuality); } catch (e) {}
              }
            });
            // watch ページは音アリで自動再生されるので、初期音量を即適用する
            window.setWallpaperVolume(pendingVolume);
            v.play();
          }
          watchVideo();

          // エラー画面の検出
          var errorPoll = window.setInterval(function() {
            if (document.querySelector('.ytp-error')) {
              window.clearInterval(errorPoll);
              notifyNative({event: 'error', code: 0});
            }
          }, 3000);

          // 一定時間再生が始まらなければ失敗として通知
          window.setTimeout(function() {
            if (!everPlayed) notifyNative({event: 'stalled', code: 0});
          }, 45000);
        })();
        """
    }
}

// YouTube ログイン用の通常ウィンドウ。壁紙の WKWebView と同じ既定 data store を
// 使うため、ここでログインすれば壁紙側も Premium セッションで再生される
final class LoginWindowController: NSObject, WKUIDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    var onClose: (() -> Void)?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 520, height: 700), configuration: config)
        webView.customUserAgent = safariUserAgent
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "YouTube にログイン(閉じると壁紙に反映)"
        window.level = .floating
        window.contentView = webView
        window.center()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )
        webView.load(URLRequest(url: URL(string: "https://www.youtube.com/")!))
        window.makeKeyAndOrderFront(nil)
        self.window = window
        self.webView = webView
    }

    @objc private func windowWillClose(_ notification: Notification) {
        if let window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: window)
        }
        webView = nil
        window = nil
        onClose?()
    }

    // ログインフローが target=_blank で開こうとするページは同じ webview で開く
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

final class ProgressBar: NSView {
    var onSeek: ((Double) -> Void)?
    private var progress: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 0, dy: 6)
        NSColor(calibratedWhite: 1, alpha: 0.18).setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()

        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height)
        NSColor(calibratedRed: 1.0, green: 0.15, blue: 0.12, alpha: 0.95).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4).fill()

        let knobX = track.minX + track.width * progress
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX - 5, y: track.midY - 5, width: 10, height: 10)).fill()
    }

    override func mouseDown(with event: NSEvent) {
        seek(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        seek(with: event)
    }

    func setProgress(_ progress: Double) {
        self.progress = min(1, max(0, progress))
        needsDisplay = true
    }

    private func seek(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let percent = Double(min(bounds.maxX, max(bounds.minX, x)) / bounds.width)
        setProgress(percent)
        onSeek?(percent)
    }
}

final class VolumePanel: NSPanel {
    var onChange: ((Int) -> Void)?
    var onSeek: ((Double) -> Void)?
    var onTogglePlayback: (() -> Void)?
    var onPreviousVideo: (() -> Void)?
    var onNextVideo: (() -> Void)?
    var onQualityChange: ((String) -> Void)?

    // 表示名 → vq 値。パネルのポップアップで使う
    static let qualityOptions: [(title: String, value: String)] = [
        ("自動", "auto"),
        ("2160p", "hd2160"),
        ("1440p", "hd1440"),
        ("1080p", "hd1080"),
        ("720p", "hd720"),
        ("480p", "large"),
    ]

    private let expandedSize = NSSize(width: 300, height: 158)
    private let collapsedSize = NSSize(width: 300, height: 34)
    private let root: NSVisualEffectView
    private let valueLabel = NSTextField(labelWithString: "0")
    private let progressBar = ProgressBar(frame: NSRect(x: 16, y: 14, width: 268, height: 14))
    private let collapseButton = NSButton(frame: .zero)
    private let playButton = NSButton(frame: .zero)
    private let qualityPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let currentTimeLabel = NSTextField(labelWithString: "--:--")
    private let durationLabel = NSTextField(labelWithString: "--:--")
    private let stateLabel = NSTextField(labelWithString: "")
    private var isPlayingIcon = false
    private var collapsibleViews: [NSView] = []
    private var isCollapsed = false

    init(volume: Int) {
        let frame = NSRect(origin: .zero, size: expandedSize)
        root = NSVisualEffectView(frame: frame)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        // 背景の空き部分をドラッグしてパネルを移動できるようにする
        isMovableByWindowBackground = true

        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor

        // ヘッダー: ロゴ + タイトル / 画質 / 折りたたみ
        let logo = NSImageView(frame: NSRect(x: 16, y: 126, width: 18, height: 18))
        logo.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        logo.contentTintColor = NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.13, alpha: 1)
        root.addSubview(logo)
        collapsibleViews.append(logo)

        let title = NSTextField(labelWithString: "YouTube Wallpaper")
        title.frame = NSRect(x: 39, y: 127, width: 140, height: 16)
        title.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        root.addSubview(title)
        collapsibleViews.append(title)

        qualityPopUp.frame = NSRect(x: 184, y: 123, width: 80, height: 22)
        qualityPopUp.controlSize = .small
        qualityPopUp.font = .systemFont(ofSize: 10, weight: .medium)
        Self.qualityOptions.forEach { qualityPopUp.addItem(withTitle: $0.title) }
        let currentQuality = WallpaperSource.maxQuality() ?? "auto"
        if let index = Self.qualityOptions.firstIndex(where: { $0.value == currentQuality }) {
            qualityPopUp.selectItem(at: index)
        }
        qualityPopUp.target = self
        qualityPopUp.action = #selector(qualityChanged(_:))
        root.addSubview(qualityPopUp)
        collapsibleViews.append(qualityPopUp)

        configureIconButton(collapseButton, symbol: "chevron.down", size: 11, action: #selector(toggleCollapsed))
        collapseButton.frame = NSRect(x: 266, y: 124, width: 20, height: 20)
        root.addSubview(collapseButton)

        // トランスポート(中央寄せ)
        let previousButton = makeIconButton(symbol: "backward.fill", size: 15, action: #selector(previousTapped))
        previousButton.frame = NSRect(x: 92, y: 76, width: 36, height: 30)
        root.addSubview(previousButton)
        collapsibleViews.append(previousButton)

        configureIconButton(playButton, symbol: "play.fill", size: 19, action: #selector(playTapped))
        playButton.frame = NSRect(x: 132, y: 74, width: 36, height: 34)
        root.addSubview(playButton)
        collapsibleViews.append(playButton)

        let nextButton = makeIconButton(symbol: "forward.fill", size: 15, action: #selector(nextTapped))
        nextButton.frame = NSRect(x: 172, y: 76, width: 36, height: 30)
        root.addSubview(nextButton)
        collapsibleViews.append(nextButton)

        // 音量
        let speaker = NSImageView(frame: NSRect(x: 16, y: 50, width: 16, height: 16))
        speaker.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        speaker.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.6)
        root.addSubview(speaker)
        collapsibleViews.append(speaker)

        let slider = NSSlider(value: Double(volume), minValue: 0, maxValue: 100, target: self, action: #selector(changed(_:)))
        slider.frame = NSRect(x: 38, y: 48, width: 206, height: 20)
        slider.controlSize = .small
        slider.isContinuous = true
        root.addSubview(slider)
        collapsibleViews.append(slider)

        valueLabel.frame = NSRect(x: 250, y: 50, width: 34, height: 16)
        valueLabel.alignment = .right
        valueLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.6)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        root.addSubview(valueLabel)
        collapsibleViews.append(valueLabel)

        // 時間・再生状態の行
        currentTimeLabel.frame = NSRect(x: 16, y: 30, width: 84, height: 13)
        currentTimeLabel.alignment = .left
        currentTimeLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.75)
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        root.addSubview(currentTimeLabel)
        collapsibleViews.append(currentTimeLabel)

        stateLabel.frame = NSRect(x: 100, y: 30, width: 100, height: 13)
        stateLabel.alignment = .center
        stateLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.45)
        stateLabel.font = .systemFont(ofSize: 9, weight: .medium)
        root.addSubview(stateLabel)
        collapsibleViews.append(stateLabel)

        durationLabel.frame = NSRect(x: 200, y: 30, width: 84, height: 13)
        durationLabel.alignment = .right
        durationLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.75)
        durationLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        root.addSubview(durationLabel)
        collapsibleViews.append(durationLabel)

        // シーク
        progressBar.onSeek = { [weak self] percent in
            self?.onSeek?(percent)
        }
        root.addSubview(progressBar)

        contentView = root
        changed(slider)
    }

    private func makeIconButton(symbol: String, size: CGFloat, action: Selector) -> NSButton {
        let button = NSButton(frame: .zero)
        configureIconButton(button, symbol: symbol, size: size, action: action)
        return button
    }

    private func configureIconButton(_ button: NSButton, symbol: String, size: CGFloat, action: Selector) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        button.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.85)
    }

    @objc private func changed(_ sender: NSSlider) {
        let volume = sender.integerValue
        valueLabel.stringValue = "\(volume)"
        onChange?(volume)
    }

    func setProgress(_ progress: Double) {
        progressBar.setProgress(progress)
    }

    // 実再生状態を表示に反映: 再生ボタンのアイコン・状態テキスト・時間表示
    func updateStatus(playing: Bool, currentTime: Double, duration: Double) {
        if playing != isPlayingIcon {
            isPlayingIcon = playing
            configureIconButton(playButton, symbol: playing ? "pause.fill" : "play.fill", size: 19, action: #selector(playTapped))
        }
        stateLabel.stringValue = playing ? "再生中" : "一時停止"
        stateLabel.textColor = playing
            ? NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 0.9)
            : NSColor(calibratedWhite: 1, alpha: 0.45)
        currentTimeLabel.stringValue = Self.formatTime(currentTime)
        // duration 0 はライブ配信や未取得
        durationLabel.stringValue = duration > 0 ? Self.formatTime(duration) : "--:--"
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else {
            return "--:--"
        }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    @objc private func playTapped() {
        onTogglePlayback?()
    }

    @objc private func previousTapped() {
        onPreviousVideo?()
    }

    @objc private func nextTapped() {
        onNextVideo?()
    }

    @objc private func qualityChanged(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard Self.qualityOptions.indices.contains(index) else {
            return
        }
        onQualityChange?(Self.qualityOptions[index].value)
    }

    @objc private func toggleCollapsed() {
        isCollapsed.toggle()
        collapsibleViews.forEach { $0.isHidden = isCollapsed }
        configureIconButton(collapseButton, symbol: isCollapsed ? "chevron.up" : "chevron.down", size: 11, action: #selector(toggleCollapsed))
        collapseButton.frame = isCollapsed
            ? NSRect(x: 266, y: 7, width: 20, height: 20)
            : NSRect(x: 266, y: 124, width: 20, height: 20)
        progressBar.frame = isCollapsed
            ? NSRect(x: 16, y: 10, width: 242, height: 14)
            : NSRect(x: 16, y: 14, width: 268, height: 14)

        let newSize = isCollapsed ? collapsedSize : expandedSize
        var frame = frame
        frame.size = newSize
        setFrame(frame, display: true, animate: true)
        root.frame = NSRect(origin: .zero, size: newSize)
    }
}

final class WallpaperView: NSView {
    private var timer: Timer?
    private let start = CACurrentMediaTime()
    private let starCount = 90

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let t = CACurrentMediaTime() - start
        let rect = bounds
        let cg = NSGraphicsContext.current?.cgContext

        NSColor(calibratedRed: 0.005, green: 0.008, blue: 0.018, alpha: 1).setFill()
        rect.fill()

        NSGradient(colors: [
            NSColor(calibratedRed: 0.01, green: 0.015, blue: 0.04, alpha: 1),
            NSColor(calibratedRed: 0.02, green: 0.08, blue: 0.12, alpha: 1),
            NSColor(calibratedRed: 0.12, green: 0.025, blue: 0.09, alpha: 1),
            NSColor(calibratedRed: 0.005, green: 0.008, blue: 0.018, alpha: 1)
        ])?.draw(in: rect, angle: 45 + CGFloat(sin(t * 0.03)) * 12)

        drawStars(in: rect, time: t)
        drawAurora(in: rect, time: t)
        drawOrbitalGlow(in: rect, time: t)
        drawPerspectiveGrid(in: rect, time: t)

        cg?.saveGState()
        cg?.setBlendMode(.multiply)
        NSGradient(colors: [
            NSColor(calibratedWhite: 0, alpha: 0.78),
            NSColor(calibratedWhite: 0, alpha: 0.10),
            NSColor(calibratedWhite: 0, alpha: 0.82)
        ])?.draw(in: rect, relativeCenterPosition: NSPoint(x: 0, y: 0))
        cg?.restoreGState()

        NSColor(calibratedWhite: 1, alpha: 0.018).setFill()
        for y in stride(from: 0, to: Int(rect.height), by: 5) {
            NSBezierPath(rect: NSRect(x: 0, y: CGFloat(y), width: rect.width, height: 1)).fill()
        }
    }

    private func drawStars(in rect: NSRect, time: TimeInterval) {
        for i in 0..<starCount {
            let seed = Double(i)
            let x = CGFloat((sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1).magnitude) * rect.width
            let y = CGFloat((sin(seed * 78.233) * 24634.6345).truncatingRemainder(dividingBy: 1).magnitude) * rect.height
            let pulse = 0.25 + 0.75 * CGFloat(pow(max(0, sin(time * 0.7 + seed)), 2))
            let size = CGFloat(0.8 + fmod(seed, 3)) * pulse

            NSColor(calibratedRed: 0.72, green: 0.92, blue: 1, alpha: 0.20 + 0.38 * pulse).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: size, height: size)).fill()
        }
    }

    private func drawAurora(in rect: NSRect, time: TimeInterval) {
        let colors = [
            NSColor(calibratedRed: 0.04, green: 0.96, blue: 0.82, alpha: 0.18),
            NSColor(calibratedRed: 0.32, green: 0.30, blue: 1.00, alpha: 0.16),
            NSColor(calibratedRed: 1.00, green: 0.20, blue: 0.58, alpha: 0.12)
        ]

        for band in 0..<4 {
            let path = NSBezierPath()
            let yBase = rect.midY + rect.height * CGFloat(0.08 + Double(band) * 0.035)
            path.move(to: NSPoint(x: -rect.width * 0.1, y: yBase))

            for step in 0...7 {
                let x = rect.width * CGFloat(Double(step) / 6.0) - rect.width * 0.08
                let wave = sin(time * (0.22 + Double(band) * 0.025) + Double(step) * 0.9 + Double(band))
                let y = yBase + CGFloat(wave) * rect.height * CGFloat(0.05 + Double(band) * 0.006)
                path.line(to: NSPoint(x: x, y: y))
            }

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 38 + CGFloat(band) * 10
            shadow.shadowColor = colors[band % colors.count]
            shadow.set()
            colors[band % colors.count].setStroke()
            path.lineWidth = 36 + CGFloat(band) * 7
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawOrbitalGlow(in rect: NSRect, time: TimeInterval) {
        let center = NSPoint(
            x: rect.midX + CGFloat(cos(time * 0.08)) * rect.width * 0.08,
            y: rect.midY + CGFloat(sin(time * 0.06)) * rect.height * 0.05
        )

        for i in 0..<5 {
            let scale = CGFloat(0.36 + Double(i) * 0.08)
            let w = rect.width * scale
            let h = w * CGFloat(0.18 + Double(i) * 0.018)
            let oval = NSRect(x: center.x - w / 2, y: center.y - h / 2, width: w, height: h)

            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: CGFloat(12 + i * 13) + CGFloat(sin(time * 0.1)) * 10)
            transform.translateX(by: -center.x, yBy: -center.y)
            transform.concat()

            NSColor(calibratedRed: 0.40, green: 0.90, blue: 1.00, alpha: 0.08).setStroke()
            let path = NSBezierPath(ovalIn: oval)
            path.lineWidth = 1.2
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawPerspectiveGrid(in rect: NSRect, time: TimeInterval) {
        let horizon = rect.height * 0.30
        let bottom = rect.height
        let color = NSColor(calibratedRed: 0.12, green: 0.95, blue: 1, alpha: 0.14)
        color.setStroke()

        for i in -7...7 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: rect.midX + CGFloat(i) * rect.width * 0.035, y: horizon))
            path.line(to: NSPoint(x: rect.midX + CGFloat(i) * rect.width * 0.16, y: bottom))
            path.lineWidth = 1
            path.stroke()
        }

        for i in 0..<12 {
            let progress = CGFloat(i) / 12
            let y = horizon + pow(progress, 2.1) * (bottom - horizon)
            let offset = CGFloat(fmod(time * 18, 36))
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 0, y: y + offset))
            path.line(to: NSPoint(x: rect.width, y: y + offset))
            path.lineWidth = 1
            path.stroke()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var windows: [NSWindow] = []
    private var youtubeViews: [YouTubeView] = []
    private var volumePanel: VolumePanel?
    private var progressTimer: Timer?
    private var statusItem: NSStatusItem?

    // 再生失敗時のフォールバック管理
    private var playbackFailureCount = 0
    private var fallbackActive = false
    private var retryTimer: Timer?

    // 自動一時停止(ロック・全面遮蔽・バッテリー駆動)
    private var autoPauseReasons: Set<String> = []
    private var autoPaused = false
    private var batteryTimer: Timer?

    // ユーザーが明示的に一時停止したか(自動復帰や再構築で勝手に再生しないため)
    private var userPaused = false
    private var lastPlaying = false
    private var lastProgress: Double = 0
    // ディスプレイ構成変更などの再構築後に復元する再生位置と再生状態
    private var pendingRestore: (progress: Double, resume: Bool)?

    private let loginWindow = LoginWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeMainMenu()
        makeStatusItem()
        makeWindows()
        loginWindow.onClose = { [weak self] in
            // ログイン後の cookie で player を作り直す(フォールバック中でも即再挑戦)
            self?.resetFallback()
            self?.makeWindows()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(makeWindows),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleRemoteCommand(_:)),
            name: Notification.Name("com.codex.livewallpaper.command"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        let lockEvents: [(String, Bool)] = [
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false),
            ("com.apple.screensaver.didstart", true),
            ("com.apple.screensaver.didstop", false),
        ]
        for (name, paused) in lockEvents {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.setAutoPauseReason("locked", active: paused)
            }
        }
        batteryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkBattery()
        }
        checkBattery()
    }

    @objc private func handleRemoteCommand(_ notification: Notification) {
        guard let json = notification.object as? String,
              let data = json.data(using: .utf8),
              let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = command["type"] as? String else {
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.apply(type: type, command: command)
        }
    }

    private func apply(type: String, command: [String: Any]) {
        switch type {
        case "play", "reload":
            // native-host が設定ファイルを書き換えた後に届くので再読み込みだけで良い
            resetFallback()
            rebuildWindows(fresh: true)
        case "off":
            resetFallback()
            rebuildWindows(fresh: true)
        case "pause", "toggle":
            togglePlaybackTracked()
        case "next":
            youtubeViews.forEach { $0.nextVideo() }
        case "previous":
            youtubeViews.forEach { $0.previousVideo() }
        case "seek":
            if let percent = (command["percent"] as? NSNumber)?.doubleValue {
                youtubeViews.forEach { $0.seek(to: percent) }
            }
        case "volume":
            if let value = (command["value"] as? NSNumber)?.intValue {
                let bounded = min(100, max(0, value))
                WallpaperSource.saveVolume(bounded)
                applyVolume(bounded)
            }
        case "subtitles":
            if let enabled = command["enabled"] as? Bool {
                youtubeViews.forEach { $0.setSubtitles(enabled: enabled) }
            }
        case "screens":
            // native-host が設定ファイルを書き換え済みなので再構成のみ
            makeWindows()
        case "quality":
            // watch ページはリロード不要で即時反映できる
            let quality = WallpaperSource.maxQuality() ?? "auto"
            youtubeViews.forEach { $0.setQuality(quality) }
        case "login":
            loginWindow.show()
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    // MARK: - 再生失敗フォールバック

    private func resetFallback() {
        playbackFailureCount = 0
        fallbackActive = false
        retryTimer?.invalidate()
        retryTimer = nil
    }

    private func handlePlayerEvent(_ event: String, code: Int) {
        switch event {
        case "playing":
            playbackFailureCount = 0
            // 再構築後の復元: 再生位置を戻し、一時停止中だった場合は止め直す
            if let restore = pendingRestore {
                pendingRestore = nil
                if restore.progress > 0.005 && restore.progress < 0.995 {
                    youtubeViews.forEach { $0.seek(to: restore.progress) }
                }
                if !restore.resume {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.youtubeViews.forEach { $0.pause() }
                    }
                }
            }
        case "error", "stalled":
            playbackFailureCount += 1
            NSLog("wallpaper playback failure #%d (event=%@ code=%d)", playbackFailureCount, event, code)
            if playbackFailureCount < 2 {
                // 30 秒おいて 1 回だけ再試行。短間隔で再ロードを繰り返すと
                // bot 判定をかえって延命させるため控えめにする
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    guard let self, !self.fallbackActive else { return }
                    self.makeWindows()
                }
            } else {
                // アニメ壁紙へ退避し、15 分間隔で自動再挑戦
                fallbackActive = true
                makeWindows()
                retryTimer?.invalidate()
                retryTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    self.playbackFailureCount = 0
                    self.fallbackActive = false
                    self.makeWindows()
                }
            }
        default:
            break
        }
    }

    // MARK: - 自動一時停止

    private func setAutoPauseReason(_ reason: String, active: Bool) {
        if active {
            autoPauseReasons.insert(reason)
        } else {
            autoPauseReasons.remove(reason)
        }
        updateAutoPauseState()
    }

    private func updateAutoPauseState() {
        let shouldPause = !autoPauseReasons.isEmpty
        guard shouldPause != autoPaused else {
            return
        }
        autoPaused = shouldPause
        if shouldPause {
            youtubeViews.forEach { $0.pause() }
        } else if !userPaused {
            // ユーザーが止めていた場合はワークスペース切替などで勝手に再生しない
            youtubeViews.forEach { $0.resume() }
        }
    }

    // 再生/一時停止トグル。直前の実再生状態からユーザーの意図(止めたい/再生したい)を記録する
    private func togglePlaybackTracked() {
        userPaused = lastPlaying
        youtubeViews.forEach { $0.togglePlayback() }
    }

    @objc private func occlusionChanged() {
        guard !youtubeViews.isEmpty else {
            return
        }
        let anyVisible = windows.contains { $0.occlusionState.contains(.visible) }
        setAutoPauseReason("occluded", active: !anyVisible)
    }

    private func checkBattery() {
        guard WallpaperSource.pauseOnBattery() else {
            setAutoPauseReason("battery", active: false)
            return
        }
        let onBattery = (IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String?) == kIOPMBatteryPowerKey
        setAutoPauseReason("battery", active: onBattery)
    }

    // MARK: - メニューバー

    // メニューを持たない accessory アプリでは Cmd+C/V などのキーイコライザが効かないため、
    // ログインウィンドウでのコピー & ペースト用に Edit メニューを持つ main menu を設定する
    private func makeMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "CodexLiveWallpaper を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "取り消す", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "やり直す", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    private func makeStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "play.tv", accessibilityDescription: "Codex Live Wallpaper")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hasVideo = !youtubeViews.isEmpty

        let toggle = NSMenuItem(title: "再生 / 一時停止", action: #selector(menuToggle), keyEquivalent: "")
        toggle.target = self
        toggle.isEnabled = hasVideo
        menu.addItem(toggle)

        let previous = NSMenuItem(title: "前の動画", action: #selector(menuPrevious), keyEquivalent: "")
        previous.target = self
        previous.isEnabled = hasVideo
        menu.addItem(previous)

        let next = NSMenuItem(title: "次の動画", action: #selector(menuNext), keyEquivalent: "")
        next.target = self
        next.isEnabled = hasVideo
        menu.addItem(next)

        menu.addItem(.separator())

        let panel = NSMenuItem(title: "操作パネルを表示", action: #selector(menuTogglePanel), keyEquivalent: "")
        panel.target = self
        panel.state = WallpaperSource.panelHidden() ? .off : .on
        menu.addItem(panel)

        let largest = NSMenuItem(title: "最大モニターのみ表示", action: #selector(menuToggleLargestOnly), keyEquivalent: "")
        largest.target = self
        largest.state = WallpaperSource.videoOnLargestScreenOnly() ? .on : .off
        menu.addItem(largest)

        let cover = NSMenuItem(title: "切り抜いて画面を埋める", action: #selector(menuToggleFitMode), keyEquivalent: "")
        cover.target = self
        cover.state = WallpaperSource.fitMode() == "cover" ? .on : .off
        menu.addItem(cover)

        menu.addItem(.separator())

        let login = NSMenuItem(title: "YouTube にログイン…", action: #selector(menuLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)

        let logout = NSMenuItem(title: "ログイン情報を消去", action: #selector(menuClearWebData), keyEquivalent: "")
        logout.target = self
        menu.addItem(logout)

        menu.addItem(.separator())

        let off = NSMenuItem(title: "壁紙を止める", action: #selector(menuOff), keyEquivalent: "")
        off.target = self
        off.isEnabled = hasVideo
        menu.addItem(off)

        let quit = NSMenuItem(title: "終了", action: #selector(menuQuit), keyEquivalent: "")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func menuToggle() {
        togglePlaybackTracked()
    }

    @objc private func menuPrevious() {
        youtubeViews.forEach { $0.previousVideo() }
    }

    @objc private func menuNext() {
        youtubeViews.forEach { $0.nextVideo() }
    }

    @objc private func menuTogglePanel() {
        WallpaperSource.savePanelHidden(!WallpaperSource.panelHidden())
        makeWindows()
    }

    @objc private func menuToggleLargestOnly() {
        WallpaperSource.saveVideoOnLargestScreenOnly(!WallpaperSource.videoOnLargestScreenOnly())
        makeWindows()
    }

    @objc private func menuToggleFitMode() {
        WallpaperSource.saveFitMode(WallpaperSource.fitMode() == "cover" ? "contain" : "cover")
        // 次の status 読み取りで新モードのフィットが適用される
        youtubeViews.forEach { $0.invalidateFit() }
    }

    @objc private func menuLogin() {
        loginWindow.show()
    }

    // cookie 等を全消去する。bot 判定が固着した時のリセットにも使える
    @objc private func menuClearWebData() {
        let store = WKWebsiteDataStore.default()
        store.removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date(timeIntervalSince1970: 0)
        ) { [weak self] in
            self?.resetFallback()
            self?.makeWindows()
        }
    }

    @objc private func menuOff() {
        WallpaperSource.clear()
        resetFallback()
        rebuildWindows(fresh: true)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // 音声は 1 画面目の player のみに流す(複数画面で重複再生されるのを防ぐ)
    private func applyVolume(_ volume: Int) {
        for (index, view) in youtubeViews.enumerated() {
            view.setVolume(index == 0 ? volume : 0)
        }
    }

    @objc private func makeWindows() {
        rebuildWindows(fresh: false)
    }

    private func rebuildWindows(fresh: Bool) {
        if fresh {
            // 新しい動画の再生開始: 復元情報と一時停止状態はリセット
            pendingRestore = nil
            userPaused = false
            lastPlaying = false
            lastProgress = 0
        } else if !youtubeViews.isEmpty {
            // ディスプレイ構成変更などの再構築: 位置と停止状態を引き継ぐ
            pendingRestore = (lastProgress, !userPaused)
        }
        windows.forEach { $0.close() }
        youtubeViews.removeAll()
        progressTimer?.invalidate()
        progressTimer = nil
        let youtubeID = WallpaperSource.youtubeID()
        let playlistID = WallpaperSource.youtubePlaylistID()
        let videoIDs = WallpaperSource.playlistVideoIDs()
        let volume = WallpaperSource.volume()
        // フォールバック中は設定を残したままアニメ壁紙を表示する
        let youtubeEnabled = (youtubeID != nil || playlistID != nil || !videoIDs.isEmpty) && !fallbackActive
        let largestOnly = WallpaperSource.videoOnLargestScreenOnly()
        let screens = NSScreen.screens
        let largestScreen = screens.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        windows = screens.compactMap { screen in
            // オプション有効時、小さいモニターにはウィンドウを作らず通常のデスクトップに戻す
            if youtubeEnabled && largestOnly && screen !== largestScreen {
                return nil
            }
            let localFrame = NSRect(origin: .zero, size: screen.frame.size)
            let window = NSWindow(
                contentRect: localFrame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            // close() と ARC の二重解放によるクラッシュを防ぐ
            window.isReleasedWhenClosed = false
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.backgroundColor = .black
            window.isOpaque = true
            window.ignoresMouseEvents = true
            // contentRect は screen 原点からの相対解釈なので、グローバル座標は明示的に合わせる
            window.setFrame(screen.frame, display: true)
            if youtubeEnabled {
                // 音声は 1 画面目の player のみ。全画面に流すと重複して聞こえる
                let view = YouTubeView(
                    frame: localFrame,
                    videoID: youtubeID,
                    playlistID: playlistID,
                    videoIDs: videoIDs,
                    volume: youtubeViews.isEmpty ? volume : 0,
                    startSeconds: WallpaperSource.startSeconds()
                )
                // 再生イベントは音声担当の 1 画面目のみ監視(全画面分監視すると多重カウントになる)
                if youtubeViews.isEmpty {
                    view.onPlayerEvent = { [weak self] event, code in
                        DispatchQueue.main.async {
                            self?.handlePlayerEvent(event, code: code)
                        }
                    }
                }
                youtubeViews.append(view)
                window.contentView = view
            } else {
                window.contentView = WallpaperView(frame: localFrame)
            }
            window.orderFrontRegardless()
            return window
        }
        updateVolumePanel(youtubeEnabled: youtubeEnabled, volume: volume)
        updateProgressTimer(youtubeEnabled: youtubeEnabled)
        if !youtubeEnabled {
            WallpaperSource.clearState()
        }
        // 再構成後に自動一時停止の状態を再適用する
        autoPaused = false
        occlusionChanged()
        updateAutoPauseState()
    }

    private func updateVolumePanel(youtubeEnabled: Bool, volume: Int) {
        guard youtubeEnabled, !WallpaperSource.panelHidden(), let screen = NSScreen.main else {
            volumePanel?.close()
            volumePanel = nil
            return
        }

        let panel = volumePanel ?? VolumePanel(volume: volume)
        if volumePanel == nil {
            // ドラッグ移動を検知して位置を永続化する
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(panelMoved(_:)),
                name: NSWindow.didMoveNotification,
                object: panel
            )
        }
        panel.onChange = { [weak self] volume in
            WallpaperSource.saveVolume(volume)
            self?.applyVolume(volume)
        }
        panel.onSeek = { [weak self] percent in
            self?.youtubeViews.forEach { $0.seek(to: percent) }
        }
        panel.onTogglePlayback = { [weak self] in
            self?.togglePlaybackTracked()
        }
        panel.onPreviousVideo = { [weak self] in
            self?.youtubeViews.forEach { $0.previousVideo() }
        }
        panel.onNextVideo = { [weak self] in
            self?.youtubeViews.forEach { $0.nextVideo() }
        }
        panel.onQualityChange = { [weak self] quality in
            WallpaperSource.saveMaxQuality(quality)
            self?.youtubeViews.forEach { $0.setQuality(quality) }
        }
        let f = screen.visibleFrame
        // visibleFrame は Dock・メニューバーを除いた領域なので、Dock と重ならない
        var origin = NSPoint(x: f.minX + 18, y: f.minY + 14)
        if let saved = WallpaperSource.panelOrigin() {
            // ドラッグで動かした位置を優先(画面外になっていたらデフォルトに戻す)
            let savedFrame = NSRect(origin: saved, size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedFrame) }) {
                origin = saved
            }
        }
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
        volumePanel = panel
    }

    @objc private func panelMoved(_ notification: Notification) {
        guard let panel = notification.object as? VolumePanel else {
            return
        }
        WallpaperSource.savePanelOrigin(panel.frame.origin)
    }

    private func updateProgressTimer(youtubeEnabled: Bool) {
        guard youtubeEnabled else {
            return
        }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            for (index, view) in self.youtubeViews.enumerated() {
                view.readStatus { [weak self, weak view] status in
                    guard let status else {
                        return
                    }
                    // video の実描画位置に合わせてレイヤー変形で全画面フィットさせる
                    view?.applyFit(status: status)
                    guard index == 0 else {
                        return
                    }
                    if let progress = (status["progress"] as? NSNumber)?.doubleValue {
                        self?.volumePanel?.setProgress(progress)
                        self?.lastProgress = progress
                    }
                    let playing = (status["playing"] as? NSNumber)?.boolValue ?? false
                    self?.lastPlaying = playing
                    self?.volumePanel?.updateStatus(
                        playing: playing,
                        currentTime: (status["currentTime"] as? NSNumber)?.doubleValue ?? 0,
                        duration: (status["duration"] as? NSNumber)?.doubleValue ?? 0
                    )
                    // popup が status コマンドで読む実状態(フィット検証用の rect も含む)
                    WallpaperSource.saveState(status)
                }
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
