# 🚀 What's New in NotchPulse v3.1.3

Welcome to NotchPulse **v3.1.3**! This release brings significant improvements to Face ID enrollment, Lock Screen Lyrics synchronization, idle CPU & memory efficiency, and in-app automatic updates via Sparkle.

---

### 🔒 Face ID & Enrollment Enhancements
- **4.0s Timeout**: Increased face scanning timeout back to 4.0 seconds for more comfortable lock screen unlocking.
- **Manual Lock Improvement**: Disabled automatic Face ID camera start when the user manually locks the screen from an active session. Face ID will now only auto-start when the Mac wakes up from sleep.
- **5-Step iPhone-Style Setup**: Redesigned face enrollment into a smooth 5-stage pose sequence (Straight, Slight Left, Slight Right, Pitch Up, Pitch Down) with relaxed yaw thresholds and clear UI progress indicators.
- **Hover & Wake Lock Screen Integration**: Improved Face ID wake triggers when hovering on the lock screen overlay.

---

### 🎵 Lock Screen Media Player & Lyrics
- **Accurate Lyric Sync (+0.7s Offset)**: Adjusted lyric timeline timing by +0.7 seconds to ensure lyrics perfectly match audio playback speed.
- **Immediate Lyric Rendering**: Active lyrics now display immediately upon expanding to full-screen view without waiting for the next subtitle timestamp.
- **Idle View Optimization**: Completely pause animation timers, wave bars, and timeline views when the Lock Screen window is hidden to conserve system resources.

---

### ⚡ CPU & Performance Optimizations
- **SystemMonitor Leak Fix**: Resolved active subscriber memory leak in `SystemMonitorManager`.
- **Interval Adjustment**: Polled system statistics at an optimized 2.5s interval to ensure background CPU usage remains near **0%** when idle.

---

### 🛠️ In-App Sparkle Auto-Update Fix
- **App Sandbox & Installer Fix**: Resolved the `"An error occurred while launching the installer"` error during Sparkle update by setting `com.apple.security.app-sandbox` to `false` for web distribution.
- **Framework Code Signing**: Corrected build pipeline code signing to sign embedded frameworks inside-out without overwriting internal helper signatures (`Autoupdate.app`).

---

Thank you for using **NotchPulse**!
