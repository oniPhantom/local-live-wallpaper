#!/bin/zsh
set -euo pipefail

# 配布用ビルド: Developer ID 署名 + 公証 (notarize)。
#
# 事前準備:
#   1. Apple Developer Program に加入し、Developer ID Application 証明書を
#      キーチェーンに入れておく
#   2. notarytool のプロファイルを登録しておく:
#      xcrun notarytool store-credentials live-wallpaper \
#        --apple-id <APPLE_ID> --team-id <TEAM_ID> --password <APP_SPECIFIC_PASSWORD>
#
# usage:
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
#   NOTARY_PROFILE=live-wallpaper \
#   ./scripts/release.sh
#
# 署名なし(ad-hoc)で zip を作る場合は明示的にオプトインする(CI 用。
# Gatekeeper 警告が出るため配布には非推奨):
#   ALLOW_ADHOC=1 ./scripts/release.sh

repo_root="${0:A:h:h}"
build_dir="$repo_root/build"
dist_dir="$repo_root/dist"
app="$dist_dir/LiveWallpaper.app"

# xcode-select が Command Line Tools を指していると SPM が Package.swift を
# ビルドできない環境があるため、Xcode があればそちらのツールチェーンを使う
if [[ -z "${DEVELOPER_DIR:-}" && "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* \
      && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

identity="${CODESIGN_IDENTITY:-}"
profile="${NOTARY_PROFILE:-}"
allow_adhoc="${ALLOW_ADHOC:-0}"

if [[ -z "$identity" && "$allow_adhoc" != "1" ]]; then
  echo "error: CODESIGN_IDENTITY を設定してください (Developer ID Application 証明書)" >&2
  echo "hint: ad-hoc 署名で続行する場合は ALLOW_ADHOC=1 を指定 (Gatekeeper 警告あり)" >&2
  exit 64
fi

echo "==> Swift をビルド (SPM release, universal)"
mkdir -p "$build_dir" "$dist_dir"
swift build --package-path "$repo_root" -c release --arch arm64 --arch x86_64
# SPM のターゲット名にハイフンが使えないため NativeHost でビルドし、配置時に native-host へ改名する
spm_bin_dir="$(swift build --package-path "$repo_root" -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$spm_bin_dir/LiveWallpaper" "$build_dir/LiveWallpaper"
cp "$spm_bin_dir/NativeHost" "$build_dir/native-host"

echo "==> app bundle を構築"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$repo_root/Sources/LiveWallpaper/Info.plist" "$app/Contents/Info.plist"
cp "$repo_root/Sources/LiveWallpaper/icon.icns" "$app/Contents/Resources/icon.icns"
cp "$build_dir/LiveWallpaper" "$app/Contents/MacOS/LiveWallpaper"
cp "$build_dir/native-host" "$app/Contents/MacOS/native-host"

if [[ -n "$identity" ]]; then
  echo "==> Developer ID で署名 (hardened runtime)"
  codesign --force --options runtime --timestamp --sign "$identity" "$app/Contents/MacOS/native-host"
  codesign --force --options runtime --timestamp --sign "$identity" "$app"
else
  echo "==> ad-hoc 署名 (ALLOW_ADHOC=1: Developer ID なし・公証不可)"
  codesign --force --sign - "$app/Contents/MacOS/native-host"
  codesign --force --sign - "$app"
fi
codesign --verify --deep --strict "$app"

zip_path="$dist_dir/LiveWallpaper.zip"
rm -f "$zip_path"
ditto -c -k --keepParent "$app" "$zip_path"

if [[ -n "$profile" && -z "$identity" ]]; then
  echo "NOTE: ad-hoc 署名のため公証はスキップしました (Developer ID 署名が必要)"
elif [[ -n "$profile" ]]; then
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
