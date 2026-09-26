# NotchPulse v4.8.7

## ✨ UI Polish & Reliability Enhancements
- **Now Playing Robustness**: Fixed a bug where `MediaChecker` incorrectly flagged Now Playing as deprecated due to test environment failures.
- **Shelf Click-Through Fix**: Removed the invisible hit-testing view in the expanded drag detection area, eliminating the "dead zone" that blocked normal mouse clicks on macOS.
- **Modern Apple Settings UI**: Upgraded settings sidebar icons to modern Apple-style SF Symbols and integrated dynamic adaptive glass backgrounds respecting system Accessibility settings (Reduce Transparency).
- **Stream Performance & Memory Optimization**: Added streaming debounce to mediaremote-adapter and downsampled album artwork for optimal Retina crispness with minimal RAM usage.
- **Hidden Scrollbars**: Cleaned up settings view scrollbars for a seamless, borderless experience while maintaining full scroll responsiveness.

