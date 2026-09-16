# 🚀 NotchPulse v3.8.6

Welcome to NotchPulse **v3.8.6**! This release delivers major memory optimizations, full BatteryToolkit hardware daemon restoration, precision Face ID hover detection, and automatic system prompt authentication with Face ID.

---

### 🔋 Battery Management & SMC Hardware Control
- **Native Battery Daemon Restored**: Corrected LaunchDaemon bundle layout and embedded `NotchPulseBatteryDaemon` with AppleScript administrative installer for seamless macOS 14+ setup.
- **Hardware Charge Limiting**: Fully wired SMC registers (`CHTE`, `CH0C`, MagSafe LED `ACLC`) for all 3 power modes: `To Limit` (e.g., 55%), `Charge to 100%`, and `AC Power Mode` (direct adapter power without cell charging).

### ⚡ Memory & Performance Optimization
- **CoreML Model Deduplication**: Refactored `NotchPulseArcFaceEmbedder` into a thread-safe singleton. CoreML model loading is deferred until active recognition or enrollment is requested, consuming **0 MB** RAM when Face ID is idle.
- **Settings Memory Teardown**: `SettingsWindowController` now lazy-loads `SettingsView` on demand and purges its view hierarchy on close, reclaiming tens of megabytes of SwiftUI view states and GPU textures.
- **Lock Screen Layer Cleanup**: Teardowns animation and video layers when `LockScreenFaceIDWindow` hides.
- **Massive RAM Reduction**: Reduced peak closed-notch RAM usage from ~350 MB down to **< 90 MB**.

### 🔒 Face ID & System Authorization Enhancements
- **Precision Notch Hover Detection**: Replaced bounding box hover with exact notch clipping shapes (`currentNotchShape`) and fixed coordinate calculations in `LockScreenTrackingHostingView`. Hover activation for Face ID is now strictly confined to the physical notch geometry.
- **Touch ID & Passkey Auto-Authentication**: Expanded system authorization interceptor to cover `com.apple.coreservices.uiagent` and `LocalAuthentication` UI agents. Face ID will seamlessly authenticate Passkeys, Touch ID dialogs, and sudo prompts with graceful native fallback.
- **English Settings Standard**: Verified 100% native English UI text across all settings tabs and dialogs.

---

Thank you for using **NotchPulse**!
