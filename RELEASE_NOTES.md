# 🚀 NotchPulse v3.5.0

Welcome to NotchPulse **v3.5.0**! This major release completely integrates Glance's high-performance biometric Face ID engine, featuring deep macOS system unlock capabilities, ArcFace ML model evaluation, secure Keychain key vaulting, and optimized power management.

---

### 🚀 What's New
- **Glance Biometric Architecture Integration**: Fully replaced legacy face detection with Glance's modular Face ID engine (`NotchPulseFaceUnlockCoordinator`, `NotchPulseVault`, `NotchPulseCamera`, `NotchPulseFaceDetector`, `NotchPulseFaceAligner`, `NotchPulseFaceEmbedder`).
- **Apple 3D Vector Face ID Glyphs**: Authentic vector-rendered Apple Face ID lock icon with 3D perspective swivel, smile reaction, and pulse animations.

---

### 🔒 Face ID Improvements & Security
- **ArcFace CoreML & TTA Preprocessing**: Embedded ArcFace (`w600k_mbf`) neural network model with Test-Time Augmentation (TTA), CLAHE contrast enhancement, and global gamma normalization.
- **AES-256 Secure Keychain Vault**: Session keys and user credentials are saved in macOS Keychain with hardware-backed encryption.
- **Multi-Phase Liveness Verification**: Active optical liveness detection prevents spoofing via static photos or video playbacks.

---

### 🎵 Lock Screen & Lyrics
- **Smooth Lock Screen Hover Wake**: Hovering over or clicking the Lock Screen Notch immediately triggers instant Face ID scanning without manual button clicks.
- **Real-Time Synchronized Lyrics**: Automatic line scrolling and immediate active lyric illumination upon player expansion.

---

### ⚡ CPU & Performance Optimizations
- **Zero Idle CPU Load**: Complete camera and background pipeline teardown on display sleep or lock disarm, keeping CPU usage near 0%.
- **Memory Efficiency**: Lightweight memory footprint during sleep states and elimination of redundant shadow render passes to prevent GPU micro-stutter.

---

### 🛠️ Sparkle & Auto-Update Fixes
- **In-App Auto-Update Feed**: Updated Sparkle update feed appcast to v3.5.0 (`version 15`).
- **Non-Sandboxed Distribution**: Retained non-sandboxed configuration (`com.apple.security.app-sandbox = false`) for seamless auto-updates in `/Applications`.

---

Thank you for using **NotchPulse**!
