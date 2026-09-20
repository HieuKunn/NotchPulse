# NotchPulse v4.2.0

## Seamless Unified Face ID Morphing
- **Unified Hardware Morphing**: Face ID is now built directly into the MacBook Notch and Dynamic Island instead of opening in a separate floating window. The cutout or pill naturally expands downward with continuous corner curves to show the scanning animation and smoothly retracts back into place upon verification.
- **Fluid Desktop Transition**: Face ID seamlessly carries your session from lock screen wake directly into your active desktop. The notch smoothly shrinks to its resting shape right as your desktop appears, providing an uninterrupted, native macOS experience.
- **Smart Media & HUD Tucking**: Active music playback, album artwork, and volume/brightness HUD indicators temporarily tuck inside whenever Face ID begins scanning, eliminating overlapping elements and keeping the visual silhouette clean.
- **Pure Lock Screen Presentation**: When waking on the lock screen, the notch maintains a clean, unified resting state without leaking media controls or text, expanding only when active face recognition takes place.

## Comprehensive Background Resource Optimization
- **On-Demand Memory Allocation**: The facial recognition pipeline now loads into system memory on-demand rather than upon application launch, saving over 100 MB of continuous background memory.
- **Eliminated Idle Background Wakeups**: System security authorization tracking now uses intelligent conditional scheduling, eliminating redundant background checks and freeing up CPU cycles when Face ID authentication is idle.
- **Smart Animation & GPU Throttling**: Audio waveform spectrums and playback animations now immediately pause rendering whenever music is paused or when the notch is closed, removing unnecessary GPU drawing in the background.
- **Timer Lifecycle Management**: Background facial animation and glance timers are now properly invalidated upon view exit, preventing background timer accumulation.
