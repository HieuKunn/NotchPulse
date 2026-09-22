# NotchPulse v4.6.3

## 🔐 Face Unlock — Session Authentication Fix
- **Automatic re-authentication after lock**: Fixed a critical issue where Face Unlock would silently fail after your Mac woke from sleep or the screen was locked. Previously, the session key was cleared from memory on lock but the app never properly prompted for Touch ID or your password to restore it — meaning Face Unlock was stuck in a broken state until you manually went to Settings → Password and authenticated there. Now, when Face Unlock detects the session is locked, it immediately presents a Touch ID / password prompt and then automatically begins scanning your face once authenticated. No more manual workaround required.

## 📁 Shelf — Drag & Drop Fixes
- **No more Mission Control when dragging files**: Fixed a bug where dragging a file toward the notch area would trigger macOS Mission Control instead of opening the Shelf. The drag detector now always runs regardless of the "Expanded drag detection" setting — that setting only controls how far the detection zone extends beyond the notch edge.
- **Faster multi-file drops**: Fixed a lag where dropping multiple files into the Shelf processed them one by one. All files are now resolved in parallel so the entire drop completes as fast as the slowest single file.

## 🖱️ Notch Hover Stability
- **No More Accidental Closings**: Fixed an issue where the open notch could unexpectedly close while your cursor was still inside it, especially when moving between buttons or content within the notch area.
