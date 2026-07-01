# local-live-wallpaper

macOS helper for showing a YouTube video as a desktop-level wallpaper window.

## Usage

```bash
youtube-wallpaper "https://www.youtube.com/watch?v=VIDEO_ID"
youtube-wallpaper off
```

The helper stores the current URL in:

```text
~/Library/Application Support/CodexLiveWallpaper/youtube-url.txt
```

When no YouTube URL is configured, the app falls back to its built-in animated wallpaper.
