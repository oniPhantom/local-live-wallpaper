import Cocoa
import LiveWallpaperCore

private let youtubeAccentColor = NSColor(calibratedRed: 1.0, green: 0.15, blue: 0.12, alpha: 1)

final class ProgressBar: NSView {
    var onSeek: ((Double) -> Void)?
    var isEnabled = true {
        didSet {
            alphaValue = isEnabled ? 1 : 0.45
        }
    }

    private var progress: Double = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityLabel("再生位置")
        setAccessibilityRole(.slider)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 0, dy: 6)
        NSColor(calibratedWhite: 1, alpha: 0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()

        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height)
        youtubeAccentColor.withAlphaComponent(0.98).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4).fill()

        let knobX = track.minX + track.width * progress
        NSColor(calibratedWhite: 1, alpha: 0.96).setFill()
        NSBezierPath(ovalIn: NSRect(x: knobX - 5, y: track.midY - 5, width: 10, height: 10)).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        seek(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEnabled else { return }
        seek(with: event)
    }

    func setProgress(_ progress: Double) {
        self.progress = min(1, max(0, progress))
        setAccessibilityValue(self.progress)
        needsDisplay = true
    }

    private func seek(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let percent = Double(min(bounds.maxX, max(bounds.minX, x)) / bounds.width)
        setProgress(percent)
        onSeek?(percent)
    }
}

private final class ResizeHandleView: NSView {
    var onDraggingChanged: ((Bool) -> Void)?
    private var startFrame: NSRect?
    private var startPoint: NSPoint?
    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        toolTip = "ドラッグしてパネルサイズを変更"
        setAccessibilityElement(true)
        setAccessibilityRole(.handle)
        setAccessibilityLabel("パネルサイズを変更")
        setAccessibilityHelp("右下のハンドルをドラッグして幅と高さを変更")

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        let grip = NSBezierPath()
        [
            NSRect(x: 5, y: 7, width: 2, height: 2),
            NSRect(x: 9, y: 7, width: 2, height: 2),
            NSRect(x: 13, y: 7, width: 2, height: 2),
            NSRect(x: 9, y: 11, width: 2, height: 2),
            NSRect(x: 13, y: 11, width: 2, height: 2),
            NSRect(x: 13, y: 15, width: 2, height: 2),
        ].forEach { grip.appendOval(in: $0) }
        (isHovered ? youtubeAccentColor.withAlphaComponent(0.9) : NSColor(calibratedWhite: 1, alpha: 0.38)).setFill()
        grip.fill()
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onDraggingChanged?(true)
        startFrame = window.frame
        startPoint = window.convertPoint(toScreen: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let startFrame, let startPoint else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let width = min(window.contentMaxSize.width, max(window.contentMinSize.width, startFrame.width + point.x - startPoint.x))
        let height = min(window.contentMaxSize.height, max(window.contentMinSize.height, startFrame.height - point.y + startPoint.y))
        let frame = NSRect(x: startFrame.minX, y: startFrame.maxY - height, width: width, height: height)
        window.setFrame(frame, display: true)
    }

    override func mouseUp(with event: NSEvent) {
        startFrame = nil
        startPoint = nil
        onDraggingChanged?(false)
    }
}

final class VolumePanel: NSPanel, NSWindowDelegate {
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

    static let qualityOptions: [(title: String, value: String)] = [
        ("自動", "auto"),
        ("2160p", "hd2160"),
        ("1440p", "hd1440"),
        ("1080p", "hd1080"),
        ("720p", "hd720"),
        ("480p", "large"),
    ]

