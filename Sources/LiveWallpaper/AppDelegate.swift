import Carbon.HIToolbox
import Cocoa
import IOKit.ps
import LiveWallpaperCore
import ServiceManagement
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    // ウィンドウ構築まわり(AppDelegate+Windows.swift)と共有するため internal にしている
    var windows: [NSWindow] = []
    // ソース種別(YouTube / ローカル動画)によらず共通プロトコルで操作する
    var playerViews: [WallpaperPlayerView] = []
    var volumePanel: VolumePanel?
    var progressTimer: Timer?
    private var statusItem: NSStatusItem?
    private var keepAliveActivity: NSObjectProtocol?
    private var keepAliveWindow: NSWindow?

    // 再生失敗時のフォールバック管理
    var playbackFailureCount = 0
    var fallbackActive = false
    var retryTimer: Timer?

    // 自動一時停止(ロック・全面遮蔽・バッテリー駆動・低電力モード)
    var autoPauseReasons: Set<String> = []
    var autoPaused = false
    private var batteryTimer: Timer?

    // YouTube ログイン状態(nil = 未確認)。メニューバーと操作パネルに反映する
    // (パネル再構築時にも参照するため internal にしている)
    var youtubeLoggedIn: Bool?
    private weak var loginStatusMenuItem: NSMenuItem?

    // グローバルホットキー(⌃⌥P: 再生/一時停止)
    private var playbackHotKey: GlobalHotKey?

    // ユーザーが明示的に一時停止したか(自動復帰や再構築で勝手に再生しないため)
    var userPaused = false
    var lastPlaying = false
    var lastProgress: Double = 0
    // 再生中の動画 ID(status から毎秒更新)。再構築時に同じ動画から再開するために使う
    var lastVideoID: String?
    // ディスプレイ構成変更などの再構築後に復元する再生位置と再生状態
    var pendingRestore: (progress: Double, resume: Bool)?

    // スペース切替時の一瞬の遮蔽で pause/resume が乱れないよう、遮蔽の pause は遅延させる
    private var occlusionPauseWork: DispatchWorkItem?
    // 画面構成変更通知は短時間に連続で届くためデバウンスする
    private var screenChangeWork: DispatchWorkItem?
    // 直近の再構築時点の画面構成。変わっていなければ再構築(=ページ再読み込み)しない
    var builtScreenFrames: [NSRect] = []

    let loginWindow = LoginWindowController()
    let playlistProvider = PlaylistProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        ProcessInfo.processInfo.disableAutomaticTermination("Keep Live Wallpaper control panel available")
        ProcessInfo.processInfo.disableSuddenTermination()
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: "Keep Live Wallpaper control panel available"
        )
        NSApp.setActivationPolicy(.accessory)
        makeMainMenu()
        makeStatusItem()
        makeKeepAliveWindow()
        makeWindows()
        loginWindow.onClose = { [weak self] in
            // ログイン後の cookie で player を作り直す(フォールバック中でも即再挑戦)
            self?.resetFallback()
            self?.makeWindows()
            self?.refreshPlaylists()
            self?.refreshLoginStatus()
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged),
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
            name: Notification.Name("com.local.livewallpaper.command"),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        let lockEvents: [(String, Bool)] = [
            ("com.apple.screenIsLocked", true),
            ("com.apple.screenIsUnlocked", false),
            ("com.apple.screensaver.didstart", true),
            ("com.apple.screensaver.didstop", false)
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
        // 低電力モード連動: 有効化で自動一時停止、解除で自動復帰
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(lowPowerModeChanged),
            name: Notification.Name.NSProcessInfoPowerStateDidChange,
            object: nil
        )
        checkLowPowerMode()
        registerPlaybackHotKey()
        refreshLoginStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func makeKeepAliveWindow() {
        guard keepAliveWindow == nil else {
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.orderFrontRegardless()
        keepAliveWindow = window
    }

    @objc private func handleRemoteCommand(_ notification: Notification) {
        guard let json = notification.object as? String,
              let data = json.data(using: .utf8),
              let command = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let type = command["type"] as? String else {
            return
        }
        DiagnosticLog.log("remote-command", [("type", type)])
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
            restoreDesktop()
        case "pause", "toggle":
            togglePlaybackTracked()
        case "next":
            playerViews.forEach { $0.nextVideo() }
        case "previous":
            playerViews.forEach { $0.previousVideo() }
        case "seek":
            if let percent = (command["percent"] as? NSNumber)?.doubleValue {
                playerViews.forEach { $0.seek(to: percent) }
            }
        case "volume":
            if let value = (command["value"] as? NSNumber)?.intValue {
                let bounded = min(100, max(0, value))
                WallpaperSource.saveVolume(bounded)
                applyVolume(bounded)
            }
        case "subtitles":
            if let enabled = command["enabled"] as? Bool {
                playerViews.forEach { $0.setSubtitles(enabled: enabled) }
            }
        case "screens":
            // native-host が設定ファイルを書き換え済みなので再構成のみ
            makeWindows()
        case "quality":
            // watch ページはリロード不要で即時反映できる
            let quality = WallpaperSource.maxQuality() ?? "auto"
            playerViews.forEach { $0.setQuality(quality) }
        case "login":
            loginWindow.show()
        case "quit":
            NSApp.terminate(nil)
        default:
            break
        }
    }

    // MARK: - 再生失敗フォールバック

    func resetFallback() {
        if fallbackActive {
            DiagnosticLog.log("fallback-exit", [("reason", "reset")])
        }
        playbackFailureCount = 0
        fallbackActive = false
        retryTimer?.invalidate()
        retryTimer = nil
    }

    func handlePlayerEvent(_ event: String, code: Int) {
        switch event {
        case "playing":
            playbackFailureCount = 0
            // 再構築後の復元: 再生位置を戻し、一時停止中だった場合は止め直す
            if let restore = pendingRestore {
                pendingRestore = nil
                if restore.progress > 0.005 && restore.progress < 0.995 {
                    playerViews.forEach { $0.seek(to: restore.progress) }
                }
                if !restore.resume {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                        self?.playerViews.forEach { $0.pause() }
                    }
                }
            }
        case "no-player-api":
            // movie_player API が取得できない = YouTube 側の DOM/API 変更の兆候。
            // 再生自体は video 要素へのフォールバック操作で続く可能性があるため記録のみ
            NSLog("wallpaper movie_player API unavailable")
            DiagnosticLog.log("no-player-api")
        case "error", "stalled":
            playbackFailureCount += 1
            NSLog("wallpaper playback failure #%d (event=%@ code=%d)", playbackFailureCount, event, code)
            DiagnosticLog.log("playback-failure", [
                ("event", event),
                ("code", "\(code)"),
                ("count", "\(playbackFailureCount)")
            ])
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
                DiagnosticLog.log("fallback-enter", [("failures", "\(playbackFailureCount)")])
                makeWindows()
                retryTimer?.invalidate()
                retryTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: false) { [weak self] _ in
                    guard let self else { return }
                    DiagnosticLog.log("fallback-exit", [("reason", "retry")])
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

    func setAutoPauseReason(_ reason: String, active: Bool) {
        let changed = active
            ? autoPauseReasons.insert(reason).inserted
            : autoPauseReasons.remove(reason) != nil
        if changed {
            DiagnosticLog.log("auto-pause", [
                ("reason", reason),
                ("active", "\(active)"),
                ("reasons", autoPauseReasons.sorted().joined(separator: ","))
            ])
        }
        updateAutoPauseState()
    }

    func updateAutoPauseState() {
        let shouldPause = !autoPauseReasons.isEmpty
        guard shouldPause != autoPaused else {
            return
        }
        autoPaused = shouldPause
        if shouldPause {
            playerViews.forEach { $0.pause() }
        } else if !userPaused {
            // ユーザーが止めていた場合はワークスペース切替などで勝手に再生しない
            playerViews.forEach { $0.resume() }
        }
    }

    // 再生/一時停止トグル。直前の実再生状態からユーザーの意図(止めたい/再生したい)を記録する
    func togglePlaybackTracked() {
        userPaused = lastPlaying
        playerViews.forEach { $0.togglePlayback() }
    }

    @objc func occlusionChanged() {
        guard !playerViews.isEmpty else {
            return
        }
        let anyVisible = windows.contains { $0.occlusionState.contains(.visible) }
        occlusionPauseWork?.cancel()
        occlusionPauseWork = nil
        if anyVisible {
            // 見えるようになったら即復帰
            setAutoPauseReason("occluded", active: false)
        } else {
            // スペース切替アニメーション中などは一瞬 occluded になるため、
            // 3 秒継続して隠れている場合のみ停止する(pause/resume の競合も防ぐ)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let stillHidden = !self.windows.contains { $0.occlusionState.contains(.visible) }
                if stillHidden {
                    self.setAutoPauseReason("occluded", active: true)
                }
            }
            occlusionPauseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
        }
    }

    // 画面構成変更はデバウンスし、実際に構成が変わった時だけ再構築する
    // (同一構成での通知のたびにページを再読み込みすると再生が先頭に戻ってしまう)
    @objc private func screenParamsChanged() {
        screenChangeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let frames = NSScreen.screens.map(\.frame)
            if frames != self.builtScreenFrames {
                DiagnosticLog.log("screen-change", [("screens", "\(frames.count)")])
                self.makeWindows()
            }
        }
        screenChangeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func checkBattery() {
        guard WallpaperSource.pauseOnBattery() else {
            setAutoPauseReason("battery", active: false)
            return
        }
        let onBattery = (IOPSGetProvidingPowerSourceType(nil)?.takeRetainedValue() as String?) == kIOPMBatteryPowerKey
        setAutoPauseReason("battery", active: onBattery)
    }

    // NSProcessInfoPowerStateDidChange は任意のスレッドで届くためメインへ移す
    @objc private func lowPowerModeChanged() {
        DispatchQueue.main.async { [weak self] in
            self?.checkLowPowerMode()
        }
    }

    private func checkLowPowerMode() {
        setAutoPauseReason("lowpower", active: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }

    // MARK: - グローバルホットキー

    // ⌃⌥P で再生/一時停止をトグル(Carbon の RegisterEventHotKey はアクセシビリティ権限不要)
    private func registerPlaybackHotKey() {
        playbackHotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_P),
            modifiers: UInt32(controlKey | optionKey),
            id: 1
        ) { [weak self] in
            DiagnosticLog.log("hotkey", [("key", "ctrl-opt-p"), ("action", "toggle-playback")])
            self?.togglePlaybackTracked()
        }
        if playbackHotKey == nil {
            // 他アプリと重複しているなど。壁紙動作には影響させず記録のみ
            NSLog("wallpaper failed to register global hotkey ctrl-opt-p")
            DiagnosticLog.log("hotkey-register-failed", [("key", "ctrl-opt-p")])
        }
    }

    // MARK: - ログイン状態

    // 既定 data store の cookie から YouTube ログイン状態を判定し、メニューとパネルへ反映する
    func refreshLoginStatus() {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { [weak self] cookies in
            let loggedIn = YouTubeLogin.isLoggedIn(
                cookies: cookies.map { (name: $0.name, domain: $0.domain) }
            )
            DispatchQueue.main.async {
                self?.applyLoginStatus(loggedIn)
            }
        }
    }

    private func applyLoginStatus(_ loggedIn: Bool) {
        if youtubeLoggedIn != loggedIn {
            DiagnosticLog.log("login-status", [("loggedIn", "\(loggedIn)")])
        }
        youtubeLoggedIn = loggedIn
        loginStatusMenuItem?.title = loginStatusText()
        volumePanel?.setLoginStatus(loggedIn: loggedIn)
    }

    private func loginStatusText() -> String {
        switch youtubeLoggedIn {
        case .some(true):
            return "YouTube: ログイン済み"
        case .some(false):
            return "YouTube: 未ログイン"
        case nil:
            return "YouTube: 状態を確認中…"
        }
    }

    // MARK: - Launch at Login

    @objc private func menuToggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                DiagnosticLog.log("launch-at-login", [("action", "unregister")])
            } else {
                try service.register()
                DiagnosticLog.log("launch-at-login", [("action", "register")])
            }
        } catch {
            // install.sh で組んだ app bundle 以外(swift run 直実行など)では登録できない
            NSLog("wallpaper launch-at-login toggle failed: %@", error.localizedDescription)
            DiagnosticLog.log("launch-at-login-error", [("error", error.localizedDescription)])
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "ログイン時に自動起動を設定できませんでした"
            alert.informativeText = "install.sh でインストールした LiveWallpaper.app から起動している場合のみ利用できます。\n詳細: \(error.localizedDescription)"
            alert.addButton(withTitle: "OK")
            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }

    // MARK: - メニューバー

    // メニューを持たない accessory アプリでは Cmd+C/V などのキーイコライザが効かないため、
    // ログインウィンドウでのコピー & ペースト用に Edit メニューを持つ main menu を設定する
    private func makeMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Live Wallpaper を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
            button.image = NSImage(systemSymbolName: "play.tv", accessibilityDescription: "Live Wallpaper")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let hasVideo = !playerViews.isEmpty

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

        let launchAtLogin = NSMenuItem(title: "ログイン時に自動起動", action: #selector(menuToggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        // 状態は SMAppService 自身が持つ(システム設定側の変更もここに反映される)
        launchAtLogin.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLogin)

        menu.addItem(.separator())

        // ログイン状態の表示行(選択不可)。cookie 判定は非同期なので表示中に更新される
        let loginStatus = NSMenuItem(title: loginStatusText(), action: nil, keyEquivalent: "")
        loginStatus.isEnabled = false
        menu.addItem(loginStatus)
        loginStatusMenuItem = loginStatus
        refreshLoginStatus()

        let login = NSMenuItem(title: "YouTube にログイン…", action: #selector(menuLogin), keyEquivalent: "")
        login.target = self
        menu.addItem(login)

        let logout = NSMenuItem(title: "ログイン情報を消去", action: #selector(menuClearWebData), keyEquivalent: "")
        logout.target = self
        menu.addItem(logout)

        menu.addItem(.separator())

        let off = NSMenuItem(title: "通常壁紙に戻す", action: #selector(menuOff), keyEquivalent: "")
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
        playerViews.forEach { $0.previousVideo() }
    }

    @objc private func menuNext() {
        playerViews.forEach { $0.nextVideo() }
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
        playerViews.forEach { $0.invalidateFit() }
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
            self?.refreshLoginStatus()
        }
    }

    @objc private func menuOff() {
        restoreDesktop()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
