## 🚀 What's New in NotchPulse v5.4

### 🔒 Rock-Solid Face ID & Zero Conflict Architecture
- **Eliminated Command Contention**: Isolated lock-screen face recognition from desktop authentication tasks, ensuring Face ID never gets interrupted or clobbered.
- **Fixed Stuck Animation on Error**: Resolved an issue where failure animations could hold indefinitely after an unrecognized scan. The overlay now collapses and resets cleanly every time.
- **Flawless Multi-Display Adaptation**: Face ID overlay and Lock Screen controls strictly respect your selected screen and macOS primary display settings, appearing as a natural Notch or Dynamic Island pill.
- **Seamless Lock/Wake Transitions**: Eliminated race conditions when rapidly locking and unlocking your Mac, keeping the lock screen media player and Face ID perfectly in sync.

### ⚡️ Zero-Overhead Performance & Fluid Animations
- **Zero-Lag Notch Expansion**: Grouped the Notch and Dynamic Island layout into dedicated hardware-accelerated layers, completely eliminating CPU rendering spikes when opening or hovering the Notch.
- **Ultra-Efficient Media Playback**: Eliminated background polling scripts for Spotify and Apple Music. Track progress, elapsed time, and synchronized lyrics now calculate instantly and smoothly with 0% CPU usage.
- **Instant Calendar & Reminders Cache**: Added smart in-memory event caching so opening or hovering the Notch instantly displays your schedule without reading your calendar database every time.
