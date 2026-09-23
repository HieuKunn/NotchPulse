# NotchPulse v4.6.5

## 🖥️ Multi-Display & External Monitor Fixes
- **Persistent Display Preference**: Fixed an issue where selecting a specific external display in single-display mode could unintentionally revert the notch to the built-in MacBook display upon screen state updates.
- **Accurate Display Routing**: Ensured all header masks, drag detectors, and lock screen media components strictly honor the user's preferred display setting.

## 🔓 Responsive Lock Screen Face ID Scan & Expansion
- **Instant Scan on Hover & Wake**: Restored immediate Face ID camera scanning and overlay expansion when hovering or waking the Mac, with silent rest on explicit lock (`.screenLocked`).
- **Dynamic Color Morphing**: Continuous smooth color morph from cyan/electric blue during active face scanning to Apple emerald green (`#34C759`) upon unlock verification.