    private static let defaultExpandedSize = NSSize(width: 360, height: 270)
    private static let minimumExpandedSize = NSSize(width: 320, height: 270)
    private static let maximumExpandedSize = NSSize(width: 640, height: 420)
    private static let collapsedHeight: CGFloat = 56
    private let root: NSVisualEffectView
    private let expandedStack = NSStackView()
    private let compactStack = NSStackView()
    private let resizeHandle = ResizeHandleView(frame: .zero)
    private var expandedStackWidthConstraint: NSLayoutConstraint!
    private var expandedStackBottomConstraint: NSLayoutConstraint!
    private var compactStackWidthConstraint: NSLayoutConstraint!
    private let expandedProgressBar = ProgressBar(frame: .zero)
    private let compactProgressBar = ProgressBar(frame: .zero)
    private let playButton = NSButton(frame: .zero)
    private let compactPlayButton = NSButton(frame: .zero)
    private let urlField = NSTextField(frame: .zero)
    private let playlistPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshPlaylistsButton = NSButton(frame: .zero)
    private let loginButton = NSButton(title: "ログイン", target: nil, action: nil)
    private let qualityPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let currentTimeLabel = NSTextField(labelWithString: "--:--")
    private let compactCurrentTimeLabel = NSTextField(labelWithString: "--:--")
    private let durationLabel = NSTextField(labelWithString: "--:--")
    private let compactDurationLabel = NSTextField(labelWithString: "--:--")
    private let stateLabel = NSTextField(labelWithString: "待機中")
    private let valueLabel = NSTextField(labelWithString: "0")
    private let sourceTypeLabel = NSTextField(labelWithString: "YouTube")
    private var playlistURLs: [String] = []
    private var localSource = false
    private var videoControls: [NSControl] = []
    private var isPlayingIcon = false
    private var isCollapsed = false
    private(set) var isResizing = false
    private var expandedUserSize = defaultExpandedSize

    private static let accentColor = youtubeAccentColor
    private static let playingColor = NSColor(calibratedRed: 0.44, green: 0.84, blue: 0.63, alpha: 1)
    private static let dangerColor = NSColor(calibratedRed: 1.0, green: 0.40, blue: 0.36, alpha: 0.95)
    private static let primaryTextColor = NSColor(calibratedWhite: 1, alpha: 0.94)
    private static let secondaryTextColor = NSColor(calibratedWhite: 1, alpha: 0.62)

    override var canBecomeKey: Bool {
        true
    }

    init(volume: Int) {
        let frame = NSRect(origin: .zero, size: Self.defaultExpandedSize)
        root = NSVisualEffectView(frame: frame)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        showsResizeIndicator = false
        preservesContentDuringLiveResize = true

        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active
        root.autoresizingMask = [.width, .height]
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.borderWidth = 1
        root.layer?.borderColor = Self.accentColor.withAlphaComponent(0.22).cgColor
        root.layer?.masksToBounds = true
        contentView = root

        configureExpandedUI(volume: volume)
        configureCompactUI()
        configureResizeHandle()
        contentMinSize = Self.minimumExpandedSize
        contentMaxSize = Self.maximumExpandedSize
        setContentSize(Self.defaultExpandedSize)
        delegate = self
        changed(volumeSlider)
        setSourceURL(WallpaperSource.currentURLString())
        setPlaybackAvailable(false)
        setPlaylists([], loading: true)
    }

    private lazy var volumeSlider: NSSlider = {
        let slider = NSSlider(value: 0, minValue: 0, maxValue: 100, target: self, action: #selector(changed(_:)))
        slider.controlSize = .small
        slider.isContinuous = true
        slider.setAccessibilityLabel("音量")
        return slider
    }()

    private func configureExpandedUI(volume: Int) {
        volumeSlider.doubleValue = Double(volume)
        expandedStack.orientation = .vertical
        expandedStack.alignment = .width
        expandedStack.distribution = .equalSpacing
        expandedStack.spacing = 6
        expandedStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        expandedStack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(expandedStack)

        expandedStackWidthConstraint = expandedStack.widthAnchor.constraint(equalToConstant: Self.defaultExpandedSize.width - 28)
        expandedStackBottomConstraint = expandedStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12)
        NSLayoutConstraint.activate([
            expandedStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            expandedStackBottomConstraint,
            expandedStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            expandedStackWidthConstraint,
        ])

        expandedStack.addArrangedSubview(makeHeaderRow())
        expandedStack.addArrangedSubview(makeTransportRow())
        expandedStack.addArrangedSubview(makeTimelineRow())
        expandedStack.addArrangedSubview(makeVolumeRow())
        expandedStack.addArrangedSubview(makeSourceHeaderRow())
        expandedStack.addArrangedSubview(makeURLRow())
        expandedStack.addArrangedSubview(makePlaylistRow())
        expandedStack.addArrangedSubview(makeFooterRow())
    }

