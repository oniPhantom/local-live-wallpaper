import Cocoa
import WebKit

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

final class YouTubeView: WKWebView {
    init(frame: NSRect, videoID: String?, playlistID: String?, videoIDs: [String], volume: Int) {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        super.init(frame: frame, configuration: config)
        wantsLayer = true
        customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        setValue(false, forKey: "drawsBackground")
        loadHTMLString(
            Self.html(videoID: videoID, playlistID: playlistID, videoIDs: videoIDs, volume: volume),
            baseURL: URL(string: "https://www.youtube-nocookie.com")
        )
    }

    required init?(coder: NSCoder) {
        nil
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

    func readProgress(_ completion: @escaping (Double?) -> Void) {
        evaluateJavaScript("wallpaperVideoProgress()") { result, _ in
            guard let progress = result as? Double else {
                completion(nil)
                return
            }
            completion(progress)
        }
    }

    private static func html(videoID: String?, playlistID: String?, videoIDs: [String], volume: Int) -> String {
        let explicitIDs = videoIDs.compactMap(WallpaperSource.sanitizeID)
        let videoIDLine = (videoID ?? explicitIDs.first).map { "                videoId: '\($0)'," } ?? ""
        let playlistVars = playlistID.map {
            """
                  listType: 'playlist',
                  list: '\($0)',
            """
        } ?? ""
        let playlistLoad: String
        if explicitIDs.count > 1 {
            let jsArray = explicitIDs.map { "'\($0)'" }.joined(separator: ", ")
            playlistLoad = """
                    event.target.loadPlaylist([\(jsArray)]);
            """
        } else {
            playlistLoad = playlistID.map {
                """
                        event.target.loadPlaylist({
                          listType: 'playlist',
                          list: '\($0)'
                        });
                """
            } ?? ""
        }
        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html, body, #player, iframe {
            background: #000;
            border: 0;
            height: 100%;
            margin: 0;
            overflow: hidden;
            padding: 0;
            width: 100%;
          }
          iframe {
            height: max(100vh, 56.25vw);
            left: 50%;
            pointer-events: none;
            position: fixed;
            top: 50%;
            transform: translate(-50%, -50%);
            width: max(100vw, 177.78vh);
          }
        </style>
        </head>
        <body>
          <div id="player"></div>
          <script src="https://www.youtube.com/iframe_api"></script>
          <script>
            var player;
            var pendingVolume = \(min(100, max(0, volume)));
            function disableCaptions() {
              if (!player) return;
              if (player.setOption) {
                player.setOption('captions', 'track', {});
                player.setOption('cc', 'track', {});
              }
              if (player.unloadModule) {
                player.unloadModule('captions');
              }
            }
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
        \(videoIDLine)
                host: 'https://www.youtube-nocookie.com',
                playerVars: {
                  autoplay: 1,
                  mute: 1,
                  controls: 0,
                  cc_load_policy: 0,
                  iv_load_policy: 3,
                  cc_lang_pref: '',
        \(playlistVars)
                  playsinline: 1,
                  modestbranding: 1,
                  rel: 0,
                  origin: 'https://www.youtube-nocookie.com'
                },
                events: {
                  onReady: function(event) {
        \(playlistLoad)
                    event.target.mute();
                    disableCaptions();
                    window.setTimeout(disableCaptions, 500);
                    window.setTimeout(disableCaptions, 1500);
                    event.target.playVideo();
                    setWallpaperVolume(pendingVolume);
                  },
                  onStateChange: function() {
                    disableCaptions();
                    window.setTimeout(disableCaptions, 500);
                  }
                }
              });
            }
            function setWallpaperVolume(volume) {
              pendingVolume = volume;
              if (!player || !player.setVolume) return;
              player.setVolume(volume);
              if (volume > 0) {
                player.unMute();
                player.playVideo();
              } else {
                player.mute();
              }
            }
            function toggleWallpaperPlayback() {
              if (!player || !player.getPlayerState) return;
              var state = player.getPlayerState();
              if (state === YT.PlayerState.PLAYING || state === YT.PlayerState.BUFFERING) {
                player.pauseVideo();
              } else {
                player.playVideo();
              }
            }
            function previousWallpaperVideo() {
              if (!player || !player.previousVideo || !player.getPlaylist) return;
              if (!player.getPlaylist() || player.getPlaylist().length <= 1) return;
              player.previousVideo();
            }
            function nextWallpaperVideo() {
              if (!player || !player.nextVideo || !player.getPlaylist) return;
              if (!player.getPlaylist() || player.getPlaylist().length <= 1) return;
              player.nextVideo();
            }
            function seekWallpaperVideo(percent) {
              if (!player || !player.getDuration || !player.seekTo) return;
              var duration = player.getDuration();
              if (!duration || duration <= 0) return;
              player.seekTo(duration * percent, true);
              player.playVideo();
            }
            function wallpaperVideoProgress() {
              if (!player || !player.getDuration || !player.getCurrentTime) return 0;
              var duration = player.getDuration();
              if (!duration || duration <= 0) return 0;
              return player.getCurrentTime() / duration;
            }
            function setWallpaperSubtitles(enabled) {
              if (!player) return;
              if (enabled && player.loadModule) {
                player.loadModule('captions');
              } else if (!enabled && player.unloadModule) {
                player.unloadModule('captions');
              }
            }
          </script>
        </body>
        </html>
        """
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
    private let expandedSize = NSSize(width: 292, height: 126)
    private let collapsedSize = NSSize(width: 292, height: 28)
    private let root: NSVisualEffectView
    private let valueLabel = NSTextField(labelWithString: "0")
    private let progressBar = ProgressBar(frame: NSRect(x: 14, y: 8, width: 264, height: 22))
    private let collapseButton: NSButton
    private var collapsibleViews: [NSView] = []
    private var isCollapsed = false

    init(volume: Int) {
        let frame = NSRect(origin: .zero, size: expandedSize)
        root = NSVisualEffectView(frame: frame)
        collapseButton = NSButton(title: "−", target: nil, action: nil)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 14

        let title = NSTextField(labelWithString: "YouTube")
        title.frame = NSRect(x: 14, y: 86, width: 110, height: 18)
        title.textColor = .white
        title.font = .systemFont(ofSize: 12, weight: .medium)
        root.addSubview(title)
        collapsibleViews.append(title)

        valueLabel.frame = NSRect(x: 246, y: 86, width: 32, height: 18)
        valueLabel.alignment = .right
        valueLabel.textColor = .white
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        root.addSubview(valueLabel)
        collapsibleViews.append(valueLabel)

        configureButton(collapseButton, action: #selector(toggleCollapsed))
        collapseButton.frame = NSRect(x: 248, y: 58, width: 30, height: 24)
        root.addSubview(collapseButton)

        let previousButton = makeButton(title: "⏮", action: #selector(previousTapped))
        previousButton.frame = NSRect(x: 14, y: 58, width: 44, height: 24)
        root.addSubview(previousButton)
        collapsibleViews.append(previousButton)

        let playButton = makeButton(title: "⏯", action: #selector(playTapped))
        playButton.frame = NSRect(x: 64, y: 58, width: 44, height: 24)
        root.addSubview(playButton)
        collapsibleViews.append(playButton)

        let nextButton = makeButton(title: "⏭", action: #selector(nextTapped))
        nextButton.frame = NSRect(x: 114, y: 58, width: 44, height: 24)
        root.addSubview(nextButton)
        collapsibleViews.append(nextButton)

        let slider = NSSlider(value: Double(volume), minValue: 0, maxValue: 100, target: self, action: #selector(changed(_:)))
        slider.frame = NSRect(x: 14, y: 32, width: 264, height: 22)
        slider.isContinuous = true
        root.addSubview(slider)
        collapsibleViews.append(slider)

        let progressLabel = NSTextField(labelWithString: "Seek")
        progressLabel.frame = NSRect(x: 14, y: 104, width: 48, height: 16)
        progressLabel.textColor = .white.withAlphaComponent(0.85)
        progressLabel.font = .systemFont(ofSize: 10, weight: .medium)
        root.addSubview(progressLabel)
        collapsibleViews.append(progressLabel)

        progressBar.onSeek = { [weak self] percent in
            self?.onSeek?(percent)
        }
        root.addSubview(progressBar)

        contentView = root
        changed(slider)
    }

    private func makeButton(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        configureButton(button, action: action)
        return button
    }

    private func configureButton(_ button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.isBordered = true
        button.font = .systemFont(ofSize: 13, weight: .medium)
    }

    @objc private func changed(_ sender: NSSlider) {
        let volume = sender.integerValue
        valueLabel.stringValue = "\(volume)"
        onChange?(volume)
    }

    func setProgress(_ progress: Double) {
        progressBar.setProgress(progress)
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

    @objc private func toggleCollapsed() {
        isCollapsed.toggle()
        collapsibleViews.forEach { $0.isHidden = isCollapsed }
        collapseButton.title = isCollapsed ? "+" : "−"
        collapseButton.frame = isCollapsed
            ? NSRect(x: 250, y: 3, width: 28, height: 22)
            : NSRect(x: 248, y: 58, width: 30, height: 24)
        progressBar.frame = isCollapsed
            ? NSRect(x: 14, y: 5, width: 224, height: 18)
            : NSRect(x: 14, y: 8, width: 264, height: 22)

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [NSWindow] = []
    private var youtubeViews: [YouTubeView] = []
    private var volumePanel: VolumePanel?
    private var progressTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(makeWindows),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleRemoteCommand(_:)),
            name: Notification.Name("com.codex.livewallpaper.command"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
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
            makeWindows()
        case "off":
            makeWindows()
        case "pause", "toggle":
            youtubeViews.forEach { $0.togglePlayback() }
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
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    // 音声は 1 画面目の player のみに流す(複数画面で重複再生されるのを防ぐ)
    private func applyVolume(_ volume: Int) {
        for (index, view) in youtubeViews.enumerated() {
            view.setVolume(index == 0 ? volume : 0)
        }
    }

    @objc private func makeWindows() {
        windows.forEach { $0.close() }
        youtubeViews.removeAll()
        progressTimer?.invalidate()
        progressTimer = nil
        let youtubeID = WallpaperSource.youtubeID()
        let playlistID = WallpaperSource.youtubePlaylistID()
        let videoIDs = WallpaperSource.playlistVideoIDs()
        let volume = WallpaperSource.volume()
        let youtubeEnabled = youtubeID != nil || playlistID != nil || !videoIDs.isEmpty
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
                    volume: youtubeViews.isEmpty ? volume : 0
                )
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
    }

    private func updateVolumePanel(youtubeEnabled: Bool, volume: Int) {
        guard youtubeEnabled, let screen = NSScreen.main else {
            volumePanel?.close()
            volumePanel = nil
            return
        }

        let panel = volumePanel ?? VolumePanel(volume: volume)
        panel.onChange = { [weak self] volume in
            WallpaperSource.saveVolume(volume)
            self?.applyVolume(volume)
        }
        panel.onSeek = { [weak self] percent in
            self?.youtubeViews.forEach { $0.seek(to: percent) }
        }
        panel.onTogglePlayback = { [weak self] in
            self?.youtubeViews.forEach { $0.togglePlayback() }
        }
        panel.onPreviousVideo = { [weak self] in
            self?.youtubeViews.forEach { $0.previousVideo() }
        }
        panel.onNextVideo = { [weak self] in
            self?.youtubeViews.forEach { $0.nextVideo() }
        }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.minX + 18, y: screen.frame.minY + 1))
        panel.orderFrontRegardless()
        volumePanel = panel
    }

    private func updateProgressTimer(youtubeEnabled: Bool) {
        guard youtubeEnabled else {
            return
        }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let view = self.youtubeViews.first else {
                return
            }
            view.readProgress { [weak self] progress in
                guard let progress else {
                    return
                }
                self?.volumePanel?.setProgress(progress)
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
