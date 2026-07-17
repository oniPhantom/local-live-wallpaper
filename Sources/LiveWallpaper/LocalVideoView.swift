import AVFoundation
import Cocoa
import LiveWallpaperCore

// ローカル動画ファイル(mp4 / mov / m4v)を AVPlayerLayer でループ再生する壁紙ビュー。
// YouTubeView と同じ WallpaperPlayerView インターフェイスを提供する
final class LocalVideoView: NSView, WallpaperPlayerView {
    var onPlayerEvent: ((String, Int) -> Void)?

    private let player = AVQueuePlayer()
    private let playerLayer: AVPlayerLayer
    private var looper: AVPlayerLooper?
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private let filePath: String
    private var everPlayed = false
    private var reportedFailure = false
    private var lastFitMode = ""

    init(frame: NSRect, fileURL: URL, volume: Int) {
        playerLayer = AVPlayerLayer(player: player)
        filePath = fileURL.path
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.frame = bounds
        playerLayer.videoGravity = Self.gravity(for: WallpaperSource.fitMode())
        lastFitMode = WallpaperSource.fitMode()
        layer?.addSublayer(playerLayer)
        setVolume(volume)

        // ファイル不在は再生を試みる前に検知し、既存のフォールバック機構(error 扱い)に載せる
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            NSLog("wallpaper local video not found: %@", fileURL.path)
            DiagnosticLog.log("local-video-missing", [("path", fileURL.path)])
            DispatchQueue.main.async { [weak self] in
                self?.notifyFailure()
            }
            return
        }

        // AVPlayerLooper が templateItem を複製してキューに詰め、切れ目なくループ再生する
        let item = AVPlayerItem(url: fileURL)
        looper = AVPlayerLooper(player: player, templateItem: item)

        // 非対応形式などの読み込み失敗検知(looper が複製した currentItem を監視する)
        itemStatusObservation = player.observe(\.currentItem?.status, options: [.new]) { [weak self] player, _ in
            guard player.currentItem?.status == .failed else {
                return
            }
            let message = player.currentItem?.error?.localizedDescription ?? "unknown"
            DispatchQueue.main.async {
                guard let self, !self.reportedFailure else {
                    return
                }
                NSLog("wallpaper local video failed: %@ (%@)", self.filePath, message)
                DiagnosticLog.log("local-video-error", [("path", self.filePath), ("error", message)])
                self.notifyFailure()
            }
        }

        // 再生開始の検知(初回のみ playing イベントを通知する)
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            guard player.timeControlStatus == .playing else {
                return
            }
            DispatchQueue.main.async {
                guard let self, !self.everPlayed else {
                    return
                }
                self.everPlayed = true
                DiagnosticLog.log("local-video-playing", [("path", self.filePath)])
                self.onPlayerEvent?("playing", 0)
            }
        }

        player.play()
    }

    required init?(coder: NSCoder) {
        nil
    }

    // ウィンドウ・画面サイズ変更に AVPlayerLayer を追従させる
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    private func notifyFailure() {
        guard !reportedFailure else {
            return
        }
        reportedFailure = true
        onPlayerEvent?("error", 0)
    }

    // MARK: - WallpaperPlayerView

    func setVolume(_ volume: Int) {
        let bounded = min(100, max(0, volume))
        player.volume = Float(bounded) / 100
        player.isMuted = bounded <= 0
    }

    func pause() {
        player.pause()
    }

    func resume() {
        player.play()
    }

    func togglePlayback() {
        if player.rate > 0 {
            player.pause()
        } else {
            player.play()
        }
    }

    // 単一ファイルのループ再生では前後スキップの対象がないため no-op
    func previousVideo() {}
    func nextVideo() {}

    // YouTube 固有機能はローカル動画では対象外(字幕なし・画質はファイル解像度のまま)
    func setSubtitles(enabled: Bool) {}
    func setQuality(_ quality: String) {}

    // シークは再生状態を維持したまま位置だけ動かす(YouTubeView と同じ挙動)
    func seek(to percent: Double) {
        guard let item = player.currentItem, item.duration.isNumeric, item.duration.seconds > 0 else {
            return
        }
        let bounded = min(1.0, max(0.0, percent))
        let target = CMTime(seconds: item.duration.seconds * bounded, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // fit-mode 変更の即時反映(AVPlayerLayer は videoGravity の変更だけで済む)
    func invalidateFit() {
        lastFitMode = ""
        applyCurrentFitMode()
    }

    // YouTubeView と違いレイヤー変形は不要なので、fit-mode の変化だけ反映する
    func applyFit(status: [String: Any]) {
        applyCurrentFitMode()
    }

    private func applyCurrentFitMode() {
        let mode = WallpaperSource.fitMode()
        guard mode != lastFitMode else {
            return
        }
        lastFitMode = mode
        playerLayer.videoGravity = Self.gravity(for: mode)
    }

    // contain = 動画全体を表示 / cover = 切り抜いて画面を埋める
    private static func gravity(for fitMode: String) -> AVLayerVideoGravity {
        fitMode == "cover" ? .resizeAspectFill : .resizeAspect
    }

    func readStatus(_ completion: @escaping ([String: Any]?) -> Void) {
        guard let item = player.currentItem else {
            completion(nil)
            return
        }
        let duration = item.duration.isNumeric ? item.duration.seconds : 0
        let rawCurrent = player.currentTime().seconds
        let current = rawCurrent.isFinite ? max(0, rawCurrent) : 0
        completion([
            "progress": duration > 0 ? min(1, current / duration) : 0,
            "playing": player.rate > 0,
            "currentTime": current,
            "duration": duration
        ])
    }
}
