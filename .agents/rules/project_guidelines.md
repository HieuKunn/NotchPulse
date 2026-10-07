# NotchPulse Project Guidelines & Memory Rules

This document outlines the core rules, architectural guidelines, and release procedures for the NotchPulse project. All AI agents working on this codebase MUST read and strictly adhere to these instructions.

> ⛔️ **DO NOT RELEASE UNLESS EXPLICITLY INSTRUCTED (STRICT RULE):**
> If the user's prompt does NOT explicitly contain a direct command or request to release (e.g., "release", "publish", "tag", "release lại", "sửa lỗi build release", etc.), **DO NOT** bump versions/build numbers, **DO NOT** create or push git tags, and **DO NOT** trigger release workflows. Simply make code modifications, verify correctness, and commit normally.
>
> 🚨 **MANDATORY RELEASE CHECKLIST (ONLY WHEN USER EXPLICITLY ASKS FOR RELEASE):**
> 1. ✅ **Update Build Number & Version in Xcode Project:**
>    - Bump `MARKETING_VERSION` (e.g., `4.8.7`) and increment `CURRENT_PROJECT_VERSION` (build number, e.g., `149`) in `NotchPulse.xcodeproj/project.pbxproj`.
>    - ⚠️ **BUILD ERROR EXCEPTION RULE**: If the user provides a GitHub Actions / Xcodebuild error log stating the build FAILED, DO NOT increment the build number or version on your subsequent fix attempt. Keep the exact same version/build number and just force-push the fix, because no runnable binary was successfully released to users. Only strictly increment the build number when introducing new features or finalizing a completely successful prior build.
> 2. ✅ **Update `RELEASE_NOTES.md`:**
>    - Write clear, user-centric release notes for the new version.
> 3. ✅ **Update Sparkle `appcast.xml`:**
>    - Ensure `<sparkle:version>` (build number) and `<sparkle:shortVersionString>` match.
> 4. ✅ **Tag Git Release & Push:**
>    - `git tag -a vX.Y.Z -m "NotchPulse vX.Y.Z Release"` and `git push origin main --tags`.

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
- **⚠️ Notch & Dynamic Island Style Parity (REQUIRED):** By default, Notch and Dynamic Island styles MUST always render identical internal views, contents, layout metrics, tabs, and components unless specifically requested otherwise by the user. Do not artificially shrink or alter internal views, headers, or tab layouts for Dynamic Island.
- **Percentage-Based Sizing:** Use dynamic, screen-relative dimensions rather than rigid hardcoded pixel values for responsive UI components (Lyrics, Media View).
- **Display Awareness:**
  - Built-in MacBook Display: Dynamically adapt UI around the camera Notch geometry.
  - External Displays: Render standard flat designs centered symmetrically without Notch offsets.
- **Micro-Animations & Text Flow:** When expanding or shrinking media views, apply subtle scaling (1–2px) to prevent layout shifts or premature line breaks in lyrics.

### 3.1. ⚠️ Notch & Dynamic Island Animation & View Identity Preservation Rules (CRITICAL)
- **Stable View Identity (`_ConditionalContent` Prevention):**
  - **NEVER** wrap the main notch container in `conditionalModifier` or `if/else` checks where the condition depends on `vm.notchState == .closed` or states that flip during open/close.
  - In SwiftUI, toggling a condition in `conditionalModifier` swaps branches in `_ConditionalContent`, destroying the active view tree and instantiating a fresh view at target size. This cancels in-flight frame interpolations and causes the notch to abruptly pop open ("mở bùm ra") and snap shut ("đóng bụp vào") with zero continuous spring movement.
  - If a gesture (e.g. `onTapGesture`) should only trigger when closed, keep the view modifier unconditional (`!isFaceIDContentActive`) and place `guard vm.notchState == .closed` **INSIDE** the gesture closure.
- **Horizontal Padding Symmetry (14px Parity):**
  - Closed horizontal padding: `cornerRadiusInsets.closed.bottom` (14px).
  - Open horizontal padding: `10 + 4` = 14px.
  - Padding must remain strictly identical across closed and open states. Any mismatch causes sudden horizontal layout jumps and clips physical notch bottom wings.
