# 改善ロードマップ(草案)

最終更新: 2026-07-09

## 現状サマリー

YouTube の watch ページを WKWebView でデスクトップレベルに表示し、CSS/JS 注入で動画のみを見せる macOS 壁紙アプリ。Chrome 拡張 → Native Messaging host → Distributed Notification という操作経路と、メニューバー・操作パネル・CLI を持つ。

**強み**

- watch ページ方式により Premium ログインで広告なし・embed 不可動画も再生可能
- 自動一時停止(ロック・遮蔽・バッテリー)、失敗時フォールバック + 自動リトライなど信頼性への配慮が厚い
- 署名不要のローカルビルド 1 コマンドインストール

**構造的リスク(着手時点 2026-07-09。下記はフェーズ 1 で解消済み)**

- `main.swift` 1 ファイル約 2,100 行のモノリス。テストゼロ・CI なし
- YouTube の内部 API(`movie_player`)と DOM 構造(`ytInitialData` スクレイピング)への強依存 — YouTube 側の変更で静かに壊れる
- 設定が `*.txt` ファイル 10 個近くに分散(`youtube-url.txt`, `volume.txt`, `fit-mode.txt`, …)
- 状態同期がファイル + 通知 + 1 秒ポーリングの組み合わせで追いにくい

---

## フェーズ 1: 基盤固め(壊れにくくする)

今後の機能追加の前提。ここを飛ばすと YouTube 側の変更のたびに手探りデバッグになる。

| 項目 | 内容 | 優先度 |
|---|---|---|
| SPM プロジェクト化 + モジュール分割 | `main.swift` を `WallpaperSource`(設定)/ `YouTubeView`(player)/ `VolumePanel`(UI)/ `AppDelegate`(制御)等に分割。`swift build` でビルドできる Package.swift を導入 | ★★★ |
| ユニットテスト導入 | 純粋関数はすでにテスト可能: `parseTimeParam`, `youtubeID(from:)`, `sanitizeID`, `watchURL` 構築。まずここから | ★★★ |
| GitHub Actions CI | macOS runner で build + test。PR ごとの退行検知 | ★★★ |
| 設定の一元化 | 分散 txt → 単一 `settings.json`(または UserDefaults)。native-host との共有仕様を 1 箇所に定義 | ★★☆ |
| 診断ログ | 再生失敗・bot 判定・フォールバック遷移を `~/Library/Logs/LiveWallpaper/` に構造化ログで記録。「なぜ壁紙が止まったか」を後から追えるように | ★★☆ |
| 注入 JS の健全性チェック | `movie_player` API が取れない/DOM 構造が変わった場合を検知してネイティブ側へ明示的に通知(現在は 45 秒 stalled 頼み) | ★★☆ |

### フェーズ 1 終了条件(Definition of Done)

- [x] `Package.swift` が存在し、`swift build` が成功する(共有ロジックはライブラリターゲット、`LiveWallpaper` / `native-host` は executable ターゲット)
- [x] `main.swift` が責務別ファイル(設定 / player / パネル UI / フォールバック壁紙 / AppDelegate)に分割され、1 ファイル 600 行程度以下
- [x] `parseTimeParam` / `youtubeID(from:)` / `sanitizeID` / `watchURL` 構築のユニットテストが存在し `swift test` が全件 pass
- [x] `.github/workflows/ci.yml` が push / PR で macOS build + test を実行する定義になっている
- [x] `install.sh` / `release.sh` が SPM ビルドに追従し、従来どおり app bundle を生成できる
- [x] 再生失敗・フォールバック遷移・自動一時停止が `~/Library/Logs/LiveWallpaper/` に構造化ログとして記録される
- [x] 注入 JS が `movie_player` API を取得できない場合を検知しネイティブ側へ明示通知する
- 対象外: 設定の一元化(native-host との互換リスクが大きいため別途判断)

## フェーズ 2: 信頼性・UX 改善(日常利用の質を上げる)

| 項目 | 内容 | 優先度 |
|---|---|---|
| ログイン状態の可視化 | パネル/メニューバーに「ログイン済み(アカウント名)/ 未ログイン」を表示。セッション切れの検知と再ログイン促し | ★★★ |
| ログイン項目(Launch at Login) | `SMAppService` でログイン時自動起動のトグルをメニューに追加 | ★★★ |
| グローバルホットキー | 再生/一時停止・パネル表示切替をキーボードから(メディアキー対応も検討) | ★★☆ |
| 省電力モードの強化 | 低電力モード連動(`NSProcessInfo.isLowPowerModeEnabled`)、サーマル状態での自動画質ダウン、消費電力の目安表示 | ★★☆ |
| モニターごとの設定 | 現在は「最大モニターのみ」の二択。画面ごとに 表示/非表示・別動画 を選べるように | ★☆☆ |
| フォールバック壁紙の選択肢 | 内蔵アニメ壁紙(現在 1 種)をテーマ選択制に。静止画フォールバックも | ★☆☆ |
| パネル UX | Auto Layout 化(現在は座標ハードコード)、ライトモード対応、再生履歴からの再選択 | ★☆☆ |

### フェーズ 2 終了条件(Definition of Done)

