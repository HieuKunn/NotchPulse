# NotchPulse v4.6.6

## 🎵 Lock Screen Media Display Routing
- **Smart Display Mode Awareness**: When "Show on all displays" is active, media player & lyrics on the lock screen cleanly frame on `NSScreen.main`. When a specific display is selected in settings, media player routes strictly to that designated display.

## 🌐 Instant Web Reload & Cache Invalidation
- **Purged Stale Web Caches**: Added automatic ServiceWorker unregistration and Cache-Control headers to ensure standard `Cmd + R` reloads always fetch the latest `v4.6.6` release instantly without requiring `Cmd + Shift + R`.

