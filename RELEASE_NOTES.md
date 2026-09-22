# NotchPulse v4.6.3

## 🔐 Face Unlock — Session Authentication Fix
- **Automatic re-authentication after lock**: Fixed a critical issue where Face Unlock would silently fail after your Mac woke from sleep or the screen was locked. Previously, the session key was cleared from memory on lock but the app never properly prompted for Touch ID or your password to restore it — meaning Face Unlock was stuck in a broken state until you manually went to Settings → Password and authenticated there. Now, when Face Unlock detects the session is locked, it immediately presents a Touch ID / password prompt and then automatically begins scanning your face once authenticated. No more manual workaround required.

## 📁 Shelf & Drag Detection
- **Precise File Drag Detection**: Fixed an issue where moving content around inside apps, selecting text on web pages, or dragging links could mistakenly trigger the Shelf to open. Now the Shelf only opens when you are genuinely dragging a real file from Finder or another app toward the notch.

## 🖱️ Notch Hover Stability
- **No More Accidental Closings**: Fixed an issue where the open notch could unexpectedly close while your cursor was still inside it, especially when moving between buttons or content within the notch area.
