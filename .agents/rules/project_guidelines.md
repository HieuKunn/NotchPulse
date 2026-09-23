# NotchPulse Project Guidelines & Memory Rules

This document outlines the core rules, architectural guidelines, and release procedures for the NotchPulse project. All AI agents working on this codebase MUST read and strictly adhere to these instructions.

> **CRITICAL RULE FOR ALL AGENTS:** Always refer to and enforce `.agents/rules/project_guidelines.md` before releasing or committing.

---

## 1. Commit Messages & Release Notes Guidelines (MANDATORY)
- **Descriptive Commit Messages:** When committing code, ALWAYS provide a concise, itemized description of the specific changes and fixes. NEVER use generic messages like "update code" or "fix bug".
- **English Release Notes (`RELEASE_NOTES.md`):**
  - **Single Latest Version Only (REQUIRED):** `RELEASE_NOTES.md` must ONLY contain the notes for the single newest release being published. Do NOT keep or append past version notes in this file; each release completely replaces `RELEASE_NOTES.md` with only the latest release section.
  - **User-Centric, Plain English (REQUIRED):** Write release notes for end-users downloading the app, NOT for developers. Explain changes and features in simple, clear, intuitive language focusing on user benefits and visible improvements.
  - **NO Developer/Academic Jargon:** DO NOT use internal programming terms, framework names, error codes, or technical constants (e.g. avoid `EX_CONFIG 78`, `SMAppService`, `launchd plists`, `SMCComm`, `512D vector embeddings`, `XPC client protocol`, `SkyLight delegation`, etc.).
  - **Relevant Sections Only:** Only include categories/sections that actually changed in that version (e.g. `🚀 What's New`, `🔋 Smart Charging`, `🔒 Face ID`, `🎵 Music & Lyrics`, `🐛 Bug Fixes`). Do NOT include boilerplate, empty, or unchanged categories.
  - **NO Raw Commit Dumps:** NEVER let GitHub Releases display raw automated single commits like `- chore: Update appcast.xml for release`.

---

## 2. Release Workflow, Version Synchronization & In-App Auto-Update
- **Strict Version Synchronization (REQUIRED for Sparkle Auto-Update):** Before publishing any release, verify and synchronize the exact version number across all required configuration files:
  - `NotchPulse.xcodeproj/project.pbxproj` (`CURRENT_PROJECT_VERSION` & `MARKETING_VERSION`)
  - **Internal/Iterative Builds:** If pushing a hotfix or internal build without changing the marketing version (e.g. keeping it at 3.9.5), you MUST increment the `CURRENT_PROJECT_VERSION` (build number) in the `.pbxproj` file. Otherwise, the Sparkle in-app updater will not detect the update for users who already installed the previous build of that version.
  - `appcast.xml` (Sparkle update feed XML — update `<sparkle:version>` and `<sparkle:shortVersionString>`)
  - GitHub Tag & Release (e.g., `v3.1.5`)
  - `RELEASE_NOTES.md` (User-friendly English release description)
- **Sparkle Auto-Update & Code Signing for DMG:**
  - `NotchPulse.entitlements` must maintain `com.apple.security.app-sandbox = false` for direct non-Mac App Store distribution so Sparkle's `Autoupdate.app` helper can properly replace the existing app binary in `/Applications`.
  - In `build-dmg.yml`, sign frameworks using the inside-out pattern without passing the parent app entitlements flag `--entitlements` to `--deep`, ensuring `Sparkle.framework` code signature integrity is preserved.
- **Dynamic Release Name (Settings UI):**
  - Do NOT hardcode the "Release name" in `Constants.swift` or `UserDefaults`. It is now computed dynamically from the app version via `Bundle.main.releaseNameString` in `BundleInfos.swift` (e.g., automatically generating "Pulse 4.0 🚀" from version 4.0.0). Always rely on this dynamic property.

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

---

## 5. Code Removal & Refactoring (Pre-Release Checks)
- **Verify Dangling References (REQUIRED):** When removing features, deprecating modules, or modifying core structures, you MUST perform a deep `grep_search` across the entire codebase (`*.swift`) for any related symbols, variables, or enum cases.
- **Do Not Rely Only on Project File Cleanup:** Removing source files from `project.pbxproj` is not enough. You must proactively find and delete dangling references in other components (e.g., `@ObservedObject` references, dead enum cases) BEFORE pushing a release tag to prevent CI build failures.
- **Check Unused Async Results:** Ensure no new compiler warnings (e.g., unused results from `async` functions) are introduced, silencing them with `_ = ` if necessary.
