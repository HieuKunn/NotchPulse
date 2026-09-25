# NotchPulse v4.8.5

## 🔒 Instant Face ID & 24/7 Zero-Latency Unlock
- **24/7 Resident AI Engine**: Kept the ArcFace CoreML model persistently resident in memory (~12MB RAM) to eliminate cold-start unloading lag and prevent model eviction after sleep.
- **0ms Lid Open & Wake Trigger**: Guaranteed instant scan trigger when opening the laptop lid or waking the screen, removing arm burst blocking and artificial delay buffers.
- **Lightning-Fast Recognition**: Instant Apple-style unlock the moment your face is recognized and liveness is confirmed.

## 🎛️ Liquid-Smooth HUDs & Native Popup Suppression
- **Leak-Free System Controls**: Completely suppressed native macOS sound and brightness popup overlays by swallowing Key-Up media events and timeout fallbacks.
- **Fluid Progress Bars**: Volume and brightness sliders now glide smoothly (`.smooth(duration: 0.18)`) when using keyboard shortcuts while maintaining 1:1 pixel-perfect tracking during mouse dragging.
- **Harmonized Inline Margins**: Standardized left (11pt) and right (10pt) margins across both Notch and Dynamic Island modes for clean, balanced visual symmetry.
