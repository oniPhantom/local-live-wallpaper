import Cocoa
import LiveWallpaperCore

// 壁紙ウィンドウ・操作パネル・進捗タイマーの構築まわり
extension AppDelegate {
    func restoreDesktop() {
        WallpaperSource.clear()
        resetFallback()
        pendingRestore = nil
        userPaused = false
        lastPlaying = false
        lastProgress = 0
        lastVideoID = nil
        autoPauseReasons.removeAll()
        autoPaused = false
        windows.forEach { $0.close() }
        windows.removeAll()
        playerViews.removeAll()
        progressTimer?.invalidate()
        progressTimer = nil
        WallpaperSource.clearState()
        updateVolumePanel(videoEnabled: false, volume: WallpaperSource.volume())
    }

    func playURL(_ rawURL: String) {
        let url = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        // ローカル動画パス(~ 展開前・スペース含み可)は URL として不正でも受け付ける
        let isLocalVideo = LocalVideoSource.localPath(from: url) != nil
        guard !url.isEmpty, isLocalVideo || URL(string: url) != nil else {
            NSSound.beep()
            return
        }
        WallpaperSource.saveYouTubeURL(url)
        WallpaperSource.savePlaylist([])
        resetFallback()
        rebuildWindows(fresh: true)
    }

    func refreshPlaylists() {
        volumePanel?.setPlaylists([], loading: true)
        playlistProvider.load { [weak self] entries in
            DispatchQueue.main.async {
                DiagnosticLog.log("playlists-loaded", [("count", "\(entries.count)")])
                self?.volumePanel?.setPlaylists(entries)
            }
        }
    }

    // 音声は 1 画面目の player のみに流す(複数画面で重複再生されるのを防ぐ)
    func applyVolume(_ volume: Int) {
        for (index, view) in playerViews.enumerated() {
            view.setVolume(index == 0 ? volume : 0)
        }
    }

    @objc func makeWindows() {
        rebuildWindows(fresh: false)
    }

