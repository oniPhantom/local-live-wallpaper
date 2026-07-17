# Security Policy

[日本語](SECURITY.md) | English

## Supported versions

Security fixes are provided only for the latest release.

| Version | Supported |
|---|---|
| Latest release (1.x) | ✅ |
| Older | ❌ |

## Reporting a vulnerability

If you find a vulnerability, **do not open a public issue**.

Please report it privately via GitHub's
[Private vulnerability reporting](https://github.com/oniPhantom/local-live-wallpaper/security/advisories/new).
Including the following helps a lot:

- Affected version
- Steps to reproduce or a PoC
- Expected impact

Reports will be acknowledged within a few days, with a reply on whether and how
it will be fixed. Please refrain from public disclosure until a fix is released.

## Scope

The app runs locally and sends no usage data to external servers
(see [docs/PRIVACY.md](docs/PRIVACY.md)). Since it displays YouTube through a
WKWebView, issues originating from YouTube-side content are out of scope.
