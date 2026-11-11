# AppWink development and release guide

AppWink is a SwiftUI/AppKit macOS utility, licensed under GPL-3.0-or-later.
The app has no commercial activation service. macOS permissions, Developer ID
signing, Apple notarization and Sparkle signatures remain security boundaries.

## Architecture and requirements

- `Sources/AppWinkCore`: configuration, targets, shortcuts, persistence and localization.
- `Sources/AppWink`: shared runtime, AppModel, controllers, services and views.
- `Sources/AppWinkDirect`: the AppWink executable and Sparkle driver.
- `Tests/AppWinkCoreTests` / `Tests/AppWinkTests`: model and runtime regression tests.
- `Tests/ReleaseToolingTests`: trusted release-ref checks using Python 3's standard library and disposable Git repositories.
- `Scripts`: packaging, notarization, release notes and update-feed tools.

Use macOS with a toolchain supporting Swift 6.2 or newer. Deployment targets
macOS 14.0 and later. Sparkle 2.9.1 is the only external package and is pinned to
the version whose complete notices are included in the source and app bundle.

```bash
swift build
swift test
python3 Tests/ReleaseToolingTests/test_release_ref.py
SIGNING_MODE=adhoc ./Scripts/package_app.sh release
```

Packaging without an architecture list builds for the host. Formal release
scripts build universal arm64/x86_64. The package uses actual SwiftPM scratch
outputs; do not copy a guessed old binary into a new app bundle.

## Application icon

The application icon uses the cobalt-blue winking keycap design. Its source
master is `Artwork/AppWink-Icon-Source.png`; keep it square, opaque/full bleed
and at least 1024 pixels. The exporter adds the rounded outline and transparent
padding consistently at every size, avoiding generated cutout noise.
Regenerate the ten standard iconset images with:

```bash
swift Scripts/generate_brand_assets.swift
iconutil --convert icns --output Icon.icns Icon.iconset
```

Packaging runs the generator and embeds the resulting `Icon.icns` automatically.
The exporter uses exact pixel dimensions independently of the display's Retina
scale. `Icon.icns` remains an ignored build artifact. Preview 16/32/64-pixel
images and inspect an isolated app bundle after changing the master. The menu
bar's monochrome template icon is maintained separately in
`StatusBarIconProvider.swift`.

## Runtime checks

Use a separately named/bundled QA app and preseed its configuration. The
preserved migration from an old MyTool preference domain can otherwise populate
an apparently fresh QA identity. Never clear a user's defaults or keychain.

Check fresh and legacy settings, ordered bindings/bookmarks, recorder isolation,
conflicts, app activate/hide, native folder/file opens, real permission
denial/recovery, virtual/pressed keyboard, mouse/Finder helpers, Hidden Bar and
network monitor. Test relevant Spaces/fullscreen, sleep and hardware behavior.
Report which checks used injected actions and which used actual system input.

For window chrome changes, check both the hotkey and Settings windows after
initial launch, close/reopen, resizing and Settings detail/back navigation in
light and dark appearances. Native close/minimize/zoom controls, window titles
and help/back accessories must remain above the full-size SwiftUI content.
Keep native fullscreen titlebar behavior intact. Screen-capture indicators may
temporarily replace the traffic-light glyphs while a window is being captured.

Privileged features retain Accessibility checks. Folder/file opens do not need
Finder Automation. Login-item controls reflect real macOS state. The package
does not request Apple Events or audio capture permission. The privacy manifest
declares the legacy UserDefaults usage.

## Contributor CI and release trust

PR/main CI builds, tests and packages ad hoc without release secrets. Actions
are pinned, checkout does not persist credentials, and normal jobs have read
permissions. Only the draft-creation job has repository content-write access.

The release workflow is manually dispatched from main by the personal
repository owner. It resolves an existing canonical version tag and only accepts
source commits reachable from main. Explicit main/SHA replays never create a
release. It reads version metadata as data, verifies real environment protection,
and only then allows access to step-scoped signing credentials.

Before enabling release automation, configure `release-signing` and
`release-draft` environments for the exact owner User reviewer, owner approval
and an exact main-only deployment branch policy. Store Apple/certificate
secrets only in release-signing. A missing or incorrect policy causes preflight
to fail; declaring an environment alone does not protect secrets. An organization
transfer requires an explicit maintainer-policy review.

Protect main and release tags from unintended changes. Review rules again after
changing repository visibility. Opening source does not authorize publishing a
binary or changing a signed update feed.

## Signed candidate and updates

Use a Developer ID Application certificate and an existing notarytool profile.
Keep signing material out of source, artifacts, logs and support reports.

```bash
APP_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
NOTARY_KEYCHAIN_PROFILE="appwink-notary" \
SPARKLE_FEED_URL="https://kairan-peng.github.io/appwink-updates/appcast.xml" \
SPARKLE_PUBLIC_ED_KEY="<existing public update key>" \
./Scripts/notarize_app.sh --package-format zip
```

The ZIP path above notarizes and staples the app. Create a DMG from that stapled
app, then explicitly sign its container with Developer ID and a timestamp before
submitting the DMG for notarization. Staple the final DMG, recompute its checksum
and update signature, then mount it and independently verify the app inside with
stapler, codesign and Gatekeeper. The existing DMG helper/release workflow does
not automate that container-signing step; complete it before enabling that path.
Verify both architectures, metadata, minimal entitlements, SHA-256 and source
correspondence. Include LICENSE, complete third-party notices and corresponding
source/build instructions when distributing the binary.

Keep the existing Sparkle feed URL and public key for installed users. Archive
EdDSA signatures and Apple Developer ID signatures serve different purposes.
Never remove update authenticity checks when simplifying the product.

The workflow requires an existing tag, creates a new draft only, refuses
existing releases and never overwrites assets. Public
Release promotion and appcast publication require a separate deliberate step.
The feed is staged with `export_release_notes.sh` and `publish_update_feed.sh`;
do not run feed publication during private candidate testing.

## Rollback and incident handling

Keep the previous signed app, exact candidate checksum/source manifest and a
configuration backup before upgrade testing. Configuration is not destructively
migrated. Restore the previous app and confirm targets/preferences if an upgrade
fails. Never overwrite an existing public installer to change its behavior.

If a newly published update is faulty, stop advertising it, preserve the bad
artifact for investigation and prepare a corrected higher build. Sparkle version
ordering does not make a lower build a normal rollback update. Check launch
failures, updater signature/download errors, configuration preservation,
Accessibility and Login Items immediately after a release. Keep any legacy
service operational until affected users have a working free upgrade path.

Report security problems following [SECURITY.md](../SECURITY.md). Review the
[license](../LICENSE), [third-party notices](../THIRD_PARTY_NOTICES.md) and
[release notes](releases/v0.1.46.md) before distribution.
