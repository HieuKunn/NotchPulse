## 🌟 Important Release: NotchPulse v5.5

> **Important Update:** This release brings substantial CPU efficiency improvements during active notch playback, seamless lock screen handover, responsive Face ID biometric matching, refined clipboard browsing, and clean edge-to-edge silhouette styling.

### 📋 Enhanced Clipboard Browsing & Dynamic Tab Heights
- **Strict 3-Item Viewport**: Calibrated the Clipboard panel height to precisely 232pt, displaying exactly 3 full clipboard cards and header while cleanly hiding overflow items below the fold until scrolled.
- **Independent Tab Height Retraction**: Resolved an issue where switching from expanded views (such as Clipboard, Audio, or Display) to System Monitor left an empty black gap. Each tab now preserves and smoothly retracts to its own native height.

### 🍏 100% Native macOS System Styling & Apple HIG Declarative UI
- **True macOS Native Settings**: Modernized Settings window with native window transparency and authentic sidebar vibrancy (frosted glass blur), allowing desktop wallpaper light sampling just like macOS System Settings.
- **Unified 52pt Frosted Header Bar**: Refined detail header bar with native SF Pro 14pt semibold typography and standard 52pt unified height, featuring a delicate hairline separator and authentic system material blur (`.bar`) that softly blurs content as it scrolls underneath.
- **Deep Settings Search Indexer**: Search now scans all toggles, sliders, pickers, and descriptions across every setting tab in your active language, with instant diacritic-insensitive matching and live sidebar hints.
- **Clean Scrollbar-Free Interface**: Completely removed the vertical scrollbar from the settings detail pane for a distraction-free, edge-to-edge layout while keeping mouse and trackpad scrolling silky smooth.
- **100% Declarative Semantic Tokens**: Audited the entire app to completely eliminate manual RGB hex/white color tokens. All controls, toggles, indicators, and charts now use Apple dynamic semantic tokens (`.primary`, `.secondary`, `.effectiveAccent`, `.green`, `.orange`, `.red`), automatically adapting across Light/Dark modes and accessibility settings.
- **Hierarchical System Materials**: Feature Tour instruction cards and Face ID setup panels now utilize native system materials (`.regularMaterial`, `.thickMaterial`, `.bar`), fully respecting Reduce Transparency preferences.
- **Enhanced Display Hub Tour**: Added interactive Display Hub spotlight walkthrough with full localization across all 9 supported languages.

### ⚡️ Massive CPU Optimization & Clean Silhouette
- **Whisper-Quiet Media Scrubbing**: Throttled progress bar recalculations and synced lyrics evaluation to human-optimal intervals, preventing unnecessary redraw cycles and slashing open notch CPU usage.
- **Crisp Edge Silhouette**: Removed unnecessary fuzzy drop shadows from the Notch and Dynamic Island panels for a clean, distraction-free aesthetic with reduced WindowServer composite overhead.

### 🎛️ Refined HUDs & Bluetooth Battery Protection
- **Eliminated Bluetooth vs Volume Race Condition**: Switching audio output to connected Bluetooth headphones no longer triggers a false volume change HUD, keeping your battery status indicator steady and visible.
- **Pixel-Perfect Default HUD Silhouette**: Expanded horizontal safe insets to 18pt so volume, brightness, and backlight icons are never clipped by the bottom curved corners of the hardware Notch or Dynamic Island.
- **Balanced Notch Height**: Eliminated the empty space beneath the bottom-row HUD slider, ensuring a tight, compact, and polished layout.
- **Harmonized Open Notch HUD**: Restored the sleek capsule container with subtle border highlights for the Open Notch HUD bar.

### 🔒 Perfected Face ID & Lock Screen Handover
- **Instant First-Try Unlock on Wake**: Restored multi-path matching (centroid and strict/relaxed sample similarities) so your Mac recognizes your face immediately on the very first frame when opening the lid.
- **Ultra-Fast Zero-Delay Arming**: Removed artificial delays on wake, allowing Face ID to start detecting your face the instant your screen lights up.
- **Smart Camera Hardware Warming & 0% Idle CPU**: Camera sensor remains pre-warmed on the lock screen for instant crisp frames while skipping frame processing until you hover or scan, preserving battery and keeping idle CPU at 0%.
- **Direct Hardware Frame Processing**: Integrated direct pixel buffer detection straight into Apple's Vision framework, eliminating intermediate memory copies and drastically lowering RAM usage.
- **Intelligent Lid-Opening Quality Filter**: Replaced arbitrary timers with face quality gating, preventing keyboard or desk reflections from interrupting Face ID while opening your MacBook.
- **Snappy Error Recovery**: Failure cue holds for a brisk 1.1s before gracefully collapsing, making retry or password input faster than ever.
- **Clean & Native Overlay Design**: Kept the scanning state clean with a calm, resting biometric glyph that smoothly transforms into an unlock confirmation or subtle retry cue.
- **Seamless Lock Screen Handover**: Eliminated any momentary pause or visual disappearance when your Mac transitions into the lock screen.
- **Instant Hover Activation**: Hovering over the Notch or Dynamic Island on your lock screen triggers biometric unlock immediately.
- **Pixel-Perfect Notch Alignment**: The closed Face ID drop panel now precisely matches the resting notch width, completely eliminating any momentary shrink or resize stutter.

### ⚡️ Zero-Overhead Performance & Fluid Animations
- **Zero-Lag Expansion**: Notch and Dynamic Island panels use hardware-accelerated rendering layers for smooth 120Hz ProMotion response with zero CPU spikes.
- **Ultra-Efficient Media Playback**: Track progress, elapsed time, and synchronized lyrics calculate with whisper-quiet efficiency.
- **Instant Calendar & Reminders Cache**: Fast memory caching ensures opening the Notch instantly displays your schedule without delay.

