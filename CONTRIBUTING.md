# コントリビューションガイド

日本語 | [English](CONTRIBUTING.en.md)

Live Wallpaper への貢献に興味を持っていただきありがとうございます。
バグ報告・機能提案・プルリクエスト、いずれも歓迎します。

## 開発環境

- macOS 13 以降（Apple Silicon / Intel）
- Swift 5.9 以降（Xcode Command Line Tools または Xcode）
- SwiftLint（`brew install swiftlint`）

> ⚠️ `swift build` / `swift test` が `Invalid manifest` で失敗する場合は
> [README の注意書き](README.md#動作環境)を参照してください
> （Xcode があれば `make test` は自動でフォールバックします）。

## セットアップと検証

```bash
git clone git@github.com:oniPhantom/local-live-wallpaper.git
cd local-live-wallpaper
swift build   # ビルド
make test     # ユニットテスト
make lint     # SwiftLint
```

動作確認までしたい場合は `make install` でビルド・インストールし、
`make play URL=<YouTube URL>` で壁紙再生を試せます（`make uninstall` で削除）。

## ディレクトリ構成

| パス | 役割 |
|---|---|
| `Sources/LiveWallpaperCore/` | AppKit 非依存の純ロジック（URL 解析・ソース判定など）。テスト対象 |
| `Sources/LiveWallpaper/` | アプリ本体（AppKit / WKWebView / AVPlayerLayer） |
| `Sources/NativeHost/` | Chrome Native Messaging ホスト |
| `chrome-extension/` | Chrome 拡張機能 |
| `Tests/LiveWallpaperCoreTests/` | ユニットテスト |
| `scripts/` | インストール・リリース用スクリプト |

新しいロジックはできるだけ `LiveWallpaperCore` に置き、ユニットテストを追加してください。

## プルリクエスト

1. `main` からブランチを作成する
2. 変更を加え、`make test` と `make lint` が通ることを確認する
3. ユーザーに見える変更は `CHANGELOG.md` の `[Unreleased]` セクションに追記する
4. PR を作成する（CI の通過が必須です）

## バグ報告・機能提案

[GitHub Issues](https://github.com/oniPhantom/local-live-wallpaper/issues) へどうぞ。
バグ報告には macOS のバージョン、再現手順、期待する挙動を含めてください。

脆弱性の報告は Issues ではなく [SECURITY.md](SECURITY.md) の手順に従ってください。

## リリース

リリース作業（メンテナー向け）は [docs/RELEASING.md](docs/RELEASING.md) を参照してください。

## 行動規範

このプロジェクトには[行動規範](CODE_OF_CONDUCT.md)があります。参加者は遵守してください。
