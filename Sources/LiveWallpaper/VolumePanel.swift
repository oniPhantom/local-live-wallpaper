import Cocoa
import LiveWallpaperCore

private let youtubeAccentColor = NSColor(calibratedRed: 1.0, green: 0.15, blue: 0.12, alpha: 1)

// 収まる場合は静止表示し、はみ出す場合だけ自動横スクロールするタイトルラベル
private final class MarqueeLabel: NSView {
    private let primary = CATextLayer()
    private let secondary = CATextLayer()
    private let scroller = CALayer()
    private static let gap: CGFloat = 32
    private static let pointsPerSecond: CGFloat = 25

    var text: String = "" {
        didSet {
            guard text != oldValue else { return }
            needsLayout = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        [primary, secondary].forEach {
            $0.isWrapped = false
            scroller.addSublayer($0)
        }
        layer?.addSublayer(scroller)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        [primary, secondary].forEach { $0.contentsScale = scale }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rebuild()
        CATransaction.commit()
    }

    private func rebuild() {
        let attributed = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.85)
        ])
        let textWidth = ceil(attributed.size().width)
        let lineHeight: CGFloat = 14
        for textLayer in [primary, secondary] {
            textLayer.string = attributed
            textLayer.frame = CGRect(x: 0, y: (bounds.height - lineHeight) / 2, width: textWidth, height: lineHeight)
        }
        scroller.frame = bounds
        scroller.removeAnimation(forKey: "marquee")
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if textWidth > bounds.width, !text.isEmpty, !reduceMotion {
            // 2枚目を後ろに並べてループが途切れないようにする
            secondary.isHidden = false
            secondary.frame.origin.x = textWidth + Self.gap
            let distance = textWidth + Self.gap
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = 0
            animation.toValue = -distance
            animation.duration = CFTimeInterval(distance / Self.pointsPerSecond)
            animation.repeatCount = .infinity
            scroller.add(animation, forKey: "marquee")
        } else {
            secondary.isHidden = true
            primary.truncationMode = reduceMotion ? .end : .none
        }
    }
}

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
        NSColor.labelColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()

        let fill = NSRect(x: track.minX, y: track.minY, width: track.width * progress, height: track.height)
        youtubeAccentColor.withAlphaComponent(0.98).setFill()
        NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4).fill()

        let knobX = track.minX + track.width * progress
        NSColor.controlBackgroundColor.setFill()
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
            NSRect(x: 13, y: 7, width: 2, height: 2),
            NSRect(x: 17, y: 7, width: 2, height: 2),
            NSRect(x: 21, y: 7, width: 2, height: 2),
            NSRect(x: 17, y: 11, width: 2, height: 2),
            NSRect(x: 21, y: 11, width: 2, height: 2),
            NSRect(x: 21, y: 15, width: 2, height: 2)
        ].forEach { grip.appendOval(in: $0) }
        (isHovered ? youtubeAccentColor.withAlphaComponent(0.9) : NSColor.secondaryLabelColor).setFill()
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
        ("480p", "large")
    ]

    private static let defaultExpandedSize = NSSize(width: 372, height: 307)
    private static let minimumExpandedSize = NSSize(width: 340, height: 307)
    private static let maximumExpandedSize = NSSize(width: 640, height: 420)
    private static let collapsedSize = NSSize(width: 97, height: 56)
    private let root: NSView
    private let expandedStack = NSStackView()
    private let compactStack = NSStackView()
    private let resizeHandle = ResizeHandleView(frame: .zero)
    private var expandedStackWidthConstraint: NSLayoutConstraint!
    private var expandedStackBottomConstraint: NSLayoutConstraint!
    private let expandedProgressBar = ProgressBar(frame: .zero)
    private let playButton = NSButton(frame: .zero)
    private let compactPlayButton = NSButton(frame: .zero)
    private let urlField = NSTextField(frame: .zero)
    private let playlistPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let refreshPlaylistsButton = NSButton(frame: .zero)
    private let loginButton = NSButton(title: "ログイン", target: nil, action: nil)
    private let qualityPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let titleMarquee = MarqueeLabel(frame: .zero)
    private let currentTimeLabel = NSTextField(labelWithString: "--:--")
    private let durationLabel = NSTextField(labelWithString: "--:--")
    private let stateLabel = NSTextField(labelWithString: "待機中")
    private let valueLabel = NSTextField(labelWithString: "0")
    private let sourceTypeLabel = NSTextField(labelWithString: "YouTube")
    private var playlistURLs: [String] = []
    private var localSource = false
    private var videoControls: [NSControl] = []
    private var isPlayingIcon = false
    private(set) var isCollapsed = false
    private(set) var isResizing = false
    private var expandedUserSize = defaultExpandedSize

    private static let accentColor = youtubeAccentColor
    private static let playingColor = NSColor.systemGreen
    private static let dangerColor = NSColor.systemRed
    private static let primaryTextColor = NSColor.labelColor
    private static let secondaryTextColor = NSColor.secondaryLabelColor

    override var canBecomeKey: Bool {
        true
    }

    // NSGlassEffectView のガラスは SwiftUI 実装(内部に NSVisualEffectView は無い)で、
    // ウィンドウのキー状態に追従して非キー時は平坦な描画に落ちる。
    // 常駐アプリのパネルはほぼ常に非キーなので、キー状態を常に true と報告して
    // ガラス描画を維持する(イベントルーティングは NSApp.keyWindow 基準なので影響しない)
    override var isKeyWindow: Bool { true }

    private static func makeFallbackRoot(frame: NSRect) -> NSVisualEffectView {
        let effect = NSVisualEffectView(frame: frame)
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .vibrantDark)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 20
        effect.layer?.cornerCurve = .continuous
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor(calibratedWhite: 1, alpha: 0.20).cgColor
        effect.layer?.masksToBounds = true
        return effect
    }

    init(volume: Int) {
        let frame = NSRect(origin: .zero, size: Self.defaultExpandedSize)
        let panelRoot: NSView
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            let content = NSView(frame: frame)
            content.autoresizingMask = [.width, .height]
            glass.contentView = content
            // .clear のガラス感を活かし、視認性はコンテンツ背面のディム層で確保する。
            // appearance は darkAqua(vibrantDark はガラス描画を無効化してしまう)
            glass.style = .clear
            glass.cornerRadius = 20
            glass.appearance = NSAppearance(named: .darkAqua)
            // darkAqua 時に glass が敷く暗色バックドロップは cornerRadius に
            // 追従せず、四隅に四角い黒縁が残るためレイヤーごと角丸で切り落とす
            glass.wantsLayer = true
            glass.layer?.cornerRadius = 20
            glass.layer?.cornerCurve = .continuous
            glass.layer?.masksToBounds = true
            content.wantsLayer = true
            content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.28).cgColor
            root = content
            panelRoot = glass
        } else {
            let effect = Self.makeFallbackRoot(frame: frame)
            root = effect
            panelRoot = effect
        }
        #else
        let effect = Self.makeFallbackRoot(frame: frame)
        root = effect
        panelRoot = effect
        #endif
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel, .resizable], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isFloatingPanel = true
        level = .floating
        // .fullScreenAuxiliary は付けない: 全画面 Space では壁紙が見えない
        // (全面被覆で自動一時停止する)ためパネルも表示しない
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        isMovableByWindowBackground = true
        showsResizeIndicator = false
        preservesContentDuringLiveResize = true

        panelRoot.autoresizingMask = [.width, .height]
        contentView = panelRoot

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

        expandedStackWidthConstraint = expandedStack.widthAnchor.constraint(equalToConstant: Self.defaultExpandedSize.width - 32)
        expandedStackBottomConstraint = expandedStack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14)
        NSLayoutConstraint.activate([
            expandedStack.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            expandedStackBottomConstraint,
            expandedStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            expandedStackWidthConstraint
        ])

        expandedStack.addArrangedSubview(makeHeaderRow())
        expandedStack.addArrangedSubview(makeTitleRow())
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
        compactStack.translatesAutoresizingMaskIntoConstraints = false
        compactStack.isHidden = true
        root.addSubview(compactStack)

        NSLayoutConstraint.activate([
            compactStack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            compactStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            compactStack.widthAnchor.constraint(equalToConstant: Self.collapsedSize.width - 24),
            compactStack.heightAnchor.constraint(equalToConstant: 36)
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

        let expandButton = makeIconButton(
            symbol: "chevron.up",
            size: 11,
            label: "パネルを展開",
            action: #selector(toggleCollapsed)
        )
        constrain(expandButton, width: 28, height: 28)

        // ボタン間の区切り線。ボタン以外の場所(ここを含む余白)がドラッグ可能だと
        // 視覚的に分かるようにする
        let divider = NSView(frame: .zero)
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.25).cgColor
        constrain(divider, width: 1, height: 20)

        [compactPlayButton, divider, expandButton]
            .forEach(compactStack.addArrangedSubview)
    }

    private func configureResizeHandle() {
        resizeHandle.onDraggingChanged = { [weak self] resizing in self?.isResizing = resizing }
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(resizeHandle)
        NSLayoutConstraint.activate([
            resizeHandle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -3),
            resizeHandle.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: 3),
            resizeHandle.widthAnchor.constraint(equalToConstant: 28),
            resizeHandle.heightAnchor.constraint(equalToConstant: 28)
        ])
    }

    private func makeHeaderRow() -> NSView {
        let logo = NSImageView()
        logo.image = NSImage(systemSymbolName: "play.rectangle.fill", accessibilityDescription: "Live Wallpaper")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .bold))
        logo.contentTintColor = Self.accentColor
        constrain(logo, width: 18, height: 18)

        let title = makeLabel("Live Wallpaper", font: Self.roundedFont(ofSize: 12, weight: .semibold), color: Self.primaryTextColor)
        stateLabel.font = .systemFont(ofSize: 9, weight: .medium)
        stateLabel.textColor = Self.secondaryTextColor
        let identity = NSStackView(views: [title, stateLabel])
        identity.orientation = .vertical
        identity.alignment = .leading
        identity.spacing = 0

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

        return makeRow([logo, identity, makeSpacer(), qualityPopUp, collapseButton], height: 32, spacing: 7)
    }

    private func makeTransportRow() -> NSView {
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
        constrain(previousButton, width: 34, height: 32)
        constrain(playButton, width: 42, height: 36)
        constrain(nextButton, width: 34, height: 32)
        videoControls += [previousButton, playButton, nextButton]

        return makeRow(
            [makeSpacer(), previousButton, playButton, nextButton, makeSpacer()],
            height: 38,
            spacing: 8
        )
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
        return makeRow([sourceTypeLabel, makeSpacer(), restoreButton, makeFixedSpacer(width: 30)], height: 24, spacing: 6)
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
        invalidateShadow()
        guard !isCollapsed, let size = contentView?.bounds.size else { return }
        expandedStackWidthConstraint.constant = max(0, size.width - 32)
        expandedUserSize = size
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
    }

    private func makeTitleRow() -> NSView {
        titleMarquee.translatesAutoresizingMaskIntoConstraints = false
        titleMarquee.heightAnchor.constraint(equalToConstant: 15).isActive = true
        titleMarquee.setAccessibilityLabel("再生中の動画タイトル")
        return titleMarquee
    }

    func updateStatus(playing: Bool, currentTime: Double, duration: Double, title: String? = nil) {
        if let title, !title.isEmpty {
            titleMarquee.text = title
        }
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
        durationLabel.stringValue = total
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
        if !available {
            setProgress(0)
            titleMarquee.text = ""
            [currentTimeLabel, durationLabel]
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
            contentMinSize = Self.minimumExpandedSize
            contentMaxSize = Self.maximumExpandedSize
            isCollapsed = false
        } else {
            expandedUserSize = contentView?.bounds.size ?? Self.defaultExpandedSize
            isCollapsed = true
            expandedStackBottomConstraint.isActive = false
            contentMinSize = Self.collapsedSize
            contentMaxSize = Self.collapsedSize
        }
        expandedStack.isHidden = isCollapsed
        compactStack.isHidden = !isCollapsed
        resizeHandle.isHidden = isCollapsed

        let newSize = isCollapsed
            ? Self.collapsedSize
            : expandedUserSize
        var newFrame = frame
        newFrame.origin.x = frame.maxX - newSize.width
        newFrame.origin.y = frame.maxY - newSize.height
        newFrame.size = newSize
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        setFrame(newFrame, display: true, animate: animate)
        root.frame = NSRect(origin: .zero, size: newSize)
        if !isCollapsed {
            expandedStackBottomConstraint.isActive = true
        }
        // 透明ウィンドウは形状変更後に影を作り直さないと
        // 旧サイズの影が四隅に黒い線として残る
        invalidateShadow()
    }
}
