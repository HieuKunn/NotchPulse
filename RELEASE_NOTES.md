# NotchPulse v3.9.6

## 🐛 Bug Fixes
- **Face ID Setup Logic (Strict)**: Reverted Face ID setup logic to explicitly use the exact parameters and threshold implementation from the source engine to guarantee flawless alignment accuracy and timing without any UI modification.
- **App Icon**: Updated the application icon to feature a pristine full-bleed design, resolving the system-imposed gray background box on macOS Sequoia.

## 🔒 Face ID Re-Engineered
- **Guided Multi-Angle Face Setup**: Completely redesigned face enrollment with a smooth 80-tick circular indicator and guided head turns in all directions. Capturing your face from multiple angles ensures reliable recognition from any posture.
- **Strict Face Security**: Fixed an issue where unrecognized faces could match an enrolled profile. Face ID now strictly matches only the enrolled person, preventing strangers from unlocking your Mac.
- **Liveness & Anti-Spoofing**: Built-in 3D depth and reflection analysis prevents photo and screen spoofing while allowing natural, instant unlock without requiring eye blinks.
- **Sensitivity Controls**: Easily customize your Face ID sensitivity in Settings between Standard, High Security, and Relaxed modes.
- **Instant Password Entry**: Enhanced lock screen keyboard injection smoothly enters your Mac password as soon as your face is verified.

## 🎵 Music & Lyrics Synchronization
- **Refined Lyric Timing**: Reduced the lyric transition delay down to 0.3 seconds for responsive, near-instantaneous karaoke-style synchronization on both the Notch and Lock Screen player.
- **Spotify & Apple Music Automation Sync**: Added one-tap automation permissions for Spotify and Apple Music to maintain exact playback position synchronization without timing drift.
