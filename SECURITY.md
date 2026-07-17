# セキュリティポリシー

日本語 | [English](SECURITY.en.md)

## サポート対象バージョン

セキュリティ修正は最新リリースに対してのみ提供します。

| バージョン | サポート |
|---|---|
| 最新リリース（1.x） | ✅ |
| それ以前 | ❌ |

## 脆弱性の報告

脆弱性を発見した場合は、**公開の Issue を立てないでください**。

GitHub の [Private vulnerability reporting](https://github.com/oniPhantom/local-live-wallpaper/security/advisories/new)
から非公開で報告してください。報告には以下を含めてもらえると助かります。

- 影響を受けるバージョン
- 再現手順または PoC
- 想定される影響

報告は数日以内に確認し、修正の要否と対応方針を返信します。修正が公開されるまで、
詳細の公表は控えていただくようお願いします。

## 範囲について

このアプリはローカルで動作し、外部サーバーへの利用データ送信はありません
（詳細は [docs/PRIVACY.md](docs/PRIVACY.md)）。WKWebView で YouTube を表示する
性質上、YouTube 側のコンテンツに起因する問題は対象外です。
