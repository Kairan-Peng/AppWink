# AppWink

[简体中文](README.md) | English

AppWink is a free, open-source macOS utility that helps people coming from Windows feel more at home in everyday use.

It offers shortcuts for apps, folders, and files, along with practical tools for displaying keystrokes, adjusting mouse scrolling, working with Finder, managing menu bar icons, and monitoring network speed. The current source requires no purchase, trial, activation, or sign-in.

> Latest release: [0.1.45](https://github.com/Kairan-Peng/AppWink/releases/tag/v0.1.45). [Download universal DMG](https://github.com/Kairan-Peng/AppWink/releases/download/v0.1.45/AppWink-v0.1.45-build46-mac.dmg) · [SHA-256](https://github.com/Kairan-Peng/AppWink/releases/download/v0.1.45/AppWink-v0.1.45-build46-mac.dmg.sha256)

## Features

- Assign global shortcuts to individual apps, folders, and files, using the default `⌥ + letter/number` combinations or optional advanced combinations.
- Bring an app to the foreground, or hide it when triggered again while its normal window is in front; preserve system behavior for full-screen and Split View windows.
- Open folders and files with the system default or an app you choose, with access saved through local bookmarks.
- Hold Option to show a virtual keyboard; optionally display pressed keys and hotkey icon hints.
- Windows-style mouse scrolling, Finder Cut, menu bar icon hiding, and network speed display.
- Chinese and English, system/light/dark appearance, launch at login, and Sparkle automatic updates.

AppWink has a focused hotkey configuration window and a separate Settings window.

## System requirements and installation

- macOS 14.0 or later.
- Official universal installers support Apple Silicon and Intel, with Developer ID signing, Apple notarization, and automatic updates.
- Releases are distributed through [GitHub Releases](https://github.com/Kairan-Peng/AppWink/releases). No App Store version is provided.
- Download the latest `.dmg`, drag AppWink into Applications, and launch it from there. GitHub's Source code ZIP contains the source code.

Some features need macOS Accessibility permission. Opening folders and files does not require Accessibility or Finder Automation; macOS may ask separately for file access when you open protected locations. Follow the app's prompts to grant permissions in System Settings.

Existing users' shortcuts, opening preferences, ordering, language, appearance, and feature switches remain stored locally. Old commercial license caches no longer affect features, and reactivation is not required. Keep a backup of your local configuration before upgrading, and check Accessibility and Login Items afterward.

## Building from source

You need a macOS development toolchain supporting Swift 6.2 or later, along with the command-line tools. The first build needs internet access to download the public Sparkle dependency. Local builds do not need a license from the maintainer, signing certificates, or server configuration.

```bash
swift build
swift test
```

To create a locally runnable app with an ad hoc signature:

```bash
SIGNING_MODE=adhoc ./Scripts/package_app.sh release
```

Then open the generated `AppWink.app`. Official distribution requires Developer ID and notarization configuration; see the [development and release guide](docs/PUBLIC_GUIDE.md). A separate QA app for permission testing should use its own name and bundle/data domains to avoid changing an existing installation or configuration.

If the public Sparkle download stalls on your machine, use the repository's local cache preparation script:

```bash
./Scripts/prepare_local_sparkle_artifact.sh
APPWINK_USE_LOCAL_SPARKLE_ARTIFACT=1 swift build
```

## Feedback and contributions

Please share problems and suggestions through [Issues](https://github.com/Kairan-Peng/AppWink/issues), or submit improvements following the [contributing guide](CONTRIBUTING.md). Include your macOS and app versions and steps to reproduce the issue, and hide private information in screenshots. For security issues, follow the [security reporting instructions](SECURITY.md).

This is a project maintained by one person, so updates will come at a pace that fits around work and life.

## License and third-party notices

Copyright (C) 2026 Kairan Peng.

AppWink is licensed under the **GNU General Public License v3.0 or later** (`GPL-3.0-or-later`). You may use, study, modify, and redistribute it under the license, including for commercial purposes. When distributing modified versions, you must comply with the GPL's source code and licensing requirements. The software is provided as is, without warranty.

See [LICENSE](LICENSE) for the full terms and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for dependency and resource notices. Sparkle and its components retain their own license and copyright notices. The app does not include commercial license verification.

The [project documentation](docs/PUBLIC_GUIDE.md) covers the architecture, local verification, and release process.
