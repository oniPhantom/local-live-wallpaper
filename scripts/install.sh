#!/bin/zsh
set -euo pipefail

# LiveWallpaper.app と Native Messaging host をビルド・インストールする。
# usage:
#   ./scripts/install.sh                # 固定 ID で host manifest も設置
#   ./scripts/install.sh <EXTENSION_ID> # ID を上書きしたい場合のみ指定

repo_root="${0:A:h:h}"
app="/Applications/LiveWallpaper.app"
app_executable="$app/Contents/MacOS/LiveWallpaper"
build_dir="$repo_root/build"
host_name="com.local.livewallpaper"
nm_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"

# manifest.json の "key" から導出される固定 ID(フォルダを移動しても変わらない)
default_extension_id="gapcbmiahdgeennnieipbddmhpmnhhgg"
extension_id="${1:-$default_extension_id}"

echo "==> Swift をビルド"
mkdir -p "$build_dir"
swiftc -O "$repo_root/LiveWallpaper/native-host.swift" -o "$build_dir/native-host"
swiftc -O "$repo_root/LiveWallpaper/main.swift" -o "$build_dir/LiveWallpaper"

echo "==> $app へインストール"
was_running=0
if pkill -x LiveWallpaper 2>/dev/null; then
  was_running=1
fi
if pkill -f "caffeinate.*LiveWallpaper" 2>/dev/null; then
  was_running=1
fi
if [[ $was_running -eq 1 ]]; then
  sleep 1
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$repo_root/LiveWallpaper/Info.plist" "$app/Contents/Info.plist"
cp "$repo_root/LiveWallpaper/icon.icns" "$app/Contents/Resources/icon.icns"
cp "$build_dir/LiveWallpaper" "$app/Contents/MacOS/LiveWallpaper"
cp "$build_dir/native-host" "$app/Contents/MacOS/native-host"
codesign --force --sign - "$app/Contents/MacOS/native-host" 2>/dev/null || true
codesign --force --sign - "$app" 2>/dev/null || true

if [[ $was_running -eq 1 ]]; then
  echo "==> 壁紙アプリを再起動"
  nohup caffeinate -dimsu "$app_executable" >/dev/null 2>&1 &
fi

echo "==> Native Messaging host manifest を設置 (extension: $extension_id)"
mkdir -p "$nm_dir"
cat > "$nm_dir/$host_name.json" <<EOF
{
  "name": "$host_name",
  "description": "Live Wallpaper bridge",
  "path": "$app/Contents/MacOS/native-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://$extension_id/"]
}
EOF
echo "    $nm_dir/$host_name.json"

echo "==> 完了"