    private func configureCompactUI() {
        compactStack.orientation = .horizontal
        compactStack.alignment = .centerY
        compactStack.distribution = .fill
        compactStack.spacing = 6
        compactStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        compactStack.translatesAutoresizingMaskIntoConstraints = false
        compactStack.isHidden = true
        root.addSubview(compactStack)

        compactStackWidthConstraint = compactStack.widthAnchor.constraint(equalToConstant: Self.defaultExpandedSize.width - 24)
        NSLayoutConstraint.activate([
            compactStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            compactStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            compactStackWidthConstraint,
            compactStack.heightAnchor.constraint(equalToConstant: 36),
        ])

        configureIconButton(
            compactPlayButton,
            symbol: "play.fill",
            size: 16,
            label: "再生",
            action: #selector(playTapped),
            tint: Self.accentColor
        )
        constrain(compactPlayButton, width: 32, height: 32)
        videoControls.append(compactPlayButton)

        configureTimeLabel(compactCurrentTimeLabel, alignment: .left)
        constrain(compactCurrentTimeLabel, width: 42)
        configureTimeLabel(compactDurationLabel, alignment: .right)
        constrain(compactDurationLabel, width: 42)

        compactProgressBar.onSeek = { [weak self] percent in self?.onSeek?(percent) }
        compactProgressBar.heightAnchor.constraint(equalToConstant: 18).isActive = true
        compactProgressBar.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let expandButton = makeIconButton(
            symbol: "chevron.up",
            size: 11,
            label: "パネルを展開",
            action: #selector(toggleCollapsed)
        )
        constrain(expandButton, width: 28, height: 28)

        [compactPlayButton, compactCurrentTimeLabel, compactProgressBar, compactDurationLabel, expandButton]
            .forEach(compactStack.addArrangedSubview)
    }

    private func configureResizeHandle() {
        resizeHandle.onDraggingChanged = { [weak self] resizing in self?.isResizing = resizing }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(resizeHandle)
        NSLayoutConstraint.activate([
            resizeHandle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -3),
            resizeHandle.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: 3),
            resizeHandle.widthAnchor.constraint(equalToConstant: 20),
            resizeHandle.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    private func makeHeaderRow() -> NSView {
        let logo = NSImageView()
        logo.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Live Wallpaper")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        logo.contentTintColor = Self.accentColor
        constrain(logo, width: 18, height: 18)

        let title = makeLabel("Live Wallpaper", font: Self.roundedFont(ofSize: 12, weight: .semibold), color: Self.primaryTextColor)

        qualityPopUp.controlSize = .small
        qualityPopUp.font = .systemFont(ofSize: 10, weight: .medium)
        Self.qualityOptions.forEach { qualityPopUp.addItem(withTitle: $0.title) }
        let currentQuality = WallpaperSource.maxQuality() ?? "auto"
        if let index = Self.qualityOptions.firstIndex(where: { $0.value == currentQuality }) {
            qualityPopUp.selectItem(at: index)
        }
        qualityPopUp.target = self
        qualityPopUp.action = #selector(qualityChanged(_:))
        qualityPopUp.setAccessibilityLabel("画質")
        constrain(qualityPopUp, width: 74)

        let collapseButton = makeIconButton(
            symbol: "chevron.down",
            size: 11,
            label: "パネルを折りたたむ",
            action: #selector(toggleCollapsed)
        )
        constrain(collapseButton, width: 28, height: 28)

        return makeRow([logo, title, makeSpacer(), qualityPopUp, collapseButton], height: 24, spacing: 6)
    }

    private func makeTransportRow() -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.heightAnchor.constraint(equalToConstant: 38).isActive = true

        stateLabel.font = .systemFont(ofSize: 10, weight: .semibold)
        stateLabel.textColor = Self.secondaryTextColor
        stateLabel.alignment = .left
        stateLabel.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(stateLabel)

        let previousButton = makeIconButton(
            symbol: "backward.fill",
            size: 15,
            label: "前の動画",
            action: #selector(previousTapped)
        )
        configureIconButton(
            playButton,
            symbol: "play.fill",
            size: 20,
            label: "再生",
            action: #selector(playTapped),
            tint: Self.accentColor
        )
        let nextButton = makeIconButton(
            symbol: "forward.fill",
            size: 15,
            label: "次の動画",
            action: #selector(nextTapped)
        )
        constrain(previousButton, width: 36, height: 32)
        constrain(playButton, width: 44, height: 38)
        constrain(nextButton, width: 36, height: 32)
        videoControls += [previousButton, playButton, nextButton]

        let controls = makeRow([previousButton, playButton, nextButton], spacing: 6)
        controls.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(controls)

        NSLayoutConstraint.activate([
            stateLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            stateLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            stateLabel.widthAnchor.constraint(equalToConstant: 76),
            controls.centerXAnchor.constraint(equalTo: row.centerXAnchor),
            controls.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        ])
        return row
    }