- **Physical Notch vs Dynamic Island Differentiation:**
  - Floating pill styling (`RoundedRectangle`, `dynamicIslandTopOffset`, bottom shadow offset) MUST ONLY apply when `isDynamicIsland && !hasPhysicalNotch`.
  - On displays with a physical MacBook notch (`hasPhysicalNotch == true`), NotchPulse MUST ALWAYS attach flush to the top edge and use `currentNotchShape` so its wings seamlessly attach to the display bezel.
- **Continuous Overlay Strokes:**
  - Never branch with `if` inside `.overlay`. Instead, unconditionally render the shape and smoothly interpolate opacity: `.stroke(Color.white.opacity((isDynamicIsland && vm.notchState == .open) ? 0.10 : 0))`.
- **Hover Debounce & Cohesive Spring Transactions:**
  - In `handleHover(false)`, maintain a hover exit delay of at least 250–280ms before collapsing. Because the spring expansion takes ~380ms (`response: 0.38`), short timeouts (e.g. 100–120ms) cancel the expansion mid-flight.
  - Always bundle `isHovering = false` and `vm.close()` inside the exact same `withAnimation(animationSpring)` block so hover-out and retraction animate cohesively.


---

## 4. Lock Screen & FaceID Window
- When returning to the Lock Screen during an active session: Prioritize hover-to-wake / hover-to-authenticate for Face ID rather than requiring a button click.
- **Top-Most Layer Face ID Rendering (CRITICAL ARCHITECTURAL RULE):**
  - Face ID static previews and scan animations (`stillImageLayer`, `FaceIDScanAnimationView`, `ScanAnimationView`, `FaceIDContentView`) MUST ALWAYS be placed on the absolute top-most layer of the hierarchy.
  - In Core Animation (`FaceIDScanAnimationHostView` / `ScanAnimationHostView`), `playerLayer` is added first (`zPosition = 0`) and `stillImageLayer` is added last (`zPosition = 100`). During idle/prep, `stillImageLayer` remains on top (`zPosition = 100`) so no black screen or video layer obscures the face.
  - In SwiftUI views (`ContentView.swift`, `FaceIDOverlayView.swift`, `LockScreenFaceIDWindow.swift`), Face ID views must always have explicit `.zIndex(999)` so no HUD or background elements render over Face ID.
  - Drop-down expansion on Face ID activation must always animate smoothly using `.spring(response: 0.38, dampingFraction: 0.8)` starting from closed height to open height.
- **Lyrics Behavior on Lock Screen:**
  - Upon track change, immediately reset and scroll lyrics to the beginning of the song (line 0 / top) without waiting for the first lyric timestamp.
  - When expanding from compact media view to full-screen lyrics, immediately illuminate and center the currently active lyric line without waiting for the next line's timestamp.

---

## 5. Code Removal & Refactoring (Pre-Release Checks)
- **Verify Dangling References (REQUIRED):** When removing features, deprecating modules, or modifying core structures, you MUST perform a deep `grep_search` across the entire codebase (`*.swift`) for any related symbols, variables, or enum cases.
- **Do Not Rely Only on Project File Cleanup:** Removing source files from `project.pbxproj` is not enough. You must proactively find and delete dangling references in other components (e.g., `@ObservedObject` references, dead enum cases) BEFORE pushing a release tag to prevent CI build failures.
- **Check Unused Async Results:** Ensure no new compiler warnings (e.g., unused results from `async` functions) are introduced, silencing them with `_ = ` if necessary.

---

## 6. Localization & Dictionary Literal Safety (CRITICAL CRASH PREVENTION)
- **NO Duplicate Keys in Dictionary Literals:** In Swift, initializing dictionary literals with duplicate keys (e.g. `[String: String]`) causes a runtime static initialization trap (`fatalError` / `EXC_BREAKPOINT` / `SIGTRAP`), causing the app to crash immediately upon launch.
- **Audit `AppLocalization.swift` Before Release:** Always verify that dictionary keys in `AppLocalization.swift` are strictly unique per language dictionary before committing or releasing.

