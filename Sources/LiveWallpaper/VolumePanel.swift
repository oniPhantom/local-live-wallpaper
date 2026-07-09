import Cocoa
import LiveWallpaperCore

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
    var onRestoreDesktop: (() -> Void)?
    var onPlayURL: ((String) -> Void)?
    var onPlaylistSelected: ((String) -> Void)?
    var onRefreshPlaylists: (() -> Void)?
    var onLogin: (() -> Void)?

    // 表示名 → vq 値。パネルのポップアップで使う
    static let qualityOptions: [(title: String, value: String)] = [
        ("自動", "auto"),
        ("2160p", "hd2160"),
        ("1440p", "hd1440"),
        ("1080p", "hd1080"),
        ("720p", "hd720"),
        ("480p", "large"),
    ]

    private let expandedSize = NSSize(width: 360, height: 230)
    private let collapsedSize = NSSize(width: 360, height: 38)
    private let root: NSVisualEffectView
    private let valueLabel = NSTextField(labelWithString: "0")
    private let progressBar = ProgressBar(frame: NSRect(x: 16, y: 14, width: 328, height: 14))
    private let collapseButton = NSButton(frame: .zero)
    private let playButton = NSButton(frame: .zero)
    private let urlField = NSTextField(frame: .zero)
    private let playlistPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshPlaylistsButton = NSButton(title: "更新", target: nil, action: nil)
    private let loginButton = NSButton(title: "ログイン", target: nil, action: nil)
    private let qualityPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let currentTimeLabel = NSTextField(labelWithString: "--:--")
    private let durationLabel = NSTextField(labelWithString: "--:--")
    private let stateLabel = NSTextField(labelWithString: "")
    private var playlistURLs: [String] = []
    // ローカル動画再生中は再生リスト・画質が意味を持たないため無効化する
    private var localSource = false
    private var videoControls: [NSControl] = []
    private var isPlayingIcon = false
    private var collapsibleViews: [NSView] = []
    private var isCollapsed = false

    override var canBecomeKey: Bool {
        true
    }

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
        let logo = NSImageView(frame: NSRect(x: 16, y: 198, width: 18, height: 18))
        logo.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        logo.contentTintColor = NSColor(calibratedRed: 1.0, green: 0.18, blue: 0.13, alpha: 1)
        root.addSubview(logo)
        collapsibleViews.append(logo)

        // 商標配慮で製品名は "YouTube" を含めない
        let title = NSTextField(labelWithString: "Live Wallpaper")
        title.frame = NSRect(x: 39, y: 199, width: 160, height: 16)
        title.textColor = NSColor(calibratedWhite: 1, alpha: 0.92)
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        root.addSubview(title)
        collapsibleViews.append(title)

        qualityPopUp.frame = NSRect(x: 244, y: 195, width: 80, height: 22)
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
        collapseButton.frame = NSRect(x: 326, y: 196, width: 20, height: 20)
        root.addSubview(collapseButton)

        urlField.frame = NSRect(x: 16, y: 160, width: 272, height: 24)
        urlField.placeholderString = "YouTube URL / 動画ファイルパス"
        urlField.font = .systemFont(ofSize: 11)
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.target = self
        urlField.action = #selector(playURLTapped)
        root.addSubview(urlField)
        collapsibleViews.append(urlField)

        let playURLButton = NSButton(title: "再生", target: self, action: #selector(playURLTapped))
        playURLButton.frame = NSRect(x: 296, y: 159, width: 48, height: 26)
        playURLButton.controlSize = .small
        playURLButton.bezelStyle = .rounded
        root.addSubview(playURLButton)
        collapsibleViews.append(playURLButton)

        playlistPopUp.frame = NSRect(x: 16, y: 126, width: 190, height: 26)
        playlistPopUp.controlSize = .small
        playlistPopUp.font = .systemFont(ofSize: 11)
        playlistPopUp.addItem(withTitle: "再生リストを読み込み中")
        playlistPopUp.target = self
        playlistPopUp.action = #selector(playlistSelected(_:))
        root.addSubview(playlistPopUp)
        collapsibleViews.append(playlistPopUp)

        refreshPlaylistsButton.target = self
        refreshPlaylistsButton.action = #selector(refreshPlaylistsTapped)
        refreshPlaylistsButton.frame = NSRect(x: 210, y: 125, width: 48, height: 26)
        refreshPlaylistsButton.controlSize = .small
        refreshPlaylistsButton.bezelStyle = .rounded
        root.addSubview(refreshPlaylistsButton)
        collapsibleViews.append(refreshPlaylistsButton)

        // ログイン状態に応じてタイトルが変わるため「ログイン済み」が収まる幅にしている
        loginButton.frame = NSRect(x: 262, y: 125, width: 82, height: 26)
        loginButton.target = self
        loginButton.action = #selector(loginTapped)
        loginButton.controlSize = .small
        loginButton.bezelStyle = .rounded
        root.addSubview(loginButton)
        collapsibleViews.append(loginButton)

        // トランスポート(中央寄せ)
        let previousButton = makeIconButton(symbol: "backward.fill", size: 15, action: #selector(previousTapped))
        previousButton.frame = NSRect(x: 122, y: 86, width: 36, height: 30)
        root.addSubview(previousButton)
        collapsibleViews.append(previousButton)
        videoControls.append(previousButton)

        configureIconButton(playButton, symbol: "play.fill", size: 19, action: #selector(playTapped))
        playButton.frame = NSRect(x: 162, y: 84, width: 36, height: 34)
        root.addSubview(playButton)
        collapsibleViews.append(playButton)
        videoControls.append(playButton)

        let nextButton = makeIconButton(symbol: "forward.fill", size: 15, action: #selector(nextTapped))
        nextButton.frame = NSRect(x: 202, y: 86, width: 36, height: 30)
        root.addSubview(nextButton)
        collapsibleViews.append(nextButton)
        videoControls.append(nextButton)

        let restoreButton = makeIconButton(symbol: "xmark.circle.fill", size: 17, action: #selector(restoreDesktopTapped))
        restoreButton.toolTip = "YouTube 再生を止めて通常壁紙に戻す"
        restoreButton.contentTintColor = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.32, alpha: 0.9)
        restoreButton.frame = NSRect(x: 254, y: 86, width: 36, height: 30)
        root.addSubview(restoreButton)
        collapsibleViews.append(restoreButton)
        videoControls.append(restoreButton)

        // 音量
        let speaker = NSImageView(frame: NSRect(x: 16, y: 60, width: 16, height: 16))
        speaker.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        speaker.contentTintColor = NSColor(calibratedWhite: 1, alpha: 0.6)
        root.addSubview(speaker)
        collapsibleViews.append(speaker)

        let slider = NSSlider(value: Double(volume), minValue: 0, maxValue: 100, target: self, action: #selector(changed(_:)))
        slider.frame = NSRect(x: 38, y: 58, width: 266, height: 20)
        slider.controlSize = .small
        slider.isContinuous = true
        root.addSubview(slider)
        collapsibleViews.append(slider)

        valueLabel.frame = NSRect(x: 310, y: 60, width: 34, height: 16)
        valueLabel.alignment = .right
        valueLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.6)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        root.addSubview(valueLabel)
        collapsibleViews.append(valueLabel)

        // 時間・再生状態の行
        currentTimeLabel.frame = NSRect(x: 16, y: 38, width: 94, height: 13)
        currentTimeLabel.alignment = .left
        currentTimeLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.75)
        currentTimeLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        root.addSubview(currentTimeLabel)
        collapsibleViews.append(currentTimeLabel)

        stateLabel.frame = NSRect(x: 110, y: 38, width: 140, height: 13)
        stateLabel.alignment = .center
        stateLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.45)
        stateLabel.font = .systemFont(ofSize: 9, weight: .medium)
        root.addSubview(stateLabel)
        collapsibleViews.append(stateLabel)

        durationLabel.frame = NSRect(x: 250, y: 38, width: 94, height: 13)
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
        setSourceURL(WallpaperSource.currentURLString())
        setPlaybackAvailable(false)
        setPlaylists([], loading: true)
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
        setPlaybackAvailable(true)
        stateLabel.stringValue = playing ? "再生中" : "一時停止"
        stateLabel.textColor = playing
            ? NSColor(calibratedRed: 0.35, green: 0.85, blue: 0.45, alpha: 0.9)
            : NSColor(calibratedWhite: 1, alpha: 0.45)
        currentTimeLabel.stringValue = Self.formatTime(currentTime)
        // duration 0 はライブ配信や未取得
        durationLabel.stringValue = duration > 0 ? Self.formatTime(duration) : "--:--"
    }

    func setSourceURL(_ url: String) {
        urlField.stringValue = url
    }

    func setPlaylists(_ entries: [(title: String, url: String)], loading: Bool = false) {
        playlistURLs = entries.map(\.url)
        playlistPopUp.removeAllItems()
        if loading {
            playlistPopUp.addItem(withTitle: "再生リストを読み込み中")
            playlistPopUp.isEnabled = false
        } else if entries.isEmpty {
            playlistPopUp.addItem(withTitle: "再生リストなし / 未ログイン")
            playlistPopUp.isEnabled = false
        } else {
            entries.forEach { playlistPopUp.addItem(withTitle: $0.title) }
            playlistPopUp.isEnabled = !localSource
        }
    }

    // ローカル動画再生中は YouTube 固有の操作(再生リスト・画質)を無効化する
    func setLocalSourceMode(_ local: Bool) {
        localSource = local
        qualityPopUp.isEnabled = !local
        refreshPlaylistsButton.isEnabled = !local
        if local {
            playlistPopUp.isEnabled = false
        } else if !playlistURLs.isEmpty {
            playlistPopUp.isEnabled = true
        }
    }

    // ログイン状態をログインボタンへ反映する(ログイン済みでもクリックで再ログインできる)
    func setLoginStatus(loggedIn: Bool) {
        loginButton.title = loggedIn ? "ログイン済み" : "ログイン"
        loginButton.toolTip = loggedIn
            ? "YouTube にログイン済み(クリックで再ログイン)"
            : "YouTube にログインすると Premium セッションで再生できます"
    }

    func setPlaybackAvailable(_ available: Bool) {
        videoControls.forEach { $0.isEnabled = available }
        if !available {
            setProgress(0)
            currentTimeLabel.stringValue = "--:--"
            durationLabel.stringValue = "--:--"
            stateLabel.stringValue = "待機中"
            stateLabel.textColor = NSColor(calibratedWhite: 1, alpha: 0.45)
            if isPlayingIcon {
                isPlayingIcon = false
                configureIconButton(playButton, symbol: "play.fill", size: 19, action: #selector(playTapped))
            }
        }
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

    @objc private func restoreDesktopTapped() {
        onRestoreDesktop?()
    }

    @objc private func playURLTapped() {
        onPlayURL?(urlField.stringValue)
    }

    @objc private func playlistSelected(_ sender: NSPopUpButton) {
        let index = sender.indexOfSelectedItem
        guard playlistURLs.indices.contains(index) else {
            return
        }
        onPlaylistSelected?(playlistURLs[index])
    }

    @objc private func refreshPlaylistsTapped() {
        setPlaylists([], loading: true)
        onRefreshPlaylists?()
    }

    @objc private func loginTapped() {
        onLogin?()
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
            ? NSRect(x: 326, y: 9, width: 20, height: 20)
            : NSRect(x: 326, y: 196, width: 20, height: 20)
        progressBar.frame = isCollapsed
            ? NSRect(x: 16, y: 12, width: 302, height: 14)
            : NSRect(x: 16, y: 14, width: 328, height: 14)

        let newSize = isCollapsed ? collapsedSize : expandedSize
        var frame = frame
        frame.size = newSize
        setFrame(frame, display: true, animate: true)
        root.frame = NSRect(origin: .zero, size: newSize)
    }
}
