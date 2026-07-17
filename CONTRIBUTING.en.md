# Contributing Guide

[日本語](CONTRIBUTING.md) | English

Thank you for your interest in contributing to Live Wallpaper.
Bug reports, feature requests, and pull requests are all welcome.

## Development environment

- macOS 13 or later (Apple Silicon / Intel)
- Swift 5.9 or later (Xcode Command Line Tools or Xcode)
- SwiftLint (`brew install swiftlint`)

> ⚠️ If `swift build` / `swift test` fails with `Invalid manifest`, see the
> [note in the README](README.en.md#requirements)
> (`make test` automatically falls back to the Xcode toolchain if available).

## Setup and verification

```bash
git clone git@github.com:oniPhantom/local-live-wallpaper.git
cd local-live-wallpaper
swift build   # build
make test     # unit tests
make lint     # SwiftLint
```

To try it end to end, run `make install` to build and install, then
`make play URL=<YouTube URL>` to play a wallpaper (`make uninstall` to remove).

## Directory layout

| Path | Role |
|---|---|
| `Sources/LiveWallpaperCore/` | Pure logic with no AppKit dependency (URL parsing, source detection, etc.). Covered by tests |
| `Sources/LiveWallpaper/` | The app itself (AppKit / WKWebView / AVPlayerLayer) |
| `Sources/NativeHost/` | Chrome Native Messaging host |
| `chrome-extension/` | Chrome extension |
| `Tests/LiveWallpaperCoreTests/` | Unit tests |
| `scripts/` | Install / release scripts |

Put new logic in `LiveWallpaperCore` whenever possible and add unit tests for it.

## Pull requests

1. Create a branch off `main`
2. Make your changes and confirm `make test` and `make lint` pass
3. Add user-facing changes to the `[Unreleased]` section of `CHANGELOG.md`
4. Open a PR (CI must pass)

## Bug reports and feature requests

Please use [GitHub Issues](https://github.com/oniPhantom/local-live-wallpaper/issues).
For bug reports, include your macOS version, steps to reproduce, and expected behavior.

For security vulnerabilities, do not use Issues — follow the process in [SECURITY.md](SECURITY.en.md).

## Releases

For release work (maintainers), see [docs/RELEASING.md](docs/RELEASING.md).

## Code of conduct

This project has a [code of conduct](CODE_OF_CONDUCT.en.md). All participants are expected to follow it.
