## NotchPulse v5.7 (Build 491) - Important Release

This release introduces native Dock Window Previews, background performance optimizations, refined Spotlight Search compatibility, smarter notch drag detection, native app logos for Quick Share, and an authentic Apple macOS Tahoe Settings interface with native scroll-under frosted blur.

### ✨ What's New in This Release
- **Native Dock Window Previews**: Hover over any running app in your Dock to instantly preview all of its open windows. Click a preview thumbnail to bring that window into immediate focus, or hover over the preview card to access the quick-close button. Supports graceful Accessibility fallback mode out-of-the-box or live window screenshots.
- **Dedicated Dock Settings**: Customize preview card size (Small, Medium, Large), fine-tune hover trigger delays, toggle window titles, and view live Dock edge detection under **Settings > Hardware & System > Dock**.
- **Ultra-Efficient Background Performance**: Eliminated background idle polling in Launchpad and System Monitor, dropping background CPU usage down to near 0.0% and drastically extending battery life.
- **Native Spotlight Search Preserved**: Command + Space and menu bar Spotlight Search remain completely untouched—only genuine Applications launcher triggers open Launchpad Home.
- **Native App Logos in Quick Share**: Mail, Notes, Messages, Reminders, Shortcuts, Freeform, LINE, WPS Office, and Journal now display their authentic app icons with crisp square proportions across Settings and the Shelf.
- **Window-Drag Immunity & Accurate File-Drag Area**: Moving windows near the top of your screen no longer triggers closed-notch hover gestures, and the file-drag open area scales accurately from the closed notch size.

### 🎨 Settings UI Improvements
- **Authentic Apple Native Header & Scroll Blur**: Fixed the Settings detail header layout to match macOS Tahoe/Sequoia System Settings. Content at rest sits cleanly below the header without overlaps or empty gaps, and when scrolled, a native within-window frosted glass blur layer smoothly fades in underneath the header.
- **Clean Liquid Glass Controls**: Polished Quick Share service menus and Settings headers for consistent alignment, contrast, and native macOS HIG presentation.
