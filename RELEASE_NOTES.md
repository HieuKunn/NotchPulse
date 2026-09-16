# 🚀 NotchPulse v3.8.1

Welcome to NotchPulse **v3.8.1**! This update brings crucial performance and battery optimizations, deep macOS App Nap integration, and a refined Notch HUD layout.

---

### 🔋 Battery Monitor & macOS App Nap Optimization
- **On-Demand Sensor Polling**: Battery telemetry polling (SMC temperature, wattage, voltage, and amperage) is now strictly active only when the Battery tab or popover is visible. When closed, internal timers are immediately invalidated and cancelled.
- **True macOS App Nap Compliance**: NotchPulse now drops to near 0% idle CPU and zero background energy impact when the Notch is resting, preventing battery drain during long work sessions.
- **Event-Driven AC Power Notifications**: Continues leveraging macOS native `IOPowerSources` run-loop hooks to detect charger plug/unplug and AC adapter changes instantly with zero CPU overhead.

### 📐 UI & Notch HUD Layout Refinements
- **Perfect 50/50 Dual Panel Ratio**: Normalized the Hardware Controls panel and the Battery Health & Status panel into an exact 50/50 split.
- **Bottom Bezel Padding**: Added dedicated bottom and horizontal edge margins ensuring all controls and hardware rows fit completely within the HUD without vertical scrolling or overlapping the Notch's bottom curves.
- **Consistent Status Indicators**: Synchronized live desktop mode, charge limit progress, and wattage status indicators across the Notch HUD, menu bar extra, and simulator previews.

---

Thank you for using **NotchPulse**!
