# リリース手順

タグ push から GitHub Release 作成までは自動化されています(`.github/workflows/release.yml`)。
このドキュメントでは、その前後に必要な作業と、**自動化の対象外である手動タスク**
(署名 secrets の設定・Homebrew tap・Chrome Web Store・Apple 公証の事前準備)をまとめます。

## 1. バージョン更新(リリース前・必須)

3 コンポーネントは一体リリースとし、同じバージョンへ揃えます
(方針の詳細は [CHANGELOG.md](../CHANGELOG.md) の「バージョニング方針」):

| 更新箇所 | ファイル |
|---|---|
| アプリ | `Sources/LiveWallpaper/Info.plist` の `CFBundleShortVersionString`(あわせて `CFBundleVersion` もインクリメント) |
| Chrome 拡張 | `chrome-extension/manifest.json` の `version` |
| CHANGELOG | `CHANGELOG.md` の `[Unreleased]` を `[<version>] - <date>` に繰り下げ、新しい空の `[Unreleased]` を作る |

> release ワークフローはタグ(`vX.Y.Z`)と Info.plist の
> `CFBundleShortVersionString` が一致しない場合に失敗します。

## 2. タグ push → Release 自動化の流れ

```bash
git tag v0.2.0
git push origin v0.2.0
```

タグ push で `.github/workflows/release.yml` が起動し、以下を自動実行します:

1. タグと Info.plist のバージョン整合チェック
2. universal ビルド(arm64 + x86_64)→ `LiveWallpaper.app` の組み立て
   (ビルド・bundle 組み立て・署名・zip 化はローカルと同じ `scripts/release.sh` を使用)
3. 署名:
   - 署名 secrets(下記 §3)が設定されていれば **Developer ID 署名 + 公証**
   - 未設定なら **ad-hoc 署名**で続行し、Release ノートに「Gatekeeper 警告が出るため
     ローカルビルド(bootstrap.sh)推奨」の注記を自動挿入
4. `LiveWallpaper-<version>.zip`(+ sha256 ファイル)を添付した GitHub Release を作成

リリース後の確認: Releases ページで zip・sha256・ノートの注記(署名状態)を確認します。

## 3. 署名 secrets の設定(手動タスク)

リポジトリの Settings → Secrets and variables → Actions に以下を登録します。
**未設定でもリリースは ad-hoc 署名で成立します**(個人利用・ローカルビルド前提の運用なら不要)。

| Secret | 内容 |
|---|---|
| `MACOS_CERTIFICATE_P12` | Developer ID Application 証明書(秘密鍵含む .p12)を base64 化した文字列 |
| `MACOS_CERTIFICATE_PASSWORD` | 上記 .p12 のパスワード |
| `NOTARY_APPLE_ID` | 公証に使う Apple ID(任意。3 つ揃うと公証まで実行) |
| `NOTARY_TEAM_ID` | Team ID(例: `ABCDE12345`) |
| `NOTARY_PASSWORD` | Apple ID の **App 用パスワード**(appleid.apple.com で発行) |

.p12 の作り方(証明書の入った Mac 上で):

```bash
# キーチェーンアクセスで Developer ID Application 証明書を書き出して p12 を作成した後:
base64 -i certificate.p12 | pbcopy   # これを MACOS_CERTIFICATE_P12 に貼り付け
```

## 4. Homebrew tap の更新手順(手動タスク)

初回のみ:

1. GitHub に `oniPhantom/homebrew-tap` リポジトリを作成(public)
2. リポジトリ直下に `Casks/` ディレクトリを作り、本リポジトリの
   `Casks/live-wallpaper.rb` をコピーして置く

リリースごと:

1. Release に添付された zip の sha256 を取得
   (添付の `.sha256` ファイル、または `shasum -a 256 LiveWallpaper-<version>.zip`)
2. `homebrew-tap` の `Casks/live-wallpaper.rb` で `version` と `sha256` を更新して push
3. 動作確認:

```bash
brew tap oniPhantom/tap
brew install --cask live-wallpaper
brew audit --cask oniPhantom/tap/live-wallpaper   # 任意
```

> 本リポジトリの `Casks/live-wallpaper.rb` は tap へ置く定義の原本です。
> sha256 は placeholder のため、リリース後に実際の値へ置き換えてから tap へ反映してください。

## 5. Chrome Web Store 公開手順(手動タスク・自動化対象外)

> ⚠️ **ポリシーリスク**: 本拡張は YouTube ページの表示を改変(UI 非表示・動画のみ表示)
> するため、Chrome Web Store の審査やユーザーデータ/コンテンツ改変ポリシー、
> YouTube の利用規約の観点で問題になる可能性があります。公開する場合は事前に
> [Developer Program Policies](https://developer.chrome.com/docs/webstore/program-policies)
> を確認してください。非公開(限定公開/unlisted)での配布も選択肢です。

1. [Chrome Web Store Developer Dashboard](https://chrome.google.com/webstore/devconsole)
   でデベロッパー登録(初回のみ・登録料 $5)
2. `chrome-extension/` を zip 化してアップロード:

   ```bash
   cd chrome-extension && zip -r ../chrome-extension.zip . -x '.*'
   ```

3. ストア掲載情報(説明・スクリーンショット・カテゴリ)、プライバシーの開示
   (`nativeMessaging` / `tabs` / `storage` 権限と `docs/PRIVACY.md` の内容)を入力
4. 審査へ提出(数日かかる場合あり)。公開後は manifest の `version` を上げないと
   更新をアップロードできない点に注意
5. **公開版では拡張 ID が変わらないこと**を確認(manifest の `key` で固定済み)。
   万一 ID が変わる場合は Native Messaging manifest(`install.sh` の
   `allowed_origins` と Cask の postflight)の追従が必要

## 6. Apple 公証の事前準備(手動タスク・自動化対象外)

1. [Apple Developer Program](https://developer.apple.com/programs/) に加入(年会費 $99)
2. Developer ID Application 証明書を作成し、キーチェーンへインストール
3. App 用パスワードを [appleid.apple.com](https://appleid.apple.com) で発行
4. CI で公証する場合 → §3 の secrets を設定
5. ローカルで公証する場合 → notarytool プロファイルを登録して `release.sh` を実行:

```bash
xcrun notarytool store-credentials live-wallpaper \
  --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>

CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=live-wallpaper \
./scripts/release.sh
```

## 手動タスクまとめ(自動化の対象外)

- [ ] 署名 secrets の登録(§3。任意 — 未設定なら ad-hoc 署名)
- [ ] `oniPhantom/homebrew-tap` リポジトリの作成と Cask の設置・更新(§4)
- [ ] Chrome Web Store のデベロッパー登録・zip アップロード・審査対応(§5)
- [ ] Apple Developer Program 加入・証明書作成・App 用パスワード発行(§6)
