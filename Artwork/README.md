# AppWink icon artwork

`AppWink-Icon-Source.png` is the full-bleed artwork master for the cobalt-blue
winking keycap icon. The taller keycap preserves AppWink's application-hotkey
focus and the Chinese slogan “应用，眨眼即达”.

The artwork was created and refined for AppWink using the built-in imagegen
tool. The final source prompt is in [icon-source-prompt.txt](icon-source-prompt.txt).
This artwork is distributed under the repository's GPL-3.0-or-later license.

Run `swift Scripts/generate_brand_assets.swift` from the repository to regenerate
the ten `Icon.iconset` PNGs. The exporter applies the clean rounded outline,
transparent padding, sRGB color space and exact pixel dimensions; keep the
master square, opaque and at least 1024 pixels. Packaging regenerates the icons
and converts them to the ignored `Icon.icns` automatically.
