# Live Wallpaper

[![CI](https://github.com/oniPhantom/local-live-wallpaper/actions/workflows/ci.yml/badge.svg)](https://github.com/oniPhantom/local-live-wallpaper/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/oniPhantom/local-live-wallpaper)](https://github.com/oniPhantom/local-live-wallpaper/releases/latest)

[日本語](README.md) | English

A tool that plays YouTube videos and playlists as your macOS desktop wallpaper.
Control it from the Chrome extension's "Set as wallpaper" button, the menu bar, or the on-desktop control panel.

- 🖥 Plays the YouTube watch page as-is (no ads when signed in with Premium)
- 🖱 One-click wallpaper from any YouTube page in Chrome (playlists supported)
- 🎛 Control panel: play by URL, pick playlists from your signed-in account, sign in, play/pause, skip forward/back, volume, seek, quality, restore normal wallpaper, time display (draggable)
- 🎞 Local video files (mp4 / mov / m4v) loop as wallpaper too (no YouTube dependency, works offline)
- 🔋 Auto-pauses while the screen is locked, fully covered, on battery power, or in Low Power Mode
- 🛟 Falls back to a built-in animated wallpaper on playback failure and retries automatically

> ⚠️ This tool is intended for personal use. It modifies how the YouTube page
> is displayed to show only the video, so use it at your own risk.

> 🌐 The app UI (menu bar, control panel, Chrome extension) is currently Japanese-only.
> The menu/button names in this README are unofficial English translations.

## Requirements

- macOS 13 or later (Apple Silicon / Intel)
- Xcode Command Line Tools (`xcode-select --install`)
- Google Chrome (if you want to control it from the extension)

> ⚠️ If `swift build` / `swift test` fails with `Invalid manifest`, the SPM that ships
> with your Command Line Tools is broken. If Xcode is installed, switch with
> `sudo xcode-select -s /Applications/Xcode.app`
> (`install.sh` / `release.sh` / `make test` automatically fall back to Xcode when present).

## Quick Install (one command)

```bash
/bin/zsh -c "$(curl -fsSL https://raw.githubusercontent.com/oniPhantom/local-live-wallpaper/main/scripts/bootstrap.sh)"
```

This clones the repo to `~/local-live-wallpaper` and builds and installs it automatically.
**Because it builds on your own Mac, no code signing or notarization (Apple Developer Program) is required.**

## Install with Homebrew

You can also install the prebuilt zip from GitHub Releases via Homebrew Cask
(available once the tap and a release are published; see [docs/RELEASING.md](docs/RELEASING.md)):

```bash
brew tap oniPhantom/tap
brew install --cask live-wallpaper
```

If the release zip is not signed and notarized, Gatekeeper will warn on first
launch; in that case the local build above is recommended.

## Manual Setup

```bash
git clone https://github.com/oniPhantom/local-live-wallpaper.git
cd local-live-wallpaper

# Build and install to /Applications (also sets up the Native Messaging host)
make install
```

Load the Chrome extension (if you want to control it from the extension):

1. Open `chrome://extensions` and turn on "Developer mode" in the top right
2. Click "Load unpacked" and select the `chrome-extension/` folder
   (the extension ID is pinned by the `key` in the manifest, so no extra setup is needed)

Sign in to YouTube (recommended — removes ads):

1. Click the ▶ icon in the menu bar → "Sign in to YouTube…"
2. Sign in in the window that opens (Cmd+C / Cmd+V work) and close it

## Usage

- **From Chrome**: the "🖥 Set as wallpaper" button in the bottom right of YouTube
  video/playlist pages, or the extension icon's popup in the toolbar
- **Menu bar**: playback controls, panel visibility, monitor settings, display mode,
  sign-in (with sign-in status display), and a launch-at-login toggle
- **Global hotkey**: ⌃⌥P toggles play/pause (works even while other apps are focused)
- **Control panel** (bottom left of the desktop, draggable): play/pause, previous/next,
  direct URL input, playlist selection from your signed-in account, sign-in, volume, seek, quality, current/total time, restore normal wallpaper
- **Local videos**: enter an mp4 / mov / m4v path (`~/Movies/loop.mp4` or a `file://` URL)
  in the panel's URL field or on the CLI to loop a local file
- **CLI**:

```bash
make play
make play 'https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID'
make play URL="~/Movies/loop.mp4"   # URL= form and local video files work too
make off

# You can also call the CLI directly
./youtube-wallpaper 'https://www.youtube.com/watch?v=VIDEO_ID&list=PLAYLIST_ID'
```

> 💡 Always quote URLs containing `&` or `?` (they are otherwise interpreted by the shell).

## Uninstall

```bash
make uninstall                         # remove everything (including settings and login data)
./scripts/uninstall.sh --keep-settings # keep settings
```

Remove the Chrome extension manually from chrome://extensions.

## Display and Behavior Settings

| Menu bar item | Description |
|---|---|
| Largest monitor only | Smaller monitors keep their normal desktop instead of the wallpaper |
| Crop to fill screen | OFF (default) = show the whole video (FullHD fits vertically with black bars) / ON = crop to fill the screen |
| Show control panel | Toggle the panel's visibility |
| Launch at login | Automatically start the app at login (registered/unregistered via `SMAppService`) |
| Clear login data | Wipe all WebKit cookies (also resets a stuck bot check) |

## Command Reference (Native Messaging)

Besides the extension, you can control the app by sending JSON with a 4-byte
length prefix to `/Applications/LiveWallpaper.app/Contents/MacOS/native-host`.

```jsonc
{ "type": "play", "url": "https://www.youtube.com/watch?v=...", "videoIds": ["id1", "id2"] }
{ "type": "off" }
{ "type": "pause" }      // toggle play / pause
{ "type": "next" }
{ "type": "previous" }
{ "type": "seek", "percent": 0.42 }
{ "type": "volume", "value": 35 }
{ "type": "subtitles", "enabled": false }
{ "type": "screens", "largestOnly": true }
{ "type": "quality", "value": "hd1080" }    // auto/small/medium/large/hd720/hd1080/hd1440/hd2160
{ "type": "status" }                        // returns the current state
{ "type": "login" }                         // opens the sign-in window
```

## How It Works

- The macOS app shows the YouTube watch page in a WKWebView inside a
  desktop-level window and injects CSS/JS to hide the page UI, leaving only the video
- The actual rendered position of the video is read every second, and the WKWebView's
  layer transform fits it to the screen
- Local video files (mp4 / mov / m4v) are looped with `AVPlayerLayer`
  (no YouTube dependency, works offline)
- Chrome extension → Native Messaging host → Distributed Notification controls the app
- All settings live as plain files in `~/Library/Application Support/LiveWallpaper/`

## Known Limitations

- When not signed in, YouTube may flag playback as bot traffic
  (the automatic fallback and retry wait for recovery; signing in almost entirely avoids it)
- Videos that cannot be watched — non-embeddable videos, unlisted-recording live streams, etc. — cannot be played
- The control panel's playlist picker shows up to **50** saved playlists from the signed-in account
- Continuously decoding full-screen video uses a fair amount of power
  (auto-pauses on battery by default)

## Distribution Build (for developers)

Distributing to other Macs requires Developer ID signing and notarization:

```bash
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_PROFILE=your-profile \
./scripts/release.sh   # produces a universal binary (arm64 + x86_64) in dist/
```

## Contributing

Bug reports, feature requests, and PRs are welcome — see the
[contributing guide](CONTRIBUTING.en.md). Participants are expected to follow
the [code of conduct](CODE_OF_CONDUCT.en.md). For vulnerabilities, see the
[security policy](SECURITY.en.md).

## License

[MIT](LICENSE) / [Privacy Policy](docs/PRIVACY.md)
