# Homebrew Cask 定義。oniPhantom/homebrew-tap の Casks/ に置いて公開する
# (手順は docs/RELEASING.md)。
#
# リリースごとに version と sha256 を更新すること:
#   shasum -a 256 LiveWallpaper-<version>.zip
cask "live-wallpaper" do
  version "0.2.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000" # PLACEHOLDER: リリース後に実際の値へ置き換える

  url "https://github.com/oniPhantom/local-live-wallpaper/releases/download/v#{version}/LiveWallpaper-#{version}.zip"
  name "Live Wallpaper"
  desc "Play YouTube videos and local video files as your macOS desktop wallpaper"
  homepage "https://github.com/oniPhantom/local-live-wallpaper"

  depends_on macos: ">= :ventura"

  app "LiveWallpaper.app"

  # Chrome 拡張から操作するための Native Messaging host manifest を設置する
  # (scripts/install.sh と同等の設定。拡張 ID は manifest.json の "key" で固定)
  postflight do
    extension_id = "gapcbmiahdgeennnieipbddmhpmnhhgg"
    nm_dir = File.expand_path("~/Library/Application Support/Google/Chrome/NativeMessagingHosts")
    FileUtils.mkdir_p(nm_dir)
    File.write(File.join(nm_dir, "com.local.livewallpaper.json"), <<~JSON)
      {
        "name": "com.local.livewallpaper",
        "description": "Live Wallpaper bridge",
        "path": "/Applications/LiveWallpaper.app/Contents/MacOS/native-host",
        "type": "stdio",
        "allowed_origins": ["chrome-extension://#{extension_id}/"]
      }
    JSON
  end

  zap trash: [
    "~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.local.livewallpaper.json",
    "~/Library/Application Support/LiveWallpaper",
    "~/Library/Logs/LiveWallpaper",
  ]

  caveats <<~EOS
    Chrome 拡張から操作する場合:
      - Native Messaging host の manifest は postflight で
        ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/ に設置済みです
      - Chrome 拡張自体は chrome://extensions でデベロッパーモードを ON にし、
        リポジトリの chrome-extension/ フォルダを読み込んでください(README 参照)
      - 設置に失敗した場合はリポジトリを clone して ./scripts/install.sh を実行すると
        同じ設定を再適用できます

    リリース zip が ad-hoc 署名(公証なし)の場合、初回起動時に Gatekeeper の
    警告が出ます。その場合はローカルビルド(scripts/bootstrap.sh)を推奨します。
  EOS
end
