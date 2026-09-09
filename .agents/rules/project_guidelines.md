# NotchPulse Project Guidelines & Memory Rules

This document outlines the core rules, architectural guidelines, and release procedures for the NotchPulse project. All AI agents working on this codebase MUST read and strictly adhere to these instructions.

> **CRITICAL RULE FOR ALL AGENTS:** Always refer to and enforce `.agents/rules/project_guidelines.md` before releasing or committing.

---

## 1. Commit Messages & Release Notes Guidelines (MANDATORY)
- **Descriptive Commit Messages:** When committing code, ALWAYS provide a concise, itemized description of the specific changes and fixes. NEVER use generic messages like "update code" or "fix bug".
- **English Release Notes (`RELEASE_NOTES.md`):** For every new release, update `RELEASE_NOTES.md` in the repository root ENTIRELY IN ENGLISH. Focus on the actual changes in the specific version (`🚀 What's New`, `🐛 Bug Fixes`, `⚡ Improvements`). NEVER let GitHub Releases display raw automated single commits such as `- chore: Update appcast.xml for release`.

---

## 2. Release Workflow, Version Synchronization & In-App Auto-Update
- **Strict Version Synchronization (REQUIRED for Sparkle Auto-Update):** Before publishing any release, verify and synchronize the exact version number across all required configuration files:
  - `NotchPulse.xcodeproj/project.pbxproj` (`CURRENT_PROJECT_VERSION` & `MARKETING_VERSION`)
  - `appcast.xml` (Sparkle update feed XML — update `<sparkle:version>` and `<sparkle:shortVersionString>`)
  - GitHub Tag & Release (e.g., `v3.1.5`)
  - `RELEASE_NOTES.md` (English release description)
- **Sparkle Auto-Update & Code Signing for DMG:**
  - `NotchPulse.entitlements` must maintain `com.apple.security.app-sandbox = false` for direct non-Mac App Store distribution so Sparkle's `Autoupdate.app` helper can properly replace the existing app binary in `/Applications`.
  - In `build-dmg.yml`, sign frameworks using the inside-out pattern without passing the parent app entitlements flag `--entitlements` to `--deep`, ensuring `Sparkle.framework` code signature integrity is preserved.

---

## 3. Layout Standards & Multi-Monitor Support
- **Percentage-Based Sizing:** Use dynamic, screen-relative dimensions rather than rigid hardcoded pixel values for responsive UI components (Lyrics, Media View).
- **Display Awareness:**
  - Built-in MacBook Display: Dynamically adapt UI around the camera Notch geometry.
  - External Displays: Render standard flat designs centered symmetrically without Notch offsets.
- **Micro-Animations & Text Flow:** When expanding or shrinking media views, apply subtle scaling (1–2px) to prevent layout shifts or premature line breaks in lyrics.

---

## 4. Lock Screen & FaceID Window
- When returning to the Lock Screen during an active session: Prioritize hover-to-wake / hover-to-authenticate for Face ID rather than requiring a button click.
- **Lyrics Behavior on Lock Screen:**
  - Upon track change, immediately reset and scroll lyrics to the beginning of the song (line 0 / top) without waiting for the first lyric timestamp.
  - When expanding from compact media view to full-screen lyrics, immediately illuminate and center the currently active lyric line without waiting for the next line's timestamp.