    func rebuildWindows(fresh: Bool) {
        // 再構築時に「直前に再生していた動画」から再開するための ID
        var restoreVideoID: String?
        if fresh {
            // 新しい動画の再生開始: 復元情報と一時停止状態はリセット
            pendingRestore = nil
            userPaused = false
            lastPlaying = false
            lastProgress = 0
            lastVideoID = nil
        } else if !playerViews.isEmpty {
            // ディスプレイ構成変更などの再構築: 動画・位置・停止状態を引き継ぐ
            pendingRestore = (lastProgress, !userPaused)
            restoreVideoID = lastVideoID
        }
        windows.forEach { $0.close() }
        playerViews.removeAll()
        progressTimer?.invalidate()
        progressTimer = nil
        // ローカル動画パスなら AVPlayerLayer 再生、そうでなければ従来の YouTube 再生
        let localVideoURL = LocalVideoSource.localPath(from: WallpaperSource.currentURLString())
            .map(LocalVideoSource.fileURL(for:))
        var youtubeID = localVideoURL == nil ? WallpaperSource.youtubeID() : nil
        let playlistID = localVideoURL == nil ? WallpaperSource.youtubePlaylistID() : nil
        var videoIDs = localVideoURL == nil ? WallpaperSource.playlistVideoIDs() : []
        // プレイリスト再生中の再構築は先頭に戻さず、直前の動画から再開する
        if let restoreVideoID {
            if videoIDs.count > 1, videoIDs.contains(restoreVideoID) {
                videoIDs = WallpaperSource.rotated(videoIDs, toStartAt: restoreVideoID)
            } else if playlistID != nil {
                youtubeID = restoreVideoID
            }
        }
        let volume = WallpaperSource.volume()
        // フォールバック中は設定を残したままアニメ壁紙を表示する
        let hasVideoSource = localVideoURL != nil || youtubeID != nil || playlistID != nil || !videoIDs.isEmpty
        let videoEnabled = hasVideoSource && !fallbackActive
        guard videoEnabled || fallbackActive else {
            windows.removeAll()
            updateVolumePanel(videoEnabled: false, volume: volume)
            WallpaperSource.clearState()
            return
        }
        let largestOnly = WallpaperSource.videoOnLargestScreenOnly()
        let screens = NSScreen.screens
        let largestScreen = screens.max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        windows = screens.compactMap { screen in
            // オプション有効時、小さいモニターにはウィンドウを作らず通常のデスクトップに戻す
            if videoEnabled && largestOnly && screen !== largestScreen {
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
            if videoEnabled {
                // 音声は 1 画面目の player のみ。全画面に流すと重複して聞こえる
                let view: WallpaperPlayerView
                if let localVideoURL {
                    view = LocalVideoView(
                        frame: localFrame,
                        fileURL: localVideoURL,
                        volume: playerViews.isEmpty ? volume : 0
                    )
                } else {
                    view = YouTubeView(
                        frame: localFrame,
                        videoID: youtubeID,
                        playlistID: playlistID,
                        videoIDs: videoIDs,
                        volume: playerViews.isEmpty ? volume : 0,
                        startSeconds: WallpaperSource.startSeconds()
                    )
                }
                // 再生イベントは音声担当の 1 画面目のみ監視(全画面分監視すると多重カウントになる)
                if playerViews.isEmpty {
                    view.onPlayerEvent = { [weak self] event, code in
                        DispatchQueue.main.async {
                            self?.handlePlayerEvent(event, code: code)
                        }
                    }
                }
                playerViews.append(view)
                window.contentView = view
            } else {
                window.contentView = WallpaperView(frame: localFrame)
            }
            window.orderFrontRegardless()
            return window
        }
        updateVolumePanel(videoEnabled: videoEnabled, volume: volume)
        updateProgressTimer(videoEnabled: videoEnabled)
        // この構成で構築済みであることを記録(同一構成の通知では再構築しない)
        builtScreenFrames = screens.map(\.frame)
        if !videoEnabled {
            WallpaperSource.clearState()
        }
        // 再構成後に自動一時停止の状態を再適用する
        autoPaused = false
        occlusionChanged()
        updateAutoPauseState()
    }

    func updateVolumePanel(videoEnabled: Bool, volume: Int) {
        guard !WallpaperSource.panelHidden(), let screen = NSScreen.main else {
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
            self?.playerViews.forEach { $0.seek(to: percent) }
        }
        panel.onTogglePlayback = { [weak self] in
            self?.togglePlaybackTracked()
        }
        panel.onPreviousVideo = { [weak self] in
            self?.playerViews.forEach { $0.previousVideo() }
        }
        panel.onNextVideo = { [weak self] in
            self?.playerViews.forEach { $0.nextVideo() }
        }
        panel.onRestoreDesktop = { [weak self] in
            self?.restoreDesktop()
        }
        panel.onPlayURL = { [weak self] url in
            self?.playURL(url)
        }
        panel.onPlaylistSelected = { [weak self] url in
            self?.playURL(url)
        }
        panel.onRefreshPlaylists = { [weak self] in
            self?.refreshPlaylists()
        }
        panel.onLogin = { [weak self] in
            self?.loginWindow.show()
        }
        panel.onQualityChange = { [weak self] quality in
            WallpaperSource.saveMaxQuality(quality)
            self?.playerViews.forEach { $0.setQuality(quality) }
        }
        panel.setSourceURL(WallpaperSource.currentURLString())
        // ローカル動画再生中は再生リスト・画質の操作が意味を持たないため無効化する
        panel.setLocalSourceMode(LocalVideoSource.localPath(from: WallpaperSource.currentURLString()) != nil)
        panel.setPlaybackAvailable(videoEnabled)
        // 判定済みのログイン状態をパネル再構築後にも反映する
        if let loggedIn = youtubeLoggedIn {
            panel.setLoginStatus(loggedIn: loggedIn)
        }
        if volumePanel == nil {
            panel.setPlaylists([], loading: true)
            refreshPlaylists()
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
        guard let panel = notification.object as? VolumePanel, !panel.isResizing else {
            return
        }
        WallpaperSource.savePanelOrigin(panel.frame.origin)
    }

    func updateProgressTimer(videoEnabled: Bool) {
        guard videoEnabled else {
            return
        }

        progressTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else {
                return
            }
            for (index, view) in self.playerViews.enumerated() {
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
                    if let videoID = status["videoId"] as? String, !videoID.isEmpty {
                        self?.lastVideoID = videoID
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
