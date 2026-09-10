# 🚀 NotchPulse v3.5.0

Welcome to NotchPulse **v3.5.0**! This major release upgrades our biometric Face ID engine, introduces an authentic Apple-style guided enrollment sweep, and enhances multi-display styling on the Lock Screen.

---

### 🚀 What's New
- **Glance Biometric Face ID Architecture**: Integrated a high-performance Face ID biometric pipeline (`NotchPulseFaceUnlockCoordinator`, `NotchPulseVault`, `NotchPulseCamera`, `NotchPulseFaceDetector`, `NotchPulseFaceAligner`, `NotchPulseFaceEmbedder`).
- **Apple 80-Tick Guided Enrollment Ring**: Full circular head-rotation enrollment sweep UI (`NotchPulseEnrollmentRingView`) with progress ticks, live head guidance cues, and completed state animations.
- **3D Vector Face ID Lock Screen Glyph**: Authentic vector-rendered Apple Face ID lock icon featuring 3D perspective swivel, smile reaction, shockwave pulse, and shake-on-error animations.
- **Multi-Monitor Adaptive Lock Screen Notch**: Dynamic positioning that seamlessly respects your chosen **Notch** vs **Dynamic Island** mode (and custom top offsets) on external or non-notch displays.

---

### 🔒 Face ID & Security Improvements
- **ArcFace CoreML & TTA Preprocessing**: Embedded ArcFace (`w600k_mbf`) neural network model with Test-Time Augmentation (TTA), CLAHE contrast enhancement, and global gamma normalization.
- **AES-256 Secure Keychain Vault**: Session keys and user credentials are saved in macOS Keychain with hardware-backed encryption.
- **Multi-Phase Liveness Verification**: Active optical liveness detection to prevent spoofing via static photos or video playbacks.

---

### ⚡ CPU & Performance Optimizations
- **Zero Idle CPU Load**: Complete camera and background pipeline teardown on display sleep or lock disarm, maintaining 0% idle CPU footprint.
- **Concurrency & Event Injection Safety**: Optimized lock screen unlock injection using thread-safe background dispatch.

---

Thank you for using **NotchPulse**!
