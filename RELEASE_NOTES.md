# NotchPulse v3.9.5

## 🐛 Bug Fixes
- **Keychain Password Save**: Fixed an issue where saving the lock screen password to Keychain failed silently on non-App Store builds due to a strict Touch ID access control policy (`.userPresence`). The vault now gracefully falls back to a standard device-unlocked Keychain item, ensuring your AES-256 encrypted password is saved securely.
- **AppleScript Automation Prompts**: Fixed an issue where the "Sync Music Permissions" button failed to prompt the macOS permission dialog for Spotify and Apple Music. The system will now correctly ask for Automation permissions, allowing precise playback and lyrics sync.

## 🔒 Face ID Re-Engineered
- **Guided Multi-Angle Face Setup**: Completely redesigned face enrollment with a smooth 80-tick circular indicator and guided head turns in all directions. Capturing your face from multiple angles ensures reliable recognition from any posture.
- **Strict Face Security**: Fixed an issue where unrecognized faces could match an enrolled profile. Face ID now strictly matches only the enrolled person, preventing strangers from unlocking your Mac.
- **Liveness & Anti-Spoofing**: Built-in 3D depth and reflection analysis prevents photo and screen spoofing while allowing natural, instant unlock without requiring eye blinks.
- **Sensitivity Controls**: Easily customize your Face ID sensitivity in Settings between Standard, High Security, and Relaxed modes.
- **Instant Password Entry**: Enhanced lock screen keyboard injection smoothly enters your Mac password as soon as your face is verified.

## 🎵 Music & Lyrics Synchronization
- **Refined Lyric Timing**: Reduced the lyric transition delay down to 0.3 seconds for responsive, near-instantaneous karaoke-style synchronization on both the Notch and Lock Screen player.
- **Spotify & Apple Music Automation Sync**: Added one-tap automation permissions for Spotify and Apple Music to maintain exact playback position synchronization without timing drift.
