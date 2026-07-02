# local-live-wallpaper

macOS helper for showing a YouTube video as a desktop-level wallpaper window,
controlled from a Chrome extension via Native Messaging.

## 構成

- `CodexLiveWallpaper/main.swift` — 壁紙アプリ本体(WKWebView + YouTube IFrame API)。
  Distributed Notification `com.codex.livewallpaper.command` でランタイム操作を受け付ける。
  メニューバー常駐アイコンからも操作できる。
- `CodexLiveWallpaper/native-host.swift` — Chrome が起動する Native Messaging host。
  設定ファイルを更新し、アプリへコマンドを中継する。
- `chrome-extension/` — Chrome 拡張(MV3)。YouTube ページ上の「壁紙にする」ボタンと
  popup の操作 UI(再生/一時停止・前後・音量・シーク・字幕・画質・モニター設定)。
- `youtube-wallpaper` — CLI から URL を切り替える従来のスクリプト。
- `scripts/install.sh` — ビルドとインストール一式。
- `scripts/release.sh` — 配布用(Developer ID 署名 + 公証)。

## セットアップ

```bash
# 1. アプリと native host をビルドして /Applications へインストール
#    (host manifest も固定 ID で自動設置される)
./scripts/install.sh

# 2. chrome://extensions → デベロッパーモード ON →
#    「パッケージ化されていない拡張機能を読み込む」で chrome-extension/ を選択
```

拡張 ID は manifest.json の `key` から `gapcbmiahdgeennnieipbddmhpmnhhgg` に
固定されている(フォルダを移動しても変わらない)。

以降は YouTube の watch / playlist ページ右下に出る「🖥 壁紙にする」ボタン、
ツールバーの拡張 popup、またはメニューバーアイコンから操作できる。

## コマンド仕様(Native Messaging)

```jsonc
{ "type": "play", "url": "https://www.youtube.com/watch?v=...", "videoIds": ["id1", "id2"] }
{ "type": "off" }
{ "type": "pause" }      // 再生 / 一時停止トグル
{ "type": "next" }
{ "type": "previous" }
{ "type": "seek", "percent": 0.42 }
{ "type": "volume", "value": 35 }
{ "type": "subtitles", "enabled": false }
{ "type": "screens", "largestOnly": true }  // 面積最大のモニターのみ動画表示
{ "type": "quality", "value": "hd1080" }    // 画質上限 (auto/small/medium/large/hd720/hd1080/hd1440/hd2160)
{ "type": "status" }                        // 現状を返す(url/volume/quality/largestOnly/playing/progress)
{ "type": "login" }                         // YouTube ログインウィンドウを開く
```

- 音声は常に 1 画面目の player のみに流す(複数画面での音の重複防止)
- `screens.largestOnly` を有効にすると、小さいモニターは壁紙ウィンドウを作らず
  通常の macOS デスクトップに戻る
- `videoIds` が 2 件以上あるときは playlist として `loadPlaylist` に渡す。
  content script が playlist パネルを自動スクロールして全件の動画 ID を抽出する
  (ログイン前提の playlist もログイン済み Chrome の DOM から取れる)
- `quality` は YouTube の `vq` パラメータによるベストエフォート(確実な強制ではない)

## 自動制御

- **再生失敗フォールバック**: player エラーや 45 秒再生が始まらない状態を検知すると
  リトライし、3 回失敗で内蔵アニメ壁紙へ退避。10 分後に自動で再挑戦する
- **自動一時停止**: 画面ロック / スクリーンセーバー中、壁紙が完全に隠れている間、
  バッテリー駆動中は動画を一時停止する(復帰で自動再開)。
  バッテリー時の停止を無効にするには `battery-pause-off.txt` を作成する

## YouTube ログイン(推奨)

メニューバーアイコン →「YouTube にログイン…」でログインウィンドウが開く。
壁紙と同じ WKWebView data store を共有しているので、一度ログインすれば
壁紙の再生も Premium セッション(広告なし・bot 判定回避)になる。
Cmd+C / Cmd+V でのコピー & ペースト対応(パスワードマネージャーから貼り付け可)。
「ログイン情報を消去」で cookie を全消去できる(bot 判定が固着した時のリセットにも有効)。

## 既知の制限

- WKWebView の埋め込み再生は YouTube 側の bot 判定を受けることがある
  (「ログインして bot ではないことを確認してください」/ エラーコード 152)。
  短時間に何度も再生 URL を切り替えると発生しやすい。時間を置くと回復する
  (上記フォールバックが自動で退避・再挑戦する)。
- 埋め込み不可設定の動画・記録非公開のライブ配信は再生できない。

## CLI

```bash
youtube-wallpaper "https://www.youtube.com/watch?v=VIDEO_ID"
youtube-wallpaper off
```

## 設定ファイル

```text
~/Library/Application Support/CodexLiveWallpaper/youtube-url.txt        # 再生 URL
~/Library/Application Support/CodexLiveWallpaper/playlist.txt           # 動画 ID(1 行 1 件)
~/Library/Application Support/CodexLiveWallpaper/volume.txt             # 音量 0-100
~/Library/Application Support/CodexLiveWallpaper/largest-only.txt       # "1" で最大モニターのみ動画表示
~/Library/Application Support/CodexLiveWallpaper/quality.txt            # 画質上限(既定 hd1080)
~/Library/Application Support/CodexLiveWallpaper/panel-hidden.txt       # "1" で操作パネル非表示
~/Library/Application Support/CodexLiveWallpaper/battery-pause-off.txt  # 存在でバッテリー時停止を無効化
~/Library/Application Support/CodexLiveWallpaper/state.json             # アプリが書き出す再生状態(読み取り用)
```

When no YouTube URL is configured, the app falls back to its built-in animated wallpaper.

## 配布(署名・公証)

他の Mac に配る場合は Gatekeeper 対策として Developer ID 署名と公証が必要:

```bash
# 事前に Developer ID Application 証明書と notarytool プロファイルを用意
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=codex-wallpaper \
./scripts/release.sh
```

Chrome 拡張を配布する場合は Chrome Web Store への公開が必要
(`chrome-extension/key.pem` は署名用の秘密鍵なので git 管理外)。
