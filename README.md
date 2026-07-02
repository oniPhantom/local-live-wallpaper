# local-live-wallpaper

macOS helper for showing a YouTube video as a desktop-level wallpaper window,
controlled from a Chrome extension via Native Messaging.

## 構成

- `CodexLiveWallpaper/main.swift` — 壁紙アプリ本体(WKWebView + YouTube IFrame API)。
  Distributed Notification `com.codex.livewallpaper.command` でランタイム操作を受け付ける。
- `CodexLiveWallpaper/native-host.swift` — Chrome が起動する Native Messaging host。
  設定ファイルを更新し、アプリへコマンドを中継する。
- `chrome-extension/` — Chrome 拡張(MV3)。YouTube ページ上の「壁紙にする」ボタンと
  popup の操作 UI(再生/一時停止・前後・音量・シーク・字幕)。
- `youtube-wallpaper` — CLI から URL を切り替える従来のスクリプト。
- `scripts/install.sh` — ビルドとインストール一式。

## セットアップ

```bash
# 1. アプリと native host をビルドして /Applications へインストール
./scripts/install.sh

# 2. chrome://extensions → デベロッパーモード ON →
#    「パッケージ化されていない拡張機能を読み込む」で chrome-extension/ を選択

# 3. 表示された拡張 ID を渡して host manifest を設置
./scripts/install.sh <EXTENSION_ID>
```

以降は YouTube の watch / playlist ページ右下に出る「🖥 壁紙にする」ボタン、
またはツールバーの拡張 popup から操作できる。

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
```

音声は常に 1 画面目の player のみに流す(複数画面での音の重複防止)。
`screens.largestOnly` を有効にすると、小さいモニターは壁紙ウィンドウを作らず
通常の macOS デスクトップに戻る。

`videoIds` が 2 件以上あるときは playlist として `loadPlaylist` に渡す。
ログイン前提の playlist はログイン済み Chrome 側の DOM から content script が
動画 ID を抽出するため、WKWebView 側の認証は不要。

## 既知の制限

- WKWebView の埋め込み再生は YouTube 側の bot 判定を受けることがある
  (「ログインして bot ではないことを確認してください」/ エラーコード 152)。
  短時間に何度も再生 URL を切り替えると発生しやすい。時間を置くと回復する。
- 埋め込み不可設定の動画・記録非公開のライブ配信は再生できない。

## CLI

```bash
youtube-wallpaper "https://www.youtube.com/watch?v=VIDEO_ID"
youtube-wallpaper off
```

## 設定ファイル

```text
~/Library/Application Support/CodexLiveWallpaper/youtube-url.txt   # 再生 URL
~/Library/Application Support/CodexLiveWallpaper/playlist.txt      # 動画 ID(1 行 1 件)
~/Library/Application Support/CodexLiveWallpaper/volume.txt        # 音量 0-100
~/Library/Application Support/CodexLiveWallpaper/largest-only.txt  # "1" で最大モニターのみ動画表示
```

When no YouTube URL is configured, the app falls back to its built-in animated wallpaper.
