# Contributing to AppWink

AppWink uses GPL-3.0-or-later. Contributions are distributed under the same
license; include the source and notices for any third-party material you add.

## Development

Use macOS 14 or later with a toolchain supporting Swift 6.2 or later.

```bash
swift build
swift test
python3 Tests/ReleaseToolingTests/test_release_ref.py
SIGNING_MODE=adhoc ./Scripts/package_app.sh release
```

Normal local builds need no private service or maintainer certificate. First
builds download the public Sparkle dependency. The release-tooling tests use
Python 3's standard library and disposable repositories. See the
[development guide](docs/PUBLIC_GUIDE.md) for packaging and runtime checks.

Keep changes focused and preserve the existing shortcut/configuration format.
AppWink has a focused hotkey window and an independent Settings window.

## Reports and pull requests

For bugs, include AppWink/macOS versions, reproduction steps, expected/actual
behavior, and relevant redacted logs or screenshots. Avoid real secrets,
private file paths, or personal content. Feature requests should explain the
workflow they would improve.

Describe the concrete behavior changed and the checks you ran. UI changes
should include screenshots. Permission, input, Finder, Spaces and signing
behavior often need manual verification; state what remains unverified.

Update the relevant user and developer documentation. Follow
AGENTS.md; never commit or publish signing material. Public contributor CI must
not require or receive release signing secrets.

The maintainer reviews changes as time permits. Suggestions and contributions
are welcome; no fixed delivery schedule is promised.
