#!/bin/zsh
set -uo pipefail

# LiveWallpaper を完全に削除する。
# usage: ./scripts/uninstall.sh [--keep-settings]

app="/Applications/LiveWallpaper.app"
old_app="/Applications/CodexLiveWallpaper.app"
nm_manifest="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.local.livewallpaper.json"
old_nm_manifest="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.codex.livewallpaper.json"
support_dir="$HOME/Library/Application Support/LiveWallpaper"
old_support_dir="$HOME/Library/Application Support/CodexLiveWallpaper"

echo "==> アプリを停止"
pkill -x LiveWallpaper 2>/dev/null || true
pkill -x CodexLiveWallpaper 2>/dev/null || true

echo "==> $app を削除"
rm -rf "$app"
rm -rf "$old_app"

echo "==> Native Messaging host manifest を削除"
rm -f "$nm_manifest"
rm -f "$old_nm_manifest"

if [[ "${1:-}" != "--keep-settings" ]]; then
  echo "==> 設定・cookie を削除 ($support_dir)"
  rm -rf "$support_dir"
  rm -rf "$old_support_dir"
else
  echo "==> 設定は保持 ($support_dir)"
fi

cat <<'EOS'

NOTE: Chrome 拡張は chrome://extensions から手動で削除してください。
==> 完了
EOS
