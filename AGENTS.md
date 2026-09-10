# NotchPulse Agent Instructions & Release Guidelines

> **IMPORTANT:** Always refer to and enforce `.agents/rules/project_guidelines.md` before releasing or committing.

Whenever working on NotchPulse or executing releases, ALWAYS follow these instructions:

## 1. Mandatory English Release Notes Format
- Every release **MUST** write/update `RELEASE_NOTES.md` at the repository root in **English**.
- **Only include sections that actually have changes** in that specific release (e.g. `🚀 What's New`, `🔒 Face ID Improvements`, `🐛 Bug Fixes`, `⚡ Performance`, etc.). Do **NOT** list empty or unchanged categories just to fill template headers.
- **NEVER** publish a GitHub Release that displays raw commit logs like `- chore: Update appcast.xml for release`.

## 2. In-App Auto-Update & Versioning (Sparkle)
- Synchronize versions across:
  - `NotchPulse.xcodeproj/project.pbxproj` (`MARKETING_VERSION` & `CURRENT_PROJECT_VERSION`)
  - `appcast.xml` (`<sparkle:version>` & `<sparkle:shortVersionString>`)
  - GitHub Tag (`vX.Y.Z`)
  - `RELEASE_NOTES.md`
- `NotchPulse.entitlements`: Keep `com.apple.security.app-sandbox` set to `false` for direct web distribution so Sparkle `Autoupdate.app` can overwrite `/Applications/NotchPulse.app`.
- In `build-dmg.yml`: Sign frameworks inside-out without passing main app entitlements to `--deep`.