    private func makeTimelineRow() -> NSView {
        configureTimeLabel(currentTimeLabel, alignment: .left)
        configureTimeLabel(durationLabel, alignment: .right)
        constrain(currentTimeLabel, width: 48)
        constrain(durationLabel, width: 48)

        expandedProgressBar.onSeek = { [weak self] percent in self?.onSeek?(percent) }
        expandedProgressBar.heightAnchor.constraint(equalToConstant: 18).isActive = true
        expandedProgressBar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return makeRow([currentTimeLabel, expandedProgressBar, durationLabel], height: 22, spacing: 6)
    }

    private func makeVolumeRow() -> NSView {
        let speaker = NSImageView()
        speaker.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "音量")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        speaker.contentTintColor = Self.secondaryTextColor
        constrain(speaker, width: 16, height: 16)

        valueLabel.alignment = .right
        valueLabel.textColor = Self.secondaryTextColor
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        constrain(valueLabel, width: 28)
        return makeRow([speaker, volumeSlider, valueLabel], height: 22, spacing: 6)
    }

    private func makeSourceHeaderRow() -> NSView {
        let label = makeLabel("ソース", font: Self.roundedFont(ofSize: 10, weight: .semibold), color: Self.secondaryTextColor)
        let separator = NSBox()
        separator.boxType = .separator
        separator.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return makeRow([label, separator], height: 18, spacing: 8)
    }

    private func makeURLRow() -> NSView {
        urlField.placeholderString = "YouTube URL / 動画ファイルパス"
        urlField.font = .systemFont(ofSize: 11)
        urlField.lineBreakMode = .byTruncatingMiddle
        urlField.target = self
        urlField.action = #selector(playURLTapped)
        urlField.setAccessibilityLabel("再生するURLまたは動画ファイル")
        urlField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let playURLButton = makeTextButton(title: "再生", label: "入力したソースを再生", action: #selector(playURLTapped))
        constrain(playURLButton, width: 52)
        return makeRow([urlField, playURLButton], height: 28, spacing: 8)
    }

    private func makePlaylistRow() -> NSView {
        playlistPopUp.controlSize = .small
        playlistPopUp.font = .systemFont(ofSize: 11)
        playlistPopUp.addItem(withTitle: "再生リストを読み込み中")
        playlistPopUp.target = self
        playlistPopUp.action = #selector(playlistSelected(_:))
        playlistPopUp.setAccessibilityLabel("再生リスト")
        playlistPopUp.setContentHuggingPriority(.defaultLow, for: .horizontal)

        configureIconButton(
            refreshPlaylistsButton,
            symbol: "arrow.clockwise",
            size: 12,
            label: "再生リストを更新",
            action: #selector(refreshPlaylistsTapped)
        )
        constrain(refreshPlaylistsButton, width: 28, height: 28)

        loginButton.target = self
        loginButton.action = #selector(loginTapped)
        loginButton.controlSize = .small
        loginButton.bezelStyle = .rounded
        loginButton.font = .systemFont(ofSize: 10, weight: .medium)
        loginButton.setAccessibilityLabel("YouTubeログイン")
        constrain(loginButton, width: 82)

        return makeRow([playlistPopUp, refreshPlaylistsButton, loginButton], height: 28, spacing: 6)
    }

    private func makeFooterRow() -> NSView {
        sourceTypeLabel.font = .systemFont(ofSize: 9, weight: .medium)
        sourceTypeLabel.textColor = Self.secondaryTextColor

        let restoreButton = makeTextButton(
            title: "通常壁紙に戻す",
            label: "動画再生を止めて通常壁紙に戻す",
            action: #selector(restoreDesktopTapped)
        )
        restoreButton.contentTintColor = Self.dangerColor
        restoreButton.toolTip = "動画再生を止めて通常壁紙に戻す"
        constrain(restoreButton, width: 112)
        videoControls.append(restoreButton)
        return makeRow([sourceTypeLabel, makeSpacer(), restoreButton, makeFixedSpacer(width: 14)], height: 24, spacing: 6)
    }

    private func makeRow(_ views: [NSView], height: CGFloat? = nil, spacing: CGFloat = 6) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = spacing
        if let height {
            stack.heightAnchor.constraint(equalToConstant: height).isActive = true
        }
        return stack
    }

    private func makeSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return spacer
    }

    private func makeFixedSpacer(width: CGFloat) -> NSView {
        let spacer = NSView()
        constrain(spacer, width: width)
        return spacer
    }

    private func makeLabel(_ text: String, font: NSFont, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        return label
    }

    private func makeTextButton(title: String, label: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.controlSize = .small
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.setAccessibilityLabel(label)
        return button
    }

    private func makeIconButton(
        symbol: String,
        size: CGFloat,
        label: String,
        action: Selector,
        tint: NSColor = primaryTextColor
    ) -> NSButton {
        let button = NSButton(frame: .zero)
        configureIconButton(button, symbol: symbol, size: size, label: label, action: action, tint: tint)
        return button
    }

    private func configureIconButton(
        _ button: NSButton,
        symbol: String,
        size: CGFloat,
        label: String,
        action: Selector,
        tint: NSColor = primaryTextColor
    ) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold))
        button.contentTintColor = tint
        button.toolTip = label
        button.setAccessibilityLabel(label)
    }

    private func configureTimeLabel(_ label: NSTextField, alignment: NSTextAlignment) {
        label.alignment = alignment
        label.textColor = Self.primaryTextColor
        label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    }

    private func constrain(_ view: NSView, width: CGFloat? = nil, height: CGFloat? = nil) {
        if let width {
            view.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        if let height {
            view.heightAnchor.constraint(equalToConstant: height).isActive = true
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard let size = contentView?.bounds.size else { return }
        expandedStackWidthConstraint.constant = max(0, size.width - 28)
        compactStackWidthConstraint.constant = max(0, size.width - 24)
        if isCollapsed {
            expandedUserSize.width = size.width
        } else {
            expandedUserSize = size
        }
    }

    private static func roundedFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    @objc private func changed(_ sender: NSSlider) {
        let volume = sender.integerValue
        valueLabel.stringValue = "\(volume)"
        onChange?(volume)
    }

    func setProgress(_ progress: Double) {
        expandedProgressBar.setProgress(progress)
        compactProgressBar.setProgress(progress)
    }

    func updateStatus(playing: Bool, currentTime: Double, duration: Double) {
        if playing != isPlayingIcon {
            isPlayingIcon = playing
            let symbol = playing ? "pause.fill" : "play.fill"
            let label = playing ? "一時停止" : "再生"
            configureIconButton(playButton, symbol: symbol, size: 20, label: label, action: #selector(playTapped), tint: Self.accentColor)
            configureIconButton(compactPlayButton, symbol: symbol, size: 16, label: label, action: #selector(playTapped), tint: Self.accentColor)
        }
        setPlaybackAvailable(true)
        stateLabel.stringValue = playing ? "再生中" : "一時停止"
        stateLabel.textColor = playing ? Self.playingColor : Self.secondaryTextColor
        let current = Self.formatTime(currentTime)
        let total = duration > 0 ? Self.formatTime(duration) : "--:--"
        currentTimeLabel.stringValue = current
        compactCurrentTimeLabel.stringValue = current
        durationLabel.stringValue = total
        compactDurationLabel.stringValue = total
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

    func setLocalSourceMode(_ local: Bool) {
        localSource = local
        sourceTypeLabel.stringValue = local ? "ローカル動画" : "YouTube"
        qualityPopUp.isEnabled = !local
        refreshPlaylistsButton.isEnabled = !local
        if local {
            playlistPopUp.isEnabled = false
        } else if !playlistURLs.isEmpty {
            playlistPopUp.isEnabled = true
        }
    }

    func setLoginStatus(loggedIn: Bool) {
        loginButton.title = loggedIn ? "ログイン済み" : "ログイン"
        loginButton.toolTip = loggedIn
            ? "YouTube にログイン済み（クリックで再ログイン）"
            : "YouTube にログインすると Premium セッションで再生できます"
    }

    func setPlaybackAvailable(_ available: Bool) {
        videoControls.forEach { $0.isEnabled = available }
        expandedProgressBar.isEnabled = available
        compactProgressBar.isEnabled = available
        if !available {
            setProgress(0)
            [currentTimeLabel, compactCurrentTimeLabel, durationLabel, compactDurationLabel]
                .forEach { $0.stringValue = "--:--" }
            stateLabel.stringValue = "待機中"
            stateLabel.textColor = Self.secondaryTextColor
            if isPlayingIcon {
                isPlayingIcon = false
                configureIconButton(playButton, symbol: "play.fill", size: 20, label: "再生", action: #selector(playTapped), tint: Self.accentColor)
                configureIconButton(compactPlayButton, symbol: "play.fill", size: 16, label: "再生", action: #selector(playTapped), tint: Self.accentColor)
            }
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
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
        guard playlistURLs.indices.contains(index) else { return }
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
        guard Self.qualityOptions.indices.contains(index) else { return }
        onQualityChange?(Self.qualityOptions[index].value)
    }

    @objc private func toggleCollapsed() {
        if isCollapsed {
            isCollapsed = false
            contentMinSize = Self.minimumExpandedSize
            contentMaxSize = Self.maximumExpandedSize
        } else {
            expandedUserSize = contentView?.bounds.size ?? Self.defaultExpandedSize
            isCollapsed = true
            expandedStackBottomConstraint.isActive = false
            contentMinSize = NSSize(width: Self.minimumExpandedSize.width, height: Self.collapsedHeight)
            contentMaxSize = NSSize(width: Self.maximumExpandedSize.width, height: Self.collapsedHeight)
        }

        let newSize = isCollapsed
            ? NSSize(width: expandedUserSize.width, height: Self.collapsedHeight)
            : expandedUserSize
        // 上端を固定したまま伸縮し、画面外にはみ出す場合だけ位置を補正する
        var newFrame = NSRect(x: frame.minX, y: frame.maxY - newSize.height, width: newSize.width, height: newSize.height)
        if let visible = (screen ?? NSScreen.main)?.visibleFrame {
            newFrame.origin.y = max(visible.minY, min(newFrame.origin.y, visible.maxY - newFrame.height))
        }

        let showStack = isCollapsed ? compactStack : expandedStack
        let hideStack = isCollapsed ? expandedStack : compactStack

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            hideStack.isHidden = true
            showStack.alphaValue = 1
            showStack.isHidden = false
            setFrame(newFrame, display: true)
            if !isCollapsed {
                expandedStackBottomConstraint.isActive = true
            }
            return
        }

        showStack.alphaValue = 0
        showStack.isHidden = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().setFrame(newFrame, display: true)
            hideStack.animator().alphaValue = 0
            showStack.animator().alphaValue = 1
        }, completionHandler: { [weak self] in
            guard let self else { return }
            // アニメーション中に再トグルされた場合も現在の状態を基準に片付ける
            let stackToHide = self.isCollapsed ? self.expandedStack : self.compactStack
            stackToHide.isHidden = true
            stackToHide.alphaValue = 1
            if !self.isCollapsed {
                self.expandedStackBottomConstraint.isActive = true
            }
        })
    }
}
