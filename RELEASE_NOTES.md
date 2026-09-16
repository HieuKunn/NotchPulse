# 🚀 NotchPulse v3.8.9

Welcome to NotchPulse **v3.8.9**! This release brings major fixes to hardware battery charging control, eliminates admin password prompts, refines Face ID recognition sensitivity, and optimizes idle memory and CPU usage.

---

### ⚡ Battery & Power Control
- **Instant Charge Limit Enforcement**: Selecting "To Limit" or adjusting the charging slider now immediately halts battery charging if the current battery percentage is at or above your configured threshold. The Mac runs on direct AC power with 0W battery charge current.
- **AC Power Mode**: Cleanly pauses battery charging, powering your Mac directly from the power adapter while keeping the battery level stable.
- **Eliminated Admin Password Loops**: Completely resolved repeated macOS administrator password prompts (*"NotchPulse wants to make changes"*) during routine battery status checks and limit adjustments.
- **Responsive Telemetry**: Live battery and hardware telemetry polling now refreshes every 1.5 seconds when the tab is open, and instantly halts (0% CPU) when the notch is closed or switched.

---

### 🔒 Face ID & Security Improvements
- **Multi-Pose Face Recognition Sensitivity**: Upgraded embedding matching to evaluate nearest-neighbor angle vectors, eliminating false rejections caused by multi-angle pose centroid dilution.
- **Settings Live Verification**: Live Face ID testing in Settings now accurately detects and confirms enrolled faces with smooth confidence scoring.
- **Permission Flow on Toggle**: Enabling system authorization prompt auto-authentication now proactively prompts for Camera and Accessibility permissions on demand.
- **Strict Camera Teardown**: Guaranteed immediate camera shutoff and green indicator deactivation whenever enrollment, testing, or screen unlock finishes or cancels.

---

### 🚀 Performance & Memory Optimizations
- **Media RAM Spike Fix**: Downsampled album artwork during average color calculation to 40×40px, cutting bitmap memory usage by 5,625× and preventing RAM runaway on track changes.
- **Cached Artwork Processing**: Avoided redundant base64 image decoding during track playback updates.
- **Idle State Cleanup**: Mounted Lock Screen media views dynamically on-demand, deallocating views and timers to 0MB when dismissed.

---

Thank you for using **NotchPulse**!