- [x] ログイン状態(ログイン済み / 未ログイン)がメニューバーと操作パネルに表示され、ログイン・ログアウト後に更新される
- [x] メニューバーに「ログイン時に自動起動」トグルがあり、`SMAppService` で登録・解除できる(状態が永続化)
- [x] グローバルホットキー(既定: ⌃⌥P)で再生 / 一時停止をトグルできる
- [x] 低電力モード(`isLowPowerModeEnabled`)で既存の自動一時停止機構が発動する
- [x] `swift build` / `swift test` が全件 pass(既存テストの回帰なし)
- 後続へ延期: モニターごとの設定、フォールバック壁紙テーマ、パネル Auto Layout 化

## フェーズ 3: 機能拡張(できることを増やす)

| 項目 | 内容 | 優先度 |
|---|---|---|
| **ローカル動画ファイル対応** | mp4/mov を `AVPlayerLayer` でループ再生。YouTube 依存ゼロ・低消費電力・オフライン動作の再生パスができ、プロダクト名「local-live-wallpaper」にも合致する。bot 判定リスクの根本的な回避先にもなる | ★★★ |
| スケジュール切替 | 時間帯・電源状態・曜日で壁紙(URL/プレイリスト)を自動切替 | ★★☆ |
| Shortcuts / AppleScript 対応 | native-host の JSON コマンド体系をそのまま App Intents に載せる。オートメーションとの連携口 | ★★☆ |
| お気に入り・履歴 | 再生した URL の履歴とピン留め。パネル・拡張 popup 双方から選択 | ★★☆ |
| 拡張の対応ブラウザ拡大 | Edge/Brave など Chromium 系は manifest 流用でほぼ動くはず。Firefox は Native Messaging の manifest 置き場のみ差分 | ★☆☆ |
| 他ソース対応の検討 | Twitch 等。注入 JS を「プロバイダ」として抽象化してから着手 | ★☆☆ |

### フェーズ 3 終了条件(Definition of Done)

- [x] ローカル動画ファイル(mp4 / mov / m4v)を `AVPlayerLayer` でループ再生できる(パネルの URL 欄・CLI からパスまたは file:// URL を指定)
- [x] 再生 / 一時停止・音量・シーク・時間表示が操作パネルで YouTube と同等に動作する
- [x] 複数モニター表示(音声は 1 画面のみ)と自動一時停止(ロック・遮蔽・バッテリー・低電力)がローカル動画でも効く
- [x] ソース種別判定(YouTube URL / ローカルパス)のユニットテストが追加され全件 pass
- 後続へ延期: スケジュール切替、App Intents、お気に入り・履歴、他ブラウザ・他ソース対応

## フェーズ 4: 配布・コミュニティ(届けやすくする)

| 項目 | 内容 | 優先度 |
|---|---|---|
| GitHub Releases + Homebrew Cask | `release.sh` は既にあるので、タグ push → 署名・公証済み dmg を Releases へ、`brew install --cask` 対応 | ★★★ |
| Chrome Web Store 公開 | 現在はデベロッパーモードで手動読み込み。ストア公開でインストール手順が大幅短縮(YouTube ページ改変ポリシーの確認が前提) | ★★☆ |
| 自動アップデート | Sparkle 導入(署名配布が前提) | ★★☆ |
| README 英語版 + スクリーンショット/GIF | 海外ユーザー獲得。動作イメージが伝わる GIF は日本語版にも効く | ★★☆ |
| CHANGELOG とバージョニング | アプリ・拡張・native-host の 3 者のバージョン整合を管理(プロトコル互換性の明示) | ★☆☆ |

### フェーズ 4 終了条件(Definition of Done)

- [x] `.github/workflows/release.yml`: タグ push で universal ビルド → zip を GitHub Release へ添付(署名 secrets があれば Developer ID 署名、なければ ad-hoc 署名で「ローカルビルド推奨」注記)
- [x] Homebrew Cask 定義(`Casks/live-wallpaper.rb`)と tap 公開手順のドキュメント
- [x] `README.en.md` を追加し、日英 README が相互リンクされている
- [x] `CHANGELOG.md` とバージョニング方針(アプリ / 拡張 / native-host の整合)が明文化されている
- [x] Chrome Web Store 公開・Apple 公証など手動タスクは `docs/RELEASING.md` に手順として整備(自動化の対象外であることを明記)
- 残り(手動タスク): 署名 secrets 登録・`oniPhantom/homebrew-tap` 作成・Web Store 登録・Developer Program 加入は `docs/RELEASING.md` の手順に従いユーザーが実施

---

## 推奨着手順(最初の 3 手)

1. **SPM 化 + 純粋関数のテスト + CI** — 半日〜1 日で済み、以降のすべての変更が安全になる
2. **ローカル動画ファイル対応** — YouTube 依存という最大のリスクに対する保険であり、単体でも価値が大きい
3. **GitHub Releases + Homebrew Cask** — 配布の摩擦を下げ、ユーザーフィードバックの母数を増やす

## 意思決定が必要な論点

- **配布方針**: 個人利用ツールのままか、署名配布して広く届けるか。フェーズ 4 の投資判断(Apple Developer Program 年会費・公証運用)が分かれる
- **YouTube 規約リスク**: ページ改変・UI 非表示は規約グレー。Chrome Web Store 公開時に審査で問題になる可能性があり、公開するなら事前調査が必要
- **対応 OS 下限**: 現在 macOS 13+。`SMAppService` 等の新 API 採用時にどこまで下位互換を保つか
