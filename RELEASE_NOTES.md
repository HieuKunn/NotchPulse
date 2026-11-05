## NotchPulse v5.5 (Build 453)

### 🎵 Seamless Background Artwork Synchronization
- **Proactive Background Artwork Fetching**: Fixed an issue where changing tracks or media in the background (such as Spotify Web or YouTube) kept showing the previous media's thumbnail on the closed notch until hovered. Artwork is now actively decoded and cached in the background immediately upon playback changes.
- **Zero Cross-Session Leakage**: Prevented background YouTube tabs from overriding artwork for Spotify Web or other media players. Removed loose fallbacks that picked up unrelated open video tabs.
- **Instant Adapter Retry**: Immediately retries fetching official system Now Playing artwork when a new track event is received without artwork data, eliminating empty thumbnail gaps.

### 🔒 Face ID Unlock & Permissions
- **Reliable Password Auto-Fill**: Ensures stored passwords are typed seamlessly and reliably upon face recognition.
- **On-Demand Permission Handling**: Completely eliminated bulk permission alerts on app launch.
