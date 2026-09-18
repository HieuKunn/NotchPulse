# NotchPulse v3.9.2

## 🔒 Face ID Improvements
- **Smart Distance Detection**: Face ID now accurately recognizes you whether you are sitting right up close (a hand-span away) or farther back. It automatically adjusts its matching thresholds to handle lens distortion when you're close to the camera.
- **Faster Recognition**: Face ID now scans in quick 2.5-second bursts and automatically retries if needed — no more waiting through long scan windows.
- **No Blink Required**: You no longer need to blink to unlock. Just look at the camera naturally and it recognizes you instantly.
- **Smoother Wake Unlock**: Fixed an issue where Face ID would flash briefly then fail after opening the lid or waking from sleep. The camera now waits until it's fully ready before scanning.
- **Photo & Spoof Protection**: Anti-spoof detection still blocks photos and screens — holding a phone with your photo won't bypass the lock.

## 🎵 Music & Lyrics
- **Perfect Sync**: Adjusted lyrics timing to better match the music, removing the slight delay for a perfect sing-along experience.

## ⚙️ Settings & Updates
- **Cleaner Settings**: Streamlined the Software Updates section by removing redundant buttons.
- **Smart Update Notifications**: The Settings window will now quietly show you when a new update is available right under the Check for Updates button. 
- **Faster Auto-Updates**: NotchPulse now checks for updates in the background much more frequently, ensuring you're always on the latest version when you want to be.

## 🔋 Battery Feature Deprecated
- **Removed Battery Module**: The Battery Charging Limit features and native battery status views have been removed. Due to Apple's changes in recent hardware (M3/M4 chips), directly controlling battery charging limits is no longer supported. To maintain system stability and avoid dangerous charging loops on new Macs, we've cleanly removed the battery tab and background helper from NotchPulse.
