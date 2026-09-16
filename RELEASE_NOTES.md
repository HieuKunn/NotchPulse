# 🚀 NotchPulse v3.8.7

Welcome to NotchPulse **v3.8.7**! This release brings a major security upgrade to Face ID with production-grade AI Anti-Spoofing capabilities.

---

### 🔒 Face ID Upgrades
- **Production-Grade AI Anti-Spoofing Ensemble**: Upgraded Liveness Detection from the placeholder model to a dual-model ensemble (MiniFASNetV2 and MiniFASNetV1SE).
- **Advanced Presentation Attack Detection**: The system now utilizes Fourier Transform texture analysis to detect high-frequency data loss common in screen replays and printed photos.
- **Hardware Acceleration**: Both anti-spoofing models are fully compiled for CoreML, leveraging the Apple Silicon Neural Engine for near-instant (under 5ms) inference with virtually zero battery impact.

---

Thank you for using **NotchPulse**!
