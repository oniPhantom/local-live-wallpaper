#!/bin/zsh
set -euo pipefail

# 配布用ビルド: Developer ID 署名 + 公証 (notarize)。
#
# 事前準備:
#   1. Apple Developer Program に加入し、Developer ID Application 証明書を
#      キーチェーンに入れておく
#   2. notarytool のプロファイルを登録しておく:
#      xcrun notarytool store-credentials codex-wallpaper \
#        --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>
#
# usage:
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=codex-wallpaper \
#   ./scripts/release.sh

repo_root="${0:A:h:h}"
build_dir="$repo_root/build"
dist_dir="$repo_root/dist"
app="$dist_dir/CodexLiveWallpaper.app"

identity="${CODESIGN_IDENTITY:-}"
profile="${NOTARY_PROFILE:-}"

if [[ -z "$identity" ]]; then
  echo "error: CODESIGN_IDENTITY を設定してください (Developer ID Application 証明書)" >&2
  exit 64
fi

echo "==> Swift をビルド (release)"
mkdir -p "$build_dir" "$dist_dir"
swiftc -O "$repo_root/CodexLiveWallpaper/main.swift" -o "$build_dir/CodexLiveWallpaper"
swiftc -O "$repo_root/CodexLiveWallpaper/native-host.swift" -o "$build_dir/native-host"

echo "==> app bundle を構築"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$repo_root/CodexLiveWallpaper/Info.plist" "$app/Contents/Info.plist"
cp "$build_dir/CodexLiveWallpaper" "$app/Contents/MacOS/CodexLiveWallpaper"
cp "$build_dir/native-host" "$app/Contents/MacOS/native-host"

echo "==> Developer ID で署名 (hardened runtime)"
codesign --force --options runtime --timestamp --sign "$identity" "$app/Contents/MacOS/native-host"
codesign --force --options runtime --timestamp --sign "$identity" "$app"
codesign --verify --deep --strict "$app"

zip_path="$dist_dir/CodexLiveWallpaper.zip"
rm -f "$zip_path"
ditto -c -k --keepParent "$app" "$zip_path"

if [[ -n "$profile" ]]; then
  echo "==> 公証 (notarytool)"
  xcrun notarytool submit "$zip_path" --keychain-profile "$profile" --wait
  echo "==> staple"
  xcrun stapler staple "$app"
  rm -f "$zip_path"
  ditto -c -k --keepParent "$app" "$zip_path"
else
  echo "NOTE: NOTARY_PROFILE 未指定のため公証はスキップしました(署名のみ)"
fi

echo "==> 完了: $zip_path"
