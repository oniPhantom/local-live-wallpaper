import Cocoa
import LiveWallpaperCore
import WebKit

// 壁紙・ログインウィンドウ共通の Safari 相当 UA(WebView 判定によるログイン拒否を避ける)
let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"

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
    // event: "playing" | "error" | "stalled" | "no-player-api", code: YT エラーコード(error 時のみ)
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
        if let url = WatchURL.build(videoID: videoID, playlistID: playlistID, videoIDs: videoIDs, startSeconds: startSeconds) {
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
            // 再構築時に「同じ動画から再開」するため、再生中の動画 ID も返す
            try {
              var p = moviePlayer();
              if (p && p.getVideoData) {
                var d = p.getVideoData();
                if (d && d.video_id) status.videoId = String(d.video_id);
              }
            } catch (e) {}
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

          // movie_player API の健全性チェック: 一定時間内に setVolume 等が取得できなければ
          // DOM 構造の変更や読み込み失敗とみなしてネイティブへ明示的に通知する
          window.setTimeout(function() {
            var p = moviePlayer();
            if (!p || typeof p.setVolume !== 'function') {
              notifyNative({event: 'no-player-api', code: 0});
            }
          }, 15000);

          // 一定時間再生が始まらなければ失敗として通知
          window.setTimeout(function() {
            if (!everPlayed) notifyNative({event: 'stalled', code: 0});
          }, 45000);
        })();
        """
    }
}
