# 🚀 NotchPulse v3.8.9

Welcome to NotchPulse **v3.8.9**! This release balances Face ID AI anti-spoofing to eliminate false rejections while completely stopping background camera leaks.

---

### 🔒 Face ID & Security Improvements
- **Balanced Anti-Spoofing Model Scoring**: Tuned the dual-model MiniFASNet ensemble to use the canonical probability fusion (average distribution + dominant class check) and fed properly scaled 2.7x and 4.0x wide context frames. This eliminates false rejections so real faces are recognized immediately without requiring exaggerated movements or multiple retries.
- **Smart Liveness Flow**: Switched standard verification back to non-blocking light mode while keeping active glare and bezel checks, preventing the system from freezing or rejecting users who sit still.

---

### 🐛 Bug Fixes
- **Camera Leak Prevention**: Fixed an issue where cancelling enrollment, switching tabs, closing Settings, or unlocking early would leave the camera session active in the background (green indicator dot staying on). Guaranteed strict camera teardown via `defer` across all Face ID workflows.

---

Thank you for using **NotchPulse**!
