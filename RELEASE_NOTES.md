# NotchPulse v4.0.0

## 🔒 Security & Face ID Re-Engineered
- **Advanced 9-Pose Face Setup**: Completely redesigned face enrollment with a smooth 80-tick circular indicator and guided head turns in all directions. Capturing your face from 9 different angles ensures far superior reliability and security.
- **Strict Anti-Spoofing & Liveness**: The Face ID engine now leverages robust 3D depth and reflection analysis from your webcam, stopping photo and screen spoofing attacks dead in their tracks.
- **Flawless Recognition Angles**: By directly utilizing Vision framework's landmark rotation data, the setup now perfectly understands your head's tilt and yaw, making enrollment seamless and unlocking effortless even if you're not perfectly centered.
- **Instant Password Injection**: Once your face is securely verified, the lock screen keyboard injects your Mac password instantaneously.

## 🎵 Music & Lyrics
- **Refined Lyric Timing**: Reduced the lyric transition delay down to 0.3 seconds for responsive, near-instantaneous karaoke-style synchronization on both the Notch and Lock Screen player.
- **Seamless Spotify & Apple Music Sync**: Streamlined automation permissions allow precise, drift-free playback tracking.

## 🐛 Bug Fixes
- **Keychain Password Save**: Fixed a silent failure on non-App Store builds when saving the lock screen password to Keychain, ensuring your AES-256 encrypted password is saved securely with the correct device-unlocked fallback policy.
- **UI Settings**: The "Release name" in Settings now automatically and dynamically displays the current version (e.g. "Pulse 4.0 🚀") instead of being permanently stuck on an older version.
