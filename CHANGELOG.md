# Changelog

本プロジェクトの注目すべき変更をこのファイルに記録します。
形式は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に従います。

## バージョニング方針

- **一体リリース**: アプリ本体(`Sources/LiveWallpaper/Info.plist` の
  `CFBundleShortVersionString`)・Chrome 拡張(`chrome-extension/manifest.json` の
  `version`)・native-host(app bundle に同梱)は同一リポジトリで一体としてリリースし、
  リリース時に 3 者を同じバージョンへ揃える
- **互換性の基準**: Native Messaging の JSON コマンド仕様(README「コマンド仕様」)を
  アプリ・拡張・native-host 間のプロトコルとみなし、
  - コマンドの削除・意味変更(後方非互換)= メジャーを上げる(0.x の間はマイナー)
  - コマンド・フィールドの追加(後方互換)= マイナーを上げる
  - 挙動を変えない修正 = パッチを上げる
- **タグ**: `v<version>`(例: `v0.2.0`)。タグ push で GitHub Release が自動作成される
  (`.github/workflows/release.yml`、手順は [docs/RELEASING.md](docs/RELEASING.md))

## [Unreleased]

### Added

- コミュニティ文書を追加(日英併記): `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md`
  (Contributor Covenant v2.1)/ `SECURITY.md`
- README にバッジ(CI / License / Release)とコントリビュートセクションを追加
- `.github/dependabot.yml`: GitHub Actions の依存を週次で自動更新
- SwiftLint を導入: `.swiftlint.yml`・`make lint`・CI の lint ジョブ
- README を刷新: ロゴ・タグライン・バッジ(macOS / Swift 追加)のヒーローヘッダー、
  機能一覧、目次、インストール手順のセクション統合(日英とも)。アプリアイコンを
  `docs/assets/icon.png` として同梱

### Changed

- 操作パネルをフロストガラスと再生コントロールの階層が伝わるデザインへ刷新
- SwiftLint の自動修正でコレクション末尾のカンマを削除(挙動変更なし)

## [1.0.0] - 2026-07-13

### Added

- SPM プロジェクト化: `Package.swift`(macOS 13+)。共有ロジックを
  `LiveWallpaperCore` ライブラリに、`LiveWallpaper` / `NativeHost` を
  executable ターゲットに分離。universal ビルド対応
- ユニットテスト: URL/ID 解析(`parseTimeParam` / `youtubeID(from:)` /
  `sanitizeID`)・watch URL 構築・ソース種別判定(YouTube URL / ローカルパス)
- GitHub Actions CI(`.github/workflows/ci.yml`): push / PR ごとに
  macOS で build + test
- 診断ログ: 再生失敗・フォールバック遷移・自動一時停止を
  `~/Library/Logs/LiveWallpaper/` に構造化ログとして記録
- 注入 JS の健全性チェック: `movie_player` API を取得できない場合を検知して
  ネイティブ側へ明示的に通知
- ログイン状態(ログイン済み / 未ログイン)をメニューバーと操作パネルに表示
- 「ログイン時に自動起動」トグル(`SMAppService`)
- グローバルホットキー ⌃⌥P で再生 / 一時停止をトグル
- 低電力モード(`isLowPowerModeEnabled`)連動の自動一時停止
- ローカル動画ファイル(mp4 / mov / m4v)を `AVPlayerLayer` でループ再生
  (パネルの URL 欄・CLI から指定。複数モニター・自動一時停止・パネル操作に対応)
- リリース自動化(`.github/workflows/release.yml`): `v*` タグ push で
  universal ビルド → zip → GitHub Release。署名 secrets があれば
  Developer ID 署名 + 公証、なければ ad-hoc 署名 + 注記
- Homebrew Cask 定義(`Casks/live-wallpaper.rb`)と tap 公開手順
- 英語版 README(`README.en.md`)と日英相互リンク
- リリース手順書(`docs/RELEASING.md`)と改善ロードマップ(`docs/ROADMAP.md`)

### Changed

- 操作パネルを再生・シーク中心に再編し、コンパクト表示と右下ドラッグによる
  パネルサイズ変更を追加
- `main.swift`(約 2,100 行)を責務別ファイル(AppDelegate / player /
  パネル UI / フォールバック壁紙 ほか)へ分割
- `install.sh` / `release.sh` を SPM ビルドへ追従(app bundle の生成方法は従来どおり)
- `release.sh` に `ALLOW_ADHOC=1` を追加(CI 向けの ad-hoc 署名モード。
  既定の動作は従来どおり `CODESIGN_IDENTITY` 必須)

## [0.1.0] - 2026-07-09

初期リリースまでの開発分(コミット `00be7eb`〜`debbca5`)。

### Added

- YouTube の watch ページを WKWebView でデスクトップレベルに表示し、
  CSS/JS 注入で動画のみを見せる壁紙アプリ本体
- Chrome 拡張 + Native Messaging host(「壁紙にする」ボタン・popup から操作)
- watch ページ方式への移行(Premium ログインで広告なし・embed 不可動画も再生可能)と
  信頼性・操作性の改善一式(自動一時停止・フォールバック・自動リトライ)
- 操作パネル: デザイン刷新・位置調整・ドラッグ移動・時間と再生状態の表示・
  URL 直接再生・ログイン中アカウントの再生リスト選択・常駐化
- 一般公開向けの整備: clone してそのまま使えるリポジトリ構成、
  1 コマンドインストールの `bootstrap.sh`、「Live Wallpaper」への名称整理
- 壁紙 CLI の make ターゲット(`make play` / `make off`)

<!-- 0.1.0 は git タグを打っていないため比較リンクは省略(次回リリースからタグ運用) -->
[Unreleased]: https://github.com/oniPhantom/local-live-wallpaper/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/oniPhantom/local-live-wallpaper/releases/tag/v1.0.0
[0.1.0]: https://github.com/oniPhantom/local-live-wallpaper/commits/main
