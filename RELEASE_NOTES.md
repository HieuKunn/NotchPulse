# NotchPulse v3.8.7

## 🔋 Battery & Smart Charging Hub
- **Hardware SMC Daemon Launch Fixed**: Resolved a launchd configuration error (`EX_CONFIG 78`) by removing invalid `ProgramArguments` from daemon plists, allowing macOS `SMAppService` to execute the hardware SMC daemon directly from the app bundle.
- **Battery Toolkit Mode Alignment**: Standardized charging controls into three clear modes matching Battery Toolkit:
  - **Charge to Limit**: Automatically stops charging at your custom threshold (e.g. 80%) and powers the Mac directly from AC power.
  - **Charge to 100%**: Continuously charges to full capacity.
  - **Disable Charging**: Immediately pauses charging at current level and runs purely on AC adapter power.
- **Auto-Recovery & Continuous Enforcement**: Added automated background health checks every 30 seconds and intelligent daemon recovery to guarantee charging limits remain strictly active without dropping out.

## 🔒 Face ID & Biometrics
- **Touch ID & Passkey Auto-Authentication**: Expanded system prompt observer to intercept `CoreAuthUI`, Passkeys, and Touch ID confirmation dialogs in Safari and macOS, automatically switching to password input and auto-filling credentials.
- **Adaptive Arm's Length Recognition**: Introduced distance-adaptive matching and a multi-retry mechanism (up to 3 progressive scans) to seamlessly recognize faces at typical sitting distances (~60–80cm / arm's length).
- **Face Recognition Matching Restored**: Reverted facial recognition tolerances to proven v3.8.2 thresholds for rapid matching under normal lighting conditions.
- **Lock Screen Input Passthrough**: Fixed password typing on the Lock Screen so standard keyboard password entry and Touch ID remain completely responsive.

## 🎵 Lock Screen Media & Lyrics
- **Real-Time Lyrics in Compact Mode**: Fixed lyric timer so karaoke lyrics advance and track playback continuously in compact lock screen mode.
- **Dynamic Lock Screen Resizing**: Automatically animates window height when lyrics finish downloading in the background to prevent content clipping.
- **Static Lyrics Preview**: Displays the opening lines of tracks with static lyrics instead of a generic button.
- **Smooth Instrumental Transitions**: Displays musical notes (`♪  ♫  ♪`) during intros and instrumental solos to eliminate UI layout jumping.
