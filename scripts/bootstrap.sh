#!/bin/zsh
set -euo pipefail

# Live Wallpaper を 1 コマンドでローカルビルド・インストールする。
# ローカルでビルドするため Apple Developer Program(署名・公証)は不要。
#
# usage:
#   /bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/oniPhantom/local-live-wallpaper/main/scripts/bootstrap.sh)"
#
# clone 先は CODEX_WALLPAPER_DIR で変更可(既定: ~/local-live-wallpaper)

repo_url="https://github.com/oniPhantom/local-live-wallpaper.git"
dest="${CODEX_WALLPAPER_DIR:-$HOME/local-live-wallpaper}"

if ! xcode-select -p >/dev/null 2>&1; then
  echo "Xcode Command Line Tools が必要です。インストールダイアログを開きます…"
  xcode-select --install || true
  echo "インストールが終わったら、もう一度このコマンドを実行してください。"
  exit 1
fi

if [[ -d "$dest/.git" ]]; then
  echo "==> 既存の clone を更新 ($dest)"
  git -C "$dest" pull --ff-only
else
  echo "==> clone ($dest)"
  git clone "$repo_url" "$dest"
fi

"$dest/scripts/install.sh"

cat <<EOS

🎉 インストール完了!次のステップ:

1. Chrome から操作する場合:
   chrome://extensions → 右上「デベロッパー モード」ON →
   「パッケージ化されていない拡張機能を読み込む」で以下を選択
     $dest/chrome-extension

2. メニューバーの ▶ アイコン → 「YouTube にログイン…」
   (Premium アカウントなら広告なしで再生されます)

3. YouTube の動画ページ右下の「🖥 壁紙にする」をクリック!

アンインストール: $dest/scripts/uninstall.sh
EOS
