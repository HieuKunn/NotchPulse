# 🚀 NotchPulse v3.8.6

Welcome to NotchPulse **v3.8.6**! This release delivers major memory optimizations, full BatteryToolkit hardware daemon restoration, precision Face ID hover detection, and automatic system prompt authentication with Face ID.

---

### 🔋 Battery Management & SMC Hardware Control
- **Native Battery Daemon Restored**: Re-embedded and signed `NotchPulseBatteryDaemon` LaunchDaemon with AppleScript administrative installer for seamless macOS 14+ setup.
- **Hardware Charge Limiting**: Fully wired SMC registers (`CHTE`, `CH0C`, MagSafe LED `ACLC`) for all 3 power modes: `To Limit` (e.g., 55%), `Charge to 100%`, and `AC Power Mode` (direct adapter power without cell charging).

### ⚡ Memory & Performance Optimization
- **CoreML Model Deduplication**: Refactored `NotchPulseArcFaceEmbedder` into a thread-safe singleton. CoreML model loading is deferred until active recognition or enrollment is requested, consuming **0 MB** RAM when Face ID is idle.
- **Settings Memory Teardown**: `SettingsWindowController` now lazy-loads `SettingsView` on demand and purges its view hierarchy on close, reclaiming tens of megabytes of SwiftUI view states and GPU textures.
- **Lock Screen Layer Cleanup**: Teardowns animation and video layers when `LockScreenFaceIDWindow` hides.
- **Massive RAM Reduction**: Reduced peak closed-notch RAM usage from ~350 MB down to **< 90 MB**.

### 🔒 Face ID & System Authorization Enhancements
- **Precision Notch Hover Detection**: Corrected flipped coordinate calculations in `LockScreenTrackingHostingView`. Hover activation for Face ID is now strictly confined to the physical top notch bezel, preventing accidental triggers from lower screen areas.
- **Auto-Authenticate System Prompts**: Added passive, event-driven observation for macOS `SecurityAgent` authorization dialogs. Automatically presents Face ID to verify admin privileges and system prompts with seamless Touch ID and manual password fallback.
- **English Settings Standard**: Verified 100% native English UI text across all settings tabs and dialogs.

---

Thank you for using **NotchPulse**!
