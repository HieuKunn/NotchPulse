# 🚀 NotchPulse v3.8.10

Welcome to NotchPulse **v3.8.10**! This update focuses strictly on Face ID reliability by reverting to Apple's native Vision ML while preserving advanced anti-spoofing security, along with significant UI smoothness improvements.

---

### 🔒 Face ID & Security Fixes
- **Restored Native Vision ML**: Dropped the experimental ArcFace (512D) model and reverted the biometric matching engine back to Apple's native `Vision Feature Print` (2048D). This completely resolves the issue where the camera was "too strict" or failed to recognize enrolled faces, restoring the rock-solid recognition from previous versions.
- **Maintained Advanced Anti-Spoofing**: Kept the new multi-phase optical liveness verification intact. Your face is easily recognized again, but photos or videos still cannot bypass the lock.
- **Far-Distance Recognition**: Lowered the minimum prominent face width requirement to 4%, allowing the camera to easily detect and authenticate you even if you sit far back from the screen.

---

### 🚀 Performance & UI Smoothness
- **Eliminated Scanning Lag**: Reduced the frame processing delay during enrollment and testing by nearly 4× (from 150ms to 40ms). The camera feed and testing results in Settings now feel buttery smooth (25+ FPS) without stuttering or lag.

---

*Note: Due to the underlying Face ID engine change, you MUST delete your old face and scan a new one in Settings -> Face ID Unlock.*

Thank you for using **NotchPulse**!
