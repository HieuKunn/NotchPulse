## 🚀 What's New in NotchPulse v5.0 

### 🌊 Buttery-Smooth Notch, Face ID & Onboarding Motion
- **Spring Animation Restored**: Re-anchored value-scoped `.animation` springs on the notch frame (matching the boring.notch baseline) so open/close always eases frame-by-frame instead of snapping open instantly when other state changes mid-flight.
- **120Hz Frame Pacing Fixes**: Cached the Face ID camera→display lookup and the lock-screen state check that previously ran dozens of times per animation frame — the main thread no longer stalls during expansion, eliminating stutter and torn frames.
- **Cleaner Compositing**: Removed asynchronous layer drawing that could produce blurry/garbled frames while the notch resized continuously on ProMotion displays.
- **Face ID Panel**: Scan/success/failure phase changes are now animated with the same spring as the notch, so the panel expands organically on hover and lock screen.
- **Spotlight Tour**: Custom open-height changes between tour steps now animate with the notch spring instead of snapping.
- **HUD & Live Activity Width**: Closed-notch silhouette correctly re-binds to inline HUD / music live-activity / face content width.
