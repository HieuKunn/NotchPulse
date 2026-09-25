# NotchPulse v4.8.5

## 🔒 Instant Face ID & Resilient Sensor Stabilization
- **Ultra-Responsive 150ms Lock Screen Face ID**: Reduced lock screen wake settle delay to 0.15s (150ms) and rearm cooldown to 400ms for instant face unlock when waking or locking your Mac.
- **Camera Sensor Warmup & Stabilization**: Added 3-frame sensor stabilization and consecutive frame match verification to let the camera auto-exposure settle, eliminating cold-wake frame jitter and false early aborts.
- **Concurrent Model Pre-Warming**: AI neural pipeline pre-warms in parallel while hardware camera starts up, giving zero-wait face recognition without draining RAM during idle periods.

## 🎛️ Liquid-Smooth HUDs & Native Popup Suppression
- **Leak-Free System Controls**: Completely suppressed native macOS sound and brightness popup overlays by swallowing Key-Up media events and timeout fallbacks.
- **Fluid Progress Bars**: Volume and brightness sliders now glide smoothly (`.smooth(duration: 0.18)`) when using keyboard shortcuts while maintaining 1:1 pixel-perfect tracking during mouse dragging.
- **Harmonized Inline Margins**: Standardized left (11pt) and right (10pt) margins across both Notch and Dynamic Island modes for clean, balanced visual symmetry.
