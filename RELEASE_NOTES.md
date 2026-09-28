# NotchPulse v5.0.0 (Build 194) Release Notes

## 🚀 What's New in v5.0.0

### 📋 Smart Clipboard History Manager & Smooth Scroll Engine
- **Clipboard History Storage**: Log, filter, and access your recent clips, formatted text, URLs, code snippets, and hex colors directly inside the Notch with quick ⌘⌥V access.
- **AppKit Native Scroll Protection**: Integrated native AppKit scroll tracking (`NSView.boundsDidChangeNotification`) mirroring the split 1/2 Calendar engine. Browsing through copied history never triggers accidental notch collapse—the notch only closes when you reach the very last item and deliberately pull upward.

### 🗓️ Full Month Calendar Grid & Regional Lunar Calendar
- **Interactive 3-State Calendar Views**: Seamlessly switch between compact 1/2 view, 3/5 Month Grid + 2/5 Event Panel, and Full Page Month Grid view right inside the Notch.
- **Astronomical Regional Lunar Calculations**: Offline calculation for Vietnamese Lunar (Âm Lịch VN, UTC+7), Chinese Nongli (UTC+8), Islamic Hijri, Hebrew, Buddhist, and Persian calendar systems with dedicated Moon badges and day-cell lunar dates.

### 🖥️ Smart Multi-Display Architecture & Mutual Exclusion
- **Single Active Notch Rule**: Operating on a notch on any display now automatically collapses and unpins the notch on all other displays—guaranteeing strictly one active notch at any given moment across multi-monitor setups.
- **Screen-Isolated Shake Gestures**: Shaking a file to open the Notch Shelf now triggers exclusively on the monitor where your cursor is currently located, preventing accidental triggers on inactive displays.
- **Per-Screen Hover & Preview Routing**: Notch hover radar and width preview notifications are strictly scoped to the active monitor containing the cursor.

### 📁 Shelf Auto-Close Slider & Gesture Purity
- **Customizable Auto-Close Slider**: Added a dedicated auto-close delay slider (2s–20s) under Shelf Settings, letting you configure how long the shelf stays open while holding files.
- **Pure Shake-to-Open Activation**: Completely removed proximity and hover-drag triggers. The Notch Shelf now opens exclusively via deliberate left-right shake gestures when dragging content.
- **Informative Settings Note**: Added localized advisory notes in Shelf Settings explaining exact shake usage and auto-close timer behavior.

### 🔒 Lock Screen Auto-Collapse & Power Awareness
- **Universal Auto-Collapse**: Returning to the Lock Screen, waking from sleep, screensaver activation, or display sleep automatically collapses both Notch and Dynamic Island back to their resting compact closed state.
- **Face ID Setup Integration**: Face ID setup initiated from the onboarding tour intelligently routes to the monitor with the physical camera and exits smoothly back to the tour without terminating the application.

### 🎵 Centered Media Layout & Tight Spacing
- **Unified Media Geometry**: Song titles, artist details, playback progress bar, and control buttons are now tightly grouped and vertically centered in both Notch and Dynamic Island expanded views.
- **Responsive Slider**: Streamlined the music progress slider height (8px) and timestamps to prevent vertical clipping or awkward spacing.

### 🌐 Website Showcase & Regional Localization
- **12-Node Feature Constellation**: Redesigned the official landing page hero showcase with 12 evenly-distributed feature badges (including Lunar Calendar, Dynamic Island Mode, Lock Screen HUD, and Multi-Display Hub).
- **Regional Lunar Localization**: Fixed language switching for the regional lunar calendar preview, automatically adapting lunar dates, badges, and event titles to your selected language.

---

### 🐛 Bug Fixes & Stability
- Resolved cross-display pinned state conflicts between Shelf and Calendar singletons.
- Fixed onboarding tour step progression and high-contrast text legibility.
- Improved drag detector pasteboard change tracking and instant mouse-release reset.
