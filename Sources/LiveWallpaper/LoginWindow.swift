import Cocoa
import WebKit

// YouTube ログイン用の通常ウィンドウ。壁紙の WKWebView と同じ既定 data store を
// 使うため、ここでログインすれば壁紙側も Premium セッションで再生される
final class LoginWindowController: NSObject, WKUIDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    var onClose: (() -> Void)?

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        if let window {
            window.orderFrontRegardless()
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
        // strong プロパティで保持するため close 時の AppKit 側 release と二重解放になる。
        // true のままだと閉じた直後の autoreleasepool drain で SIGSEGV する
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
        window.orderFrontRegardless()
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

// ログイン済みアカウントの YouTube ページを非表示で読み、保存済み再生リストを抽出する。
final class PlaylistProvider: NSObject, WKNavigationDelegate {
    private var window: NSWindow?
    private var webView: WKWebView?
    private var completion: (([(title: String, url: String)]) -> Void)?
    private var attempts = 0
    // 直前の抽出件数。同数が 2 回続いたら「出揃った」とみなす
    private var lastEntryCount = -1
    private var loadGeneration = 0

    func load(completion: @escaping ([(title: String, url: String)]) -> Void) {
        cancelCurrentLoad()
        loadGeneration += 1
        let generation = loadGeneration
        self.completion = completion
        attempts = 0
        lastEntryCount = -1
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 980, height: 720), configuration: config)
        webView.customUserAgent = safariUserAgent
        webView.navigationDelegate = self
        let window = NSWindow(
            contentRect: NSRect(x: -2400, y: -2400, width: 980, height: 720),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        // strong プロパティ保持 + close() を併用するため false 必須(true だと二重解放でクラッシュ)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.contentView = webView
        webView.load(URLRequest(url: URL(string: "https://www.youtube.com/feed/playlists")!))
        window.orderFrontRegardless()
        self.window = window
        self.webView = webView
        scheduleExtract(from: webView, generation: generation, after: 5)
        // 件数安定待ち(最大 8 回 × 1.5 秒 + 初回 5 秒)より少し長いバックストップ
        DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
            guard let self, self.loadGeneration == generation, self.completion != nil else { return }
            self.finish([], generation: generation)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        scheduleExtract(from: webView, generation: loadGeneration, after: 1)
    }

    private func scheduleExtract(from webView: WKWebView, generation: Int, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak webView] in
            guard let self, let webView, self.loadGeneration == generation, self.completion != nil else { return }
            self.extract(from: webView, generation: generation)
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish([], generation: loadGeneration)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish([], generation: loadGeneration)
    }

    private func extract(from webView: WKWebView, generation: Int) {
        guard self.webView === webView, loadGeneration == generation, completion != nil else {
            return
        }
        attempts += 1
        webView.evaluateJavaScript(Self.extractScript) { [weak self] result, _ in
            guard let self else { return }
            guard self.webView === webView, self.loadGeneration == generation, self.completion != nil else {
                return
            }
            guard let rows = result as? [[String: Any]] else {
                if self.attempts >= 8 {
                    self.finish([], generation: generation)
                } else {
                    self.scheduleExtract(from: webView, generation: generation, after: 2)
                }
                return
            }
            let entries = rows.compactMap { row -> (title: String, url: String)? in
                guard let title = row["title"] as? String,
                      let url = row["url"] as? String,
                      !title.isEmpty,
                      !url.isEmpty else {
                    return nil
                }
                return (title, url)
            }
            // 一覧は遅延読み込みされるため、最初の非空結果で確定せず
            // 2 回連続で同じ件数になる(=出揃った)まで抽出を繰り返す
            if !entries.isEmpty && entries.count == self.lastEntryCount {
                self.finish(entries, generation: generation)
            } else if self.attempts >= 8 {
                self.finish(entries, generation: generation)
            } else {
                self.lastEntryCount = entries.count
                self.scheduleExtract(from: webView, generation: generation, after: 1.5)
            }
        }
    }

    private func finish(_ entries: [(title: String, url: String)], generation: Int) {
        guard loadGeneration == generation, let completion else {
            return
        }
        cancelCurrentLoad()
        completion(entries)
    }

    private func cancelCurrentLoad() {
        let currentWebView = webView
        webView = nil
        currentWebView?.stopLoading()
        currentWebView?.navigationDelegate = nil
        let currentWindow = window
        window = nil
        currentWindow?.contentView = nil
        currentWindow?.orderOut(nil)
        currentWindow?.close()
        completion = nil
    }

    private static let extractScript = """
        (function() {
          window.scrollTo(0, Math.max(document.body.scrollHeight, document.documentElement.scrollHeight));
          const byList = new Map();
          const clean = function(value) {
            return (value || '').replace(/\\s+/g, ' ').trim();
          };
          const textOf = function(value) {
            if (!value) return '';
            if (typeof value === 'string') return clean(value);
            if (value.simpleText) return clean(value.simpleText);
            if (Array.isArray(value.runs)) return clean(value.runs.map(function(run) { return run.text || ''; }).join(''));
            return '';
          };
          const add = function(listID, title) {
            if (!listID || byList.has(listID)) return;
            title = clean(title) || listID;
            if (title.length > 72) title = title.slice(0, 69) + '...';
            byList.set(listID, {
              title: title,
              url: 'https://www.youtube.com/playlist?list=' + encodeURIComponent(listID)
            });
          };
          const walk = function(value, depth) {
            if (!value || depth > 20) return;
            if (Array.isArray(value)) {
              value.forEach(function(item) { walk(item, depth + 1); });
              return;
            }
            if (typeof value !== 'object') return;
            if (value.playlistId) {
              add(value.playlistId, textOf(value.title) || textOf(value.header && value.header.title));
            }
            // 新 UI (lockupViewModel): contentType が PLAYLIST の contentId が再生リスト ID
            if (value.contentId && typeof value.contentType === 'string' && value.contentType.indexOf('PLAYLIST') >= 0) {
              let lockupTitle = '';
              try {
                lockupTitle = value.metadata.lockupMetadataViewModel.title.content || '';
              } catch (e) {}
              add(value.contentId, lockupTitle);
            }
            Object.keys(value).forEach(function(key) { walk(value[key], depth + 1); });
          };
          walk(window.ytInitialData, 0);
          document.querySelectorAll('a[href*="list="]').forEach(function(anchor) {
            let url;
            let listID;
            try {
              url = new URL(anchor.href, location.origin);
              listID = url.searchParams.get('list');
            } catch (e) {
              return;
            }
            if (!listID || byList.has(listID)) return;
            // 旧 UI (ytd-*-renderer) と新 UI (yt-lockup-view-model) の両方をカードとして扱う
            const card = anchor.closest('ytd-rich-item-renderer,ytd-grid-playlist-renderer,ytd-playlist-video-renderer,ytd-compact-playlist-renderer,ytd-item-section-renderer,ytd-shelf-renderer,yt-lockup-view-model') || anchor;
            let title = clean(anchor.getAttribute('title')) || clean(anchor.textContent);
            const heading = card.querySelector('#video-title,#playlist-title,h3,a[title],yt-formatted-string,.yt-core-attributed-string');
            title = clean(heading && (heading.getAttribute('title') || heading.textContent)) || title || listID;
            add(listID, title);
          });
          return Array.from(byList.values()).slice(0, 50);
        })();
        """
}
