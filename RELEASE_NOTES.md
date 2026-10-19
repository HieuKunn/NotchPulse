## 🚀 What's New in NotchPulse v5.4

### 🔒 Perfected Face ID & Seamless Lock Screen
- **True Lock Screen Style Parity**: The lock screen now strictly honors your chosen style (Notch or Dynamic Island) across all displays, never reverting to a pill by default.
- **Flawless Face Recognition**: Upgraded the on-device face recognition engine with smart multi-target hardware acceleration, ensuring your camera recognizes your face reliably on every wake.
- **Instant Clean Collapse & Retry**: Unrecognized scans now play a swift failure hint and smoothly collapse shut in 1.8 seconds, ready for instant hover reactivation without lingering awkwardly.
- **Eliminated Command Contention**: Isolated lock-screen face recognition from desktop authentication tasks, ensuring Face ID never gets interrupted or clobbered.
- **Seamless Lock/Wake Transitions**: Eliminated race conditions when rapidly locking and unlocking your Mac, keeping the lock screen media player and Face ID perfectly in sync.

### ⚡️ Zero-Overhead Performance & Fluid Animations
- **Zero-Lag Notch Expansion**: Grouped the Notch and Dynamic Island layout into dedicated hardware-accelerated layers, completely eliminating CPU rendering spikes when opening or hovering the Notch.
- **Ultra-Efficient Media Playback**: Track progress, elapsed time, and synchronized lyrics now calculate instantly and smoothly with zero background overhead.
- **Instant Calendar & Reminders Cache**: Smart in-memory event caching ensures opening or hovering the Notch instantly displays your schedule without reading your database every time.
