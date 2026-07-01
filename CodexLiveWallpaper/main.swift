import Cocoa
import WebKit

enum WallpaperSource {
    static let configURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/youtube-url.txt")
    static let volumeURL = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/CodexLiveWallpaper/volume.txt")

    static func youtubeID() -> String? {
        let args = ProcessInfo.processInfo.arguments.dropFirst()
        let raw = args.first ?? (try? String(contentsOf: configURL, encoding: .utf8))
        guard let raw, let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return youtubeID(from: url)
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
    init(frame: NSRect, videoID: String, volume: Int) {
        let config = WKWebViewConfiguration()
        config.allowsAirPlayForMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        super.init(frame: frame, configuration: config)
        wantsLayer = true
        customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        setValue(false, forKey: "drawsBackground")
        loadHTMLString(Self.html(videoID: videoID, volume: volume), baseURL: URL(string: "https://www.youtube-nocookie.com"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    func setVolume(_ volume: Int) {
        evaluateJavaScript("setWallpaperVolume(\(min(100, max(0, volume))))")
    }

    private static func html(videoID: String, volume: Int) -> String {
        """
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
            function onYouTubeIframeAPIReady() {
              player = new YT.Player('player', {
                videoId: '\(videoID)',
                host: 'https://www.youtube-nocookie.com',
                playerVars: {
                  autoplay: 1,
                  mute: 1,
                  controls: 0,
                  loop: 1,
                  playlist: '\(videoID)',
                  playsinline: 1,
                  modestbranding: 1,
                  rel: 0,
                  origin: 'https://www.youtube-nocookie.com'
                },
                events: {
                  onReady: function(event) {
                    event.target.mute();
                    event.target.playVideo();
                    setWallpaperVolume(pendingVolume);
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
          </script>
        </body>
        </html>
        """
    }
}

final class VolumePanel: NSPanel {
    var onChange: ((Int) -> Void)?
    private let valueLabel = NSTextField(labelWithString: "0")

    init(volume: Int) {
        let frame = NSRect(x: 0, y: 0, width: 260, height: 58)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let root = NSVisualEffectView(frame: frame)
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.wantsLayer = true
        root.layer?.cornerRadius = 14

        let title = NSTextField(labelWithString: "YouTube 音量")
        title.frame = NSRect(x: 14, y: 32, width: 110, height: 18)
        title.textColor = .white
        title.font = .systemFont(ofSize: 12, weight: .medium)
        root.addSubview(title)

        valueLabel.frame = NSRect(x: 216, y: 32, width: 32, height: 18)
        valueLabel.alignment = .right
        valueLabel.textColor = .white
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        root.addSubview(valueLabel)

        let slider = NSSlider(value: Double(volume), minValue: 0, maxValue: 100, target: self, action: #selector(changed(_:)))
        slider.frame = NSRect(x: 14, y: 10, width: 232, height: 22)
        slider.isContinuous = true
        root.addSubview(slider)

        contentView = root
        changed(slider)
    }

    @objc private func changed(_ sender: NSSlider) {
        let volume = sender.integerValue
        valueLabel.stringValue = "\(volume)"
        onChange?(volume)
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        makeWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(makeWindows),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func makeWindows() {
        windows.forEach { $0.close() }
        youtubeViews.removeAll()
        let youtubeID = WallpaperSource.youtubeID()
        let volume = WallpaperSource.volume()
        windows = NSScreen.screens.map { screen in
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.backgroundColor = .black
            window.isOpaque = true
            window.ignoresMouseEvents = true
            if let youtubeID {
                let view = YouTubeView(frame: screen.frame, videoID: youtubeID, volume: volume)
                youtubeViews.append(view)
                window.contentView = view
            } else {
                window.contentView = WallpaperView(frame: screen.frame)
            }
            window.orderFrontRegardless()
            return window
        }
        updateVolumePanel(youtubeEnabled: youtubeID != nil, volume: volume)
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
            self?.youtubeViews.forEach { $0.setVolume(volume) }
        }
        let f = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 18, y: f.minY + 18))
        panel.orderFrontRegardless()
        volumePanel = panel
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
