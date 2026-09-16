# 🚀 NotchPulse v3.8

Welcome to NotchPulse **v3.8**! This release delivers a major upgrade featuring an all-new Native Battery Monitor with smart charge limiting, a comprehensive overhaul of Face ID biometric unlock for macOS 15 Sequoia, and perfectly synchronized real-time lyrics.

---

### 🔋 Native Battery Monitor & Smart Charging
- **Live Hardware Stats on Notch**: View real-time Battery Health %, Cycle Count, real-time Charging/Discharging Wattage (W), Battery Temperature (°C), Voltage, and connected Power Adapter details (70W/96W/140W PD or MagSafe) directly in the Notch HUD.
- **Smart Custom Charge Limit**: Set a custom charge threshold (50%–95%) to automatically pause charging and prevent battery degradation when connected to power all day.
- **Desktop Mode Indicator**: Automatically detects when your Mac runs purely on AC power while charging is paused.
- **Ultra-Lightweight & Native**: Eliminated bloated background daemons and kernel extensions in favor of a streamlined, native SMC architecture that opens instantly without macOS Gatekeeper warnings.

### 🔒 Face ID Core Overhaul & Reliability Fixes
- **Keychain Accessibility Under Lock**: Updated vault credentials storage to `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, enabling smooth password retrieval when the Mac screen is locked without `errSecInteractionNotAllowed` errors.
- **Authoritative Lock Screen Detection**: Resolved CoreGraphics session boolean type casting (`CGSSessionScreenIsLocked`), ensuring unlock keystroke events are never prematurely aborted.
- **Pre-Warmed Session Caching**: Vault symmetric key and credentials are now pre-warmed and cached safely in memory during active sessions, eliminating keychain latency on wake.
- **Zero-Click Auto-Scan on Wake**: Automatically triggers biometric scanning upon display wake and manual screen lock with a smooth grace period.
- **Universal Character Keystroke Injection**: Added native unicode keystroke fallback (`keyboardSetUnicodeString`), ensuring passwords with special symbols and characters unlock accurately.
- **System Permissions Diagnostics**: Integrated real-time Camera and Accessibility status indicators in Settings with direct 1-click links to macOS System Settings.

### 🎵 Real-Time Synced Lyrics & Media HUD
- **Subsecond Precision Parser**: High-accuracy LRC parsing supporting `.x`, `.xx`, and `.xxx` subseconds with acoustic lead-in calibration and instrumental break detection (`♪ ♫ ♪`).
- **Drift-Free Periodic Sync**: Continuous 2.0-second background synchronization for Spotify and Apple Music controllers, keeping lyrics perfectly locked to audio playback.
- **Smooth Vertical Transitions**: Replaced abrupt text clipping with smooth vertical slide transitions without marquee jumping.

### ⚡ Performance & Stability
- **Apple Neural Engine Optimization**: ArcFace 512D inference operates with zero idle battery consumption and sub-second recognition latency.
- **Instant Gatekeeper-Safe Launch**: Clean inside-out ad-hoc code signature preserving Sparkle auto-update compatibility.

---

Thank you for using **NotchPulse**!
