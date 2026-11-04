# AppWink Agent Guide

AppWink is a SwiftPM macOS utility under GPL-3.0-or-later. Keep changes focused
and preserve the existing app/folder/file hotkey behavior and configuration.

- Read README, CONTRIBUTING and docs/PUBLIC_GUIDE.md before substantial work.
- Inspect git status and preserve unrelated edits; do not commit, push or publish
  unless the user asks. Never publish signing material or change update trust.
- Use four-space Swift indentation and the existing Core/Runtime/Direct split.
- Run focused checks, swift build and relevant tests. Keep permissions, file
  bookmarks, user intent and updater signature checks independent of features.
- Use an isolated QA bundle/defaults domain for runtime testing, preseeded to
  avoid legacy MyTool import. Do not overwrite the user's production app/data.
- Update applicable user/developer docs and report actual verification limits.
