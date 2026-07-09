import Cocoa

// 壁紙プレイヤー(YouTubeView / LocalVideoView)の共通インターフェイス。
// AppDelegate はソース種別を意識せず、このプロトコル越しに再生制御・状態読み取りを行う
protocol WallpaperPlayerView: NSView {
    // event: "playing" | "error" | "stalled" | "no-player-api"(code はエラーコード)
    var onPlayerEvent: ((String, Int) -> Void)? { get set }

    func setVolume(_ volume: Int)
    func pause()
    func resume()
    func togglePlayback()
    // プレイリスト非対応のソース(単一ローカルファイル)では no-op
    func previousVideo()
    func nextVideo()
    func seek(to percent: Double)
    // YouTube 固有機能。非対応のソースでは no-op
    func setSubtitles(enabled: Bool)
    func setQuality(_ quality: String)
    // fit-mode 変更時に呼ばれる。次の applyFit で新モードを適用させる
    func invalidateFit()
    func applyFit(status: [String: Any])
    // progress / playing / currentTime / duration を返す(取得不能時は nil)
    func readStatus(_ completion: @escaping ([String: Any]?) -> Void)
}

// YouTubeView は既に全メソッドを持つため宣言のみで適合する
extension YouTubeView: WallpaperPlayerView {}
