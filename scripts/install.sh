#!/bin/zsh
set -euo pipefail

# CodexLiveWallpaper.app と Native Messaging host をビルド・インストールする。
# usage:
#   ./scripts/install.sh                # アプリのビルド・インストールのみ
#   ./scripts/install.sh <EXTENSION_ID> # Chrome 拡張の ID を指定して host manifest も設置

repo_root="${0:A:h:h}"
app="/Applications/CodexLiveWallpaper.app"
build_dir="$repo_root/build"
host_name="com.codex.livewallpaper"
nm_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

extension_id="${1:-}"

echo "==> Swift をビルド"
mkdir -p "$build_dir"
swiftc -O "$repo_root/CodexLiveWallpaper/main.swift" -o "$build_dir/CodexLiveWallpaper"
swiftc -O "$repo_root/CodexLiveWallpaper/native-host.swift" -o "$build_dir/native-host"

echo "==> $app へインストール"
was_running=0
if pkill -x CodexLiveWallpaper 2>/dev/null; then
  was_running=1
  sleep 1
fi
mkdir -p "$app/Contents/MacOS"
cp "$repo_root/CodexLiveWallpaper/Info.plist" "$app/Contents/Info.plist"
cp "$build_dir/CodexLiveWallpaper" "$app/Contents/MacOS/CodexLiveWallpaper"
cp "$build_dir/native-host" "$app/Contents/MacOS/native-host"
codesign --force --sign - "$app/Contents/MacOS/native-host" 2>/dev/null || true
codesign --force --sign - "$app" 2>/dev/null || true

if [[ $was_running -eq 1 ]]; then
  echo "==> 壁紙アプリを再起動"
  open -a "$app"
fi

if [[ -n "$extension_id" ]]; then
  echo "==> Native Messaging host manifest を設置"
  mkdir -p "$nm_dir"
  cat > "$nm_dir/$host_name.json" <<EOF
{
  "name": "$host_name",
  "description": "Codex Live Wallpaper bridge",
  "path": "$app/Contents/MacOS/native-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$extension_id/"]
}
EOF
  echo "    $nm_dir/$host_name.json"
else
  cat <<'EOS'

NOTE: Chrome 拡張の ID が未指定なので host manifest は設置していません。
  1. chrome://extensions を開き「パッケージ化されていない拡張機能を読み込む」で
     chrome-extension/ ディレクトリを読み込む
  2. 表示された ID をコピーして再実行:
     ./scripts/install.sh <EXTENSION_ID>
EOS
fi

echo "==> 完了"
