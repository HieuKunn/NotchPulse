import Foundation
import AppKit
@testable import NotchPulse

// MARK: - Minimal Lightweight Test Harness
final class TestSuite {
    var passedCount = 0
    var failedCount = 0
    var failureMessages: [String] = []

    func runTest(_ name: String, block: () throws -> Void) {
        print("  ▶ Running: \(name)...", terminator: " ")
        do {
            try block()
            passedCount += 1
            print("✅ PASSED")
        } catch {
            failedCount += 1
            let msg = "❌ FAILED: \(name) - \(error.localizedDescription)"
            failureMessages.append(msg)
            print("❌ FAILED (\(error.localizedDescription))")
        }
    }

    func assertTrue(_ condition: Bool, _ message: String = "Expected true, got false", file: StaticString = #file, line: UInt = #line) throws {
        if !condition {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message) at \(file):\(line)"])
        }
    }

    func assertFalse(_ condition: Bool, _ message: String = "Expected false, got true", file: StaticString = #file, line: UInt = #line) throws {
        if condition {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(message) at \(file):\(line)"])
        }
    }

    func assertEqual<T: Equatable>(_ a: T, _ b: T, _ message: String = "", file: StaticString = #file, line: UInt = #line) throws {
        if a != b {
            let msg = message.isEmpty ? "Expected \(a) == \(b)" : "\(message) (Expected \(a) == \(b))"
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(msg) at \(file):\(line)"])
        }
    }

    func report() -> Bool {
        print("\n==========================================")
        print("Test Results: \(passedCount) passed, \(failedCount) failed")
        print("==========================================")
        if !failureMessages.isEmpty {
            print("\nFailures:")
            for msg in failureMessages {
                print("  - \(msg)")
            }
            return false
        }
        return true
    }
}

let suite = TestSuite()

@main
struct TestApp {
    @MainActor
    static func main() {
        runAllTests()
        let success = suite.report()
        exit(success ? 0 : 1)
    }

    @MainActor
    static func runAllTests() {
        // MARK: - 1. Permissions Tests
        print("\n--- 1. Testing Permissions Logic ---")

        suite.runTest("Core vs Unneeded Permissions Classification") {
            let required: [AppPermissionKind] = [.camera, .accessibility, .calendar, .reminders, .musicAutomation]
            for perm in required {
                try suite.assertTrue(perm.isRequiredForCoreFeatures, "\(perm.rawValue) should be required")
            }

            let unneeded: [AppPermissionKind] = [.screenRecording, .fullDiskAccess]
            for perm in unneeded {
                try suite.assertFalse(perm.isRequiredForCoreFeatures, "\(perm.rawValue) should be unneeded")
            }
        }

        suite.runTest("PermissionStatus Satisfaction Check") {
            try suite.assertTrue(PermissionStatus.granted.isSatisfied)
            try suite.assertTrue(PermissionStatus.notNeeded.isSatisfied)
            try suite.assertFalse(PermissionStatus.denied.isSatisfied)
            try suite.assertFalse(PermissionStatus.notDetermined.isSatisfied)
            try suite.assertFalse(PermissionStatus.restricted.isSatisfied)
        }

        suite.runTest("Permission Deep Link URL Schemes") {
            for perm in AppPermissionKind.allCases {
                let (primary, fallback) = PermissionsManager.systemSettingsURL(for: perm)
                try suite.assertTrue(primary.absoluteString.hasPrefix("x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_"),
                                     "Primary URL \(primary) should be a valid System Settings extension deep link")
                try suite.assertTrue(fallback.absoluteString.hasPrefix("x-apple.systempreferences:com.apple.preference.security?Privacy_"),
                                     "Fallback URL \(fallback) should be a valid System Settings preference deep link")
            }
        }

        // MARK: - 2. Clipboard Production Function Tests
        print("\n--- 2. Testing Clipboard Manager Production Logic ---")

        suite.runTest("ClipboardManager.isSensitivePasteboard directly on markers and negative types") {
            // Positive test cases (password manager markers)
            try suite.assertTrue(ClipboardManager.isSensitivePasteboard([NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")]),
                                 "ConcealedType must be sensitive")
            try suite.assertTrue(ClipboardManager.isSensitivePasteboard([NSPasteboard.PasteboardType("org.nspasteboard.TransientType")]),
                                 "TransientType must be sensitive")
            try suite.assertTrue(ClipboardManager.isSensitivePasteboard([NSPasteboard.PasteboardType("org.nspasteboard.AutoGeneratedType")]),
                                 "AutoGeneratedType must be sensitive")
            try suite.assertTrue(ClipboardManager.isSensitivePasteboard([NSPasteboard.PasteboardType("com.agilebits.onepassword")]),
                                 "1Password marker must be sensitive")
            try suite.assertTrue(ClipboardManager.isSensitivePasteboard([
                NSPasteboard.PasteboardType.string,
                NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
            ]), "Mixed types containing ConcealedType must be sensitive")

            // Negative test cases (standard public types)
            try suite.assertFalse(ClipboardManager.isSensitivePasteboard([NSPasteboard.PasteboardType.string]),
                                  "Plain string must not be sensitive")
            try suite.assertFalse(ClipboardManager.isSensitivePasteboard([NSPasteboard.PasteboardType("public.utf8-plain-text")]),
                                  "UTF8 plain text must not be sensitive")
            try suite.assertFalse(ClipboardManager.isSensitivePasteboard([]),
                                  "Empty types list must not be sensitive")
            try suite.assertFalse(ClipboardManager.isSensitivePasteboard(nil),
                                  "nil types must not be sensitive")
        }

        suite.runTest("ClipboardItem Backward-Compatible JSON Decoding") {
            let legacyJSON = """
            {
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "contentString": "Hello World",
                "timestamp": 1700000000.0,
                "type": "text"
            }
            """.data(using: .utf8)!

            let decoder = JSONDecoder()
            let item = try decoder.decode(ClipboardItem.self, from: legacyJSON)
            try suite.assertEqual(item.contentString, "Hello World")
            try suite.assertFalse(item.isPinned, "isPinned should default to false when decoding legacy data")
        }

        suite.runTest("ClipboardManager.processHistoryInsertion: Pin Retention and Trim") {
            // Build an initial history with 1 pinned item and 2 unpinned items
            let pinnedItem = ClipboardItem(contentString: "Pinned Note", isPinned: true)
            let unpinned1 = ClipboardItem(contentString: "Note 1", isPinned: false)
            let unpinned2 = ClipboardItem(contentString: "Note 2", isPinned: false)
            let current = [pinnedItem, unpinned1, unpinned2]

            // Insert Note 3 with unpinned limit = 2
            let newItem = ClipboardItem(contentString: "Note 3", isPinned: false)
            let (updated, _) = ClipboardManager.processHistoryInsertion(
                currentHistory: current,
                newItem: newItem,
                unpinnedLimit: 2
            )

            // Result must retain the pinned item at the start, plus only the 2 newest unpinned items
            try suite.assertEqual(updated.count, 3)
            try suite.assertTrue(updated[0].isPinned && updated[0].contentString == "Pinned Note", "Pinned item must stay at index 0")
            try suite.assertEqual(updated[1].contentString, "Note 3", "New item must be at front of unpinned section")
            try suite.assertEqual(updated[2].contentString, "Note 1", "Next newest unpinned item")
            try suite.assertFalse(updated.contains(where: { $0.contentString == "Note 2" }), "Oldest unpinned Note 2 must be trimmed")
        }

        suite.runTest("ClipboardManager.processHistoryInsertion: Duplicate Keeps Pinned State") {
            // If an item was previously pinned, re-copying the same content must preserve isPinned = true
            let pinnedItem = ClipboardItem(contentString: "Secret Code", isPinned: true)
            let unpinned1 = ClipboardItem(contentString: "Other item", isPinned: false)
            let current = [pinnedItem, unpinned1]

            // User copies "Secret Code" again (default unpinned)
            let reCopied = ClipboardItem(contentString: "Secret Code", isPinned: false)
            let (updated, _) = ClipboardManager.processHistoryInsertion(
                currentHistory: current,
                newItem: reCopied,
                unpinnedLimit: 10
            )

            try suite.assertEqual(updated.count, 2, "Duplicate must replace existing entry")
            try suite.assertTrue(updated[0].isPinned, "Re-copied duplicate must inherit and preserve pinned status")
            try suite.assertEqual(updated[0].contentString, "Secret Code")
        }

        // MARK: - 3. Shelf Production Decoder Tests
        print("\n--- 3. Testing Shelf Persistence Production Decoder ---")

        suite.runTest("ShelfPersistenceService.decodeItems directly handles mixed valid and corrupted entries") {
            let mixedJSON = """
            [
                {"id": "A0000000-0000-0000-0000-000000000001", "isTemporary": false, "kind": {"type": "text", "value": "Valid First"}},
                {"id": "bad-entry-missing-kind-payload"},
                {"id": "A0000000-0000-0000-0000-000000000002", "isTemporary": false, "kind": {"type": "text", "value": "Valid Second"}}
            ]
            """.data(using: .utf8)!

            // Directly invoke the production decoder in ShelfPersistenceService
            let decodedItems = ShelfPersistenceService.decodeItems(from: mixedJSON)

            try suite.assertEqual(decodedItems.count, 2, "Decoder must skip corrupted item and recover 2 valid items")
            try suite.assertEqual(decodedItems[0].displayName, "Valid First", "Decoder must preserve item order")
            try suite.assertEqual(decodedItems[1].displayName, "Valid Second", "Decoder must preserve item order")
        }

        suite.runTest("ShelfItemKind Encoding & Decoding Parity") {
            let linkKind = ShelfItemKind.link(url: URL(string: "https://apple.com")!)
            let textKind = ShelfItemKind.text(string: "A shelf note")
            let fakeBookmarkData = "test-bookmark-data".data(using: .utf8)!
            let fileKind = ShelfItemKind.file(bookmark: fakeBookmarkData)

            let encoder = JSONEncoder()
            let decoder = JSONDecoder()

            let linkDecoded = try decoder.decode(ShelfItemKind.self, from: try encoder.encode(linkKind))
            let textDecoded = try decoder.decode(ShelfItemKind.self, from: try encoder.encode(textKind))
            let fileDecoded = try decoder.decode(ShelfItemKind.self, from: try encoder.encode(fileKind))

            try suite.assertEqual(linkKind, linkDecoded)
            try suite.assertEqual(textKind, textDecoded)
            try suite.assertEqual(fileKind, fileDecoded)
        }

        suite.runTest("ShelfItem Identity Keys Format") {
            let textItem = ShelfItem(kind: .text(string: "Quick note"))
            let linkItem = ShelfItem(kind: .link(url: URL(string: "https://example.com/test")!))

            try suite.assertEqual(textItem.identityKey, "text://Quick note")
            try suite.assertEqual(linkItem.identityKey, "link://https://example.com/test")
        }

        // MARK: - 4. Media & Lyrics Tests
        print("\n--- 4. Testing Media & Lyrics Production Logic ---")

        suite.runTest("MusicManager stripLRCTimestamps") {
            let lineWithTags = "[01:23.45]Hello world <01:24.00>foo<01:24.50>bar"
            let stripped = MusicManager.stripLRCTimestamps(from: lineWithTags)
            try suite.assertEqual(stripped, "Hello world foobar")
        }

        suite.runTest("MusicManager parseLRC Timestamp Precision & Ordering") {
            let sampleLRC = """
            [ti:Test Title]
            [ar:Test Artist]
            [01:05.50]Second line
            [00:10.00]First line
            [02:00.123]Third line with milliseconds
            """

            let parsed = MusicManager.parseLRC(sampleLRC)
            try suite.assertEqual(parsed.count, 3, "Expected 3 parsed lyrics lines")
            
            try suite.assertEqual(parsed[0].text, "First line")
            try suite.assertTrue(abs(parsed[0].time - 10.0) < 0.001)

            try suite.assertEqual(parsed[1].text, "Second line")
            try suite.assertTrue(abs(parsed[1].time - 65.5) < 0.001)

            try suite.assertEqual(parsed[2].text, "Third line with milliseconds")
            try suite.assertTrue(abs(parsed[2].time - 120.123) < 0.001)
        }

        suite.runTest("MusicManager parseLRC Handles Malformed Data Without Crashing") {
            let emptyResult = MusicManager.parseLRC("")
            try suite.assertTrue(emptyResult.isEmpty)

            let junkResult = MusicManager.parseLRC("random text without timestamps\\n[invalid:timestamp] foo")
            try suite.assertTrue(junkResult.isEmpty)
        }

        // MARK: - 5. Calendar Date Boundary Tests
        print("\n--- 5. Testing Calendar Date Boundary Logic ---")

        suite.runTest("CalendarManager startOfDay and endOfDay Safe Spanning") {
            let now = Date()
            let start = CalendarManager.startOfDay(now)
            let end = CalendarManager.endOfDay(for: now)

            let calendar = Calendar.current
            let startComponents = calendar.dateComponents([.hour, .minute, .second], from: start)
            try suite.assertEqual(startComponents.hour ?? -1, 0)
            try suite.assertEqual(startComponents.minute ?? -1, 0)
            try suite.assertEqual(startComponents.second ?? -1, 0)

            try suite.assertTrue(end > start, "endOfDay must be after startOfDay")
            
            let diff = end.timeIntervalSince(start)
            try suite.assertTrue(diff >= 82800 && diff <= 90000, "Day duration should be ~24h even across DST boundaries")
        }

        // MARK: - 6. Face ID Production Logic Tests
        print("\n--- 6. Testing Face ID Production Model & Action Availability ---")

        suite.runTest("NotchPulseFaceEnrollmentStore.determineActionAvailability: Load Failure Blocks All Mutations") {
            let avail = NotchPulseFaceEnrollmentStore.determineActionAvailability(
                loadFailure: "Keychain decryption failed (OSStatus -25308)",
                identitiesCount: 2,
                isFlowRunning: false
            )
            try suite.assertEqual(avail, .unreadable(reason: "Keychain decryption failed (OSStatus -25308)"))
            try suite.assertFalse(avail.canSetup, "Setup must be blocked on load failure")
            try suite.assertFalse(avail.canAddFace, "Add Face must be blocked on load failure to prevent overwriting disk enrollments")
            try suite.assertFalse(avail.canRecapture, "Recapture must be blocked on load failure")
            try suite.assertFalse(avail.canDelete, "Delete must be blocked on load failure")
            try suite.assertFalse(avail.canToggleIdentity, "Identity toggle must be blocked on load failure")
        }

        suite.runTest("NotchPulseFaceEnrollmentStore.determineActionAvailability: Load Success + Empty Allows Setup Only") {
            let avail = NotchPulseFaceEnrollmentStore.determineActionAvailability(
                loadFailure: nil,
                identitiesCount: 0,
                isFlowRunning: false
            )
            try suite.assertEqual(avail, .readyToSetup)
            try suite.assertTrue(avail.canSetup, "Setup must be enabled when store loaded successfully with 0 identities")
            try suite.assertFalse(avail.canAddFace, "Add Face is not used when no identities exist (Setup is used)")
            try suite.assertFalse(avail.canRecapture, "Cannot recapture when 0 identities")
            try suite.assertFalse(avail.canDelete, "Cannot delete when 0 identities")
        }

        suite.runTest("NotchPulseFaceEnrollmentStore.determineActionAvailability: Load Success + Identities Allows Management") {
            let avail = NotchPulseFaceEnrollmentStore.determineActionAvailability(
                loadFailure: nil,
                identitiesCount: 2,
                isFlowRunning: false
            )
            try suite.assertEqual(avail, .readyWithIdentities(count: 2))
            try suite.assertFalse(avail.canSetup, "Setup is not offered when already enrolled")
            try suite.assertTrue(avail.canAddFace, "Add Face must be enabled")
            try suite.assertTrue(avail.canRecapture, "Recapture must be enabled")
            try suite.assertTrue(avail.canDelete, "Delete must be enabled")
            try suite.assertTrue(avail.canToggleIdentity, "Toggle must be enabled")
        }

        suite.runTest("NotchPulseFaceEnrollmentStore.determineActionAvailability: Flow In Progress Blocks Concurrent Flows") {
            let avail = NotchPulseFaceEnrollmentStore.determineActionAvailability(
                loadFailure: nil,
                identitiesCount: 2,
                isFlowRunning: true
            )
            try suite.assertEqual(avail, .flowInProgress)
            try suite.assertFalse(avail.canSetup, "Cannot start flow while another is running")
            try suite.assertFalse(avail.canAddFace, "Cannot start Add Face while another is running")
            try suite.assertFalse(avail.canRecapture, "Cannot start Recapture while another is running")
            try suite.assertFalse(avail.canDelete, "Cannot delete while flow is running")
            try suite.assertFalse(avail.canToggleIdentity, "Cannot toggle identity while flow is running")
        }

        suite.runTest("AutoLockInterval Slider Conversion & Defaults") {
            try suite.assertEqual(AutoLockInterval.from(sliderIndex: 0), .oneDay)
            try suite.assertEqual(AutoLockInterval.from(sliderIndex: 1), .sevenDays)
            try suite.assertEqual(AutoLockInterval.from(sliderIndex: 2), .fourteenDays)
            try suite.assertEqual(AutoLockInterval.from(sliderIndex: 3), .thirtyDays)
            
            try suite.assertEqual(AutoLockInterval.from(sliderIndex: -5), .sevenDays)
            try suite.assertEqual(AutoLockInterval.from(sliderIndex: 99), .sevenDays)
        }

        suite.runTest("FaceSample QualityTier Bucketing") {
            let unratedSample = FaceSample(embedding: [0.1], pose: nil, capturedAt: Date(), quality: nil)
            try suite.assertEqual(unratedSample.qualityTier, .unrated)

            let poorSample = FaceSample(embedding: [0.1], pose: nil, capturedAt: Date(), quality: 0.35)
            try suite.assertEqual(poorSample.qualityTier, .poor)

            let fairSample = FaceSample(embedding: [0.1], pose: nil, capturedAt: Date(), quality: 0.45)
            try suite.assertEqual(fairSample.qualityTier, .fair)

            let goodSample = FaceSample(embedding: [0.1], pose: nil, capturedAt: Date(), quality: 0.85)
            try suite.assertEqual(goodSample.qualityTier, .good)
        }

        suite.runTest("UnlockTrigger Identification") {
            let all = UnlockTrigger.allCases
            try suite.assertEqual(all.count, 3)
            try suite.assertTrue(all.contains(.onWake))
            try suite.assertTrue(all.contains(.onLock))
            try suite.assertTrue(all.contains(.onSpace))
        }

        // MARK: - 7. Calendar DST Date Boundary Tests
        print("\n--- 7. Testing Calendar DST Date Boundary ---")

        suite.runTest("CalendarManager.exclusiveEndOfDay across 23h & 25h DST Days") {
            guard let timeZone = TimeZone(identifier: "America/New_York") else {
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing America/New_York timezone"])
            }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone

            // Spring forward 2024: March 10, 2024 (23 hours long day)
            var components = DateComponents()
            components.year = 2024
            components.month = 3
            components.day = 10
            components.hour = 12
            guard let march10Noon = cal.date(from: components) else {
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed creating March 10 date"])
            }

            let marchEndOfDay = CalendarManager.exclusiveEndOfDay(for: march10Noon, calendar: cal)
            let marchNextStart = cal.startOfDay(for: marchEndOfDay)
            try suite.assertEqual(marchEndOfDay, marchNextStart, "exclusiveEndOfDay must land exactly on midnight of the next day on 23h DST day")
            let marchDayComp = cal.component(.day, from: marchEndOfDay)
            try suite.assertEqual(marchDayComp, 11, "End of March 10 must be start of March 11")

            // Fall back 2024: November 3, 2024 (25 hours long day)
            components.month = 11
            components.day = 3
            components.hour = 12
            guard let nov3Noon = cal.date(from: components) else {
                throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed creating Nov 3 date"])
            }

            let novEndOfDay = CalendarManager.exclusiveEndOfDay(for: nov3Noon, calendar: cal)
            let novNextStart = cal.startOfDay(for: novEndOfDay)
            try suite.assertEqual(novEndOfDay, novNextStart, "exclusiveEndOfDay must land exactly on midnight of the next day on 25h DST day")
            let novDayComp = cal.component(.day, from: novEndOfDay)
            try suite.assertEqual(novDayComp, 4, "End of November 3 must be start of November 4")
        }

        // MARK: - 8. Display Target Selection Tests
        print("\n--- 8. Testing Display Target Selection ---")

        suite.runTest("BrightnessManager.determineActiveDisplay: Retain, Fallback, and Empty") {
            let builtin = DisplayTarget(
                id: 1,
                isBuiltin: true,
                localizedName: "Built-in Retina",
                shortName: "Retina",
                isSidecarOrVirtual: false
            )
            let external1 = DisplayTarget(
                id: 2,
                isBuiltin: false,
                localizedName: "Dell UltraSharp 4K",
                shortName: "Dell 4K",
                isSidecarOrVirtual: false
            )
            let external2 = DisplayTarget(
                id: 3,
                isBuiltin: false,
                localizedName: "LG 5K UltraFine",
                shortName: "LG 5K",
                isSidecarOrVirtual: false
            )

            let available = [builtin, external1, external2]

            // Case 1: Current ID exists in available list -> retain it
            let retained = BrightnessManager.determineActiveDisplay(currentID: 2, availableDisplays: available)
            try suite.assertEqual(retained?.id, 2, "Should retain external display if it is still connected")

            // Case 2: Current ID was disconnected (e.g. ID 99) -> fallback to builtin
            let fallback = BrightnessManager.determineActiveDisplay(currentID: 99, availableDisplays: available)
            try suite.assertEqual(fallback?.id, 1, "Should fallback to builtin display if current disconnected")

            // Case 3: Current ID nil -> fallback to builtin
            let nilFallback = BrightnessManager.determineActiveDisplay(currentID: nil, availableDisplays: available)
            try suite.assertEqual(nilFallback?.id, 1, "Should fallback to builtin display if current is nil")

            // Case 4: No builtin available (desktop Mac) -> fallback to first available
            let desktops = [external1, external2]
            let desktopFallback = BrightnessManager.determineActiveDisplay(currentID: 99, availableDisplays: desktops)
            try suite.assertEqual(desktopFallback?.id, 2, "Should fallback to first display on desktop Mac")

            // Case 5: Empty list -> nil
            let emptyResult = BrightnessManager.determineActiveDisplay(currentID: 1, availableDisplays: [])
            try suite.assertTrue(emptyResult == nil, "Empty available list must return nil")
        }

        // MARK: - 9. Bluetooth Headphone Debounce Tests
        print("\n--- 9. Testing Bluetooth Headphone Debounce ---")

        suite.runTest("BluetoothHeadphoneManager.shouldAnnounceBattery: Debounce & Thresholds") {
            let now = Date()

            // 1. Initial announcement (no previous level) -> always true
            let initial = BluetoothHeadphoneManager.shouldAnnounceBattery(
                previousLevel: nil,
                newLevel: 85,
                lastAnnouncedAt: .distantPast,
                now: now
            )
            try suite.assertTrue(initial, "Initial battery reading should always be announced")

            // 2. Identical level within debounce interval -> false
            let sameLevelRecent = BluetoothHeadphoneManager.shouldAnnounceBattery(
                previousLevel: 85,
                newLevel: 85,
                lastAnnouncedAt: now.addingTimeInterval(-2),
                now: now,
                minInterval: 10.0
            )
            try suite.assertFalse(sameLevelRecent, "Identical battery level within interval must be debounced")

            // 3. Minor fluctuation (< 5%) within debounce interval -> false
            let minorFluctuation = BluetoothHeadphoneManager.shouldAnnounceBattery(
                previousLevel: 85,
                newLevel: 84,
                lastAnnouncedAt: now.addingTimeInterval(-3),
                now: now,
                minInterval: 10.0,
                significantChangeThreshold: 5
            )
            try suite.assertFalse(minorFluctuation, "Minor fluctuation (1%) within interval must be debounced")

            // 4. Significant change (>= 5%) within interval -> true
            let significantChange = BluetoothHeadphoneManager.shouldAnnounceBattery(
                previousLevel: 85,
                newLevel: 75,
                lastAnnouncedAt: now.addingTimeInterval(-3),
                now: now,
                minInterval: 10.0,
                significantChangeThreshold: 5
            )
            try suite.assertTrue(significantChange, "Significant change (10%) should announce immediately")

            // 5. Minor change but interval expired (>= 10s) -> true
            let expiredChange = BluetoothHeadphoneManager.shouldAnnounceBattery(
                previousLevel: 85,
                newLevel: 83,
                lastAnnouncedAt: now.addingTimeInterval(-15),
                now: now,
                minInterval: 10.0
            )
            try suite.assertTrue(expiredChange, "Change after minInterval expired should announce")

            // 6. Identical level even after interval expired -> false (no point spamming unchanged HUD)
            let expiredSame = BluetoothHeadphoneManager.shouldAnnounceBattery(
                previousLevel: 85,
                newLevel: 85,
                lastAnnouncedAt: now.addingTimeInterval(-20),
                now: now,
                minInterval: 10.0
            )
            try suite.assertFalse(expiredSame, "Unchanged battery level should not re-announce after interval")
        }

        // MARK: - 10. System Monitor Fan State Tests
        print("\n--- 10. Testing System Monitor Fan State ---")

        suite.runTest("SystemMonitorManager.categorizeFanState: Fanless vs Active") {
            // M-series MacBook Air (fanless)
            try suite.assertEqual(
                SystemMonitorManager.categorizeFanState(rpm: 0, isFanlessMachine: true),
                .fanless,
                "Fanless machine with 0 RPM should be categorized as .fanless"
            )
            try suite.assertEqual(
                SystemMonitorManager.categorizeFanState(rpm: 2500, isFanlessMachine: true),
                .fanless,
                "Fanless machine with sensor noise should still be .fanless"
            )

            // MacBook Pro with fans (idle)
            try suite.assertEqual(
                SystemMonitorManager.categorizeFanState(rpm: 0, isFanlessMachine: false),
                .idle(rpm: 0),
                "Pro machine with stopped fans should be .idle"
            )
            try suite.assertEqual(
                SystemMonitorManager.categorizeFanState(rpm: 1000, isFanlessMachine: false),
                .idle(rpm: 1000),
                "Pro machine below 1200 RPM should be .idle"
            )

            // MacBook Pro with fans (active)
            try suite.assertEqual(
                SystemMonitorManager.categorizeFanState(rpm: 2400, isFanlessMachine: false),
                .active(rpm: 2400),
                "Pro machine above 1200 RPM should be .active"
            )
            try suite.assertEqual(
                SystemMonitorManager.categorizeFanState(rpm: 6500, isFanlessMachine: false),
                .active(rpm: 6500),
                "Pro machine at max RPM should be .active"
            )
        }

        // MARK: - 11. Media Gating Policy Tests
        print("\n--- 11. Testing Media Gating Policy ---")

        suite.runTest("MediaGatingPolicy.shouldRunPlaybackTimers Battery Optimization") {
            // Feature disabled: must not run regardless of app/player state
            try suite.assertFalse(
                MediaGatingPolicy.shouldRunPlaybackTimers(isAppActive: true, isFeatureEnabled: false, hasActivePlayer: true),
                "Timers must not run when media feature is disabled"
            )

            // App inactive/hidden: must not run to save energy
            try suite.assertFalse(
                MediaGatingPolicy.shouldRunPlaybackTimers(isAppActive: false, isFeatureEnabled: true, hasActivePlayer: true),
                "Timers must not run when app is inactive"
            )

            // No active player: must not run
            try suite.assertFalse(
                MediaGatingPolicy.shouldRunPlaybackTimers(isAppActive: true, isFeatureEnabled: true, hasActivePlayer: false),
                "Timers must not run when no music is playing"
            )

            // All active: must run
            try suite.assertTrue(
                MediaGatingPolicy.shouldRunPlaybackTimers(isAppActive: true, isFeatureEnabled: true, hasActivePlayer: true),
                "Timers should run when app is active, feature enabled, and track is playing"
            )
        }

        // MARK: - 12. Music Automation Status Combinations
        print("\n--- 12. Testing Music Automation Combinations ---")

        suite.runTest("MediaAutomationPermissionHelper.determineCombinedStatus Combinations") {
            // Both authorized -> granted
            try suite.assertEqual(
                MediaAutomationPermissionHelper.determineCombinedStatus(spotify: .granted, appleMusic: .granted),
                .granted
            )

            // One authorized, other notDetermined -> partiallyAuthorized
            try suite.assertEqual(
                MediaAutomationPermissionHelper.determineCombinedStatus(spotify: .granted, appleMusic: .notDetermined),
                .partiallyAuthorized
            )
            try suite.assertEqual(
                MediaAutomationPermissionHelper.determineCombinedStatus(spotify: .notDetermined, appleMusic: .granted),
                .partiallyAuthorized
            )

            // One authorized, other denied -> partiallyAuthorized
            try suite.assertEqual(
                MediaAutomationPermissionHelper.determineCombinedStatus(spotify: .granted, appleMusic: .denied),
                .partiallyAuthorized
            )
            try suite.assertEqual(
                MediaAutomationPermissionHelper.determineCombinedStatus(spotify: .denied, appleMusic: .granted),
                .partiallyAuthorized
            )

            // Both denied -> denied
            try suite.assertEqual(
                MediaAutomationPermissionHelper.determineCombinedStatus(spotify: .denied, appleMusic: .denied),
                .denied
            )

            // Both notDetermined -> notDetermined
            try suite.assertEqual(
                MediaAutomationPermissionHelper.determineCombinedStatus(spotify: .notDetermined, appleMusic: .notDetermined),
                .notDetermined
            )
        }

        // MARK: - 13. Clipboard Search Filtering Tests
        print("\n--- 13. Testing Clipboard Search Filtering ---")

        suite.runTest("ClipboardManager.filterHistory: Query Matching") {
            let item1 = ClipboardItem(contentString: "Hello world Swift coding")
            let item2 = ClipboardItem(contentString: "NotchPulse MacOS project")
            let item3 = ClipboardItem(contentString: "Tiếng Việt có dấu")
            let imageItem = ClipboardItem(type: .image, contentString: nil, thumbnailData: Data(), diskFilePath: "/Users/test/screenshot_app.png")

            let items = [item1, item2, item3, imageItem]

            // 1. Empty query returns all
            let all = ClipboardManager.filterHistory(items: items, query: "")
            try suite.assertEqual(all.count, 4)

            // 2. Case-insensitive substring match
            let swiftMatch = ClipboardManager.filterHistory(items: items, query: "swift")
            try suite.assertEqual(swiftMatch.count, 1)
            try suite.assertEqual(swiftMatch.first?.contentString, "Hello world Swift coding")

            // 3. Diacritic-insensitive match ("tieng viet" matches "Tiếng Việt")
            let diacriticMatch = ClipboardManager.filterHistory(items: items, query: "tieng viet")
            try suite.assertEqual(diacriticMatch.count, 1)
            try suite.assertEqual(diacriticMatch.first?.contentString, "Tiếng Việt có dấu")

            // 4. Image filename match
            let imageMatch = ClipboardManager.filterHistory(items: items, query: "screenshot")
            try suite.assertEqual(imageMatch.count, 1)
            try suite.assertEqual(imageMatch.first?.diskFilePath, "/Users/test/screenshot_app.png")

            // 5. Non-matching query
            let noMatch = ClipboardManager.filterHistory(items: items, query: "xyzNonExistent")
            try suite.assertEqual(noMatch.count, 0)
        }

        // MARK: - 14. YouTubeMusicController Artwork Response Guard Tests
        print("\n--- 14. Testing YouTube Music Artwork Request Identity Guard ---")

        suite.runTest("YouTubeMusicController.isArtworkResponseValid Stale Artwork Invalidation") {
            let identity = ArtworkRequestIdentity(
                requestId: 42,
                targetURLString: "https://example.com/artwork42.jpg",
                trackTitle: "Current Song",
                trackArtist: "Current Artist"
            )

            // 1. Exact match, not cancelled -> true
            let valid = YouTubeMusicController.isArtworkResponseValid(
                expectedIdentity: identity,
                currentRequestId: 42,
                currentURLString: "https://example.com/artwork42.jpg",
                currentTrackTitle: "Current Song",
                currentTrackArtist: "Current Artist",
                isTaskCancelled: false
            )
            try suite.assertTrue(valid, "Artwork response matching active request identity must be accepted")

            // 2. Task cancelled -> false
            let cancelled = YouTubeMusicController.isArtworkResponseValid(
                expectedIdentity: identity,
                currentRequestId: 42,
                currentURLString: "https://example.com/artwork42.jpg",
                currentTrackTitle: "Current Song",
                currentTrackArtist: "Current Artist",
                isTaskCancelled: true
            )
            try suite.assertFalse(cancelled, "Cancelled fetch task must reject response")

            // 3. User skipped to next track (incremented requestId) -> false
            let staleRequestId = YouTubeMusicController.isArtworkResponseValid(
                expectedIdentity: identity,
                currentRequestId: 43,
                currentURLString: "https://example.com/artwork43.jpg",
                currentTrackTitle: "Next Song",
                currentTrackArtist: "Next Artist",
                isTaskCancelled: false
            )
            try suite.assertFalse(staleRequestId, "Stale request generation ID from skipped track must be rejected")

            // 4. Mismatched URL -> false
            let mismatchedURL = YouTubeMusicController.isArtworkResponseValid(
                expectedIdentity: identity,
                currentRequestId: 42,
                currentURLString: "https://example.com/different.jpg",
                currentTrackTitle: "Current Song",
                currentTrackArtist: "Current Artist",
                isTaskCancelled: false
            )
            try suite.assertFalse(mismatchedURL, "Mismatched artwork URL must be rejected")

            // 5. Mismatched track title/artist -> false
            let mismatchedTitle = YouTubeMusicController.isArtworkResponseValid(
                expectedIdentity: identity,
                currentRequestId: 42,
                currentURLString: "https://example.com/artwork42.jpg",
                currentTrackTitle: "Another Song",
                currentTrackArtist: "Current Artist",
                isTaskCancelled: false
            )
            try suite.assertFalse(mismatchedTitle, "Response with mismatched track title must be rejected")

            // 6. Controller reset/deactivated (currentURLString is nil) -> false
            let resetController = YouTubeMusicController.isArtworkResponseValid(
                expectedIdentity: identity,
                currentRequestId: 43,
                currentURLString: nil,
                currentTrackTitle: "",
                currentTrackArtist: "",
                isTaskCancelled: false
            )
            try suite.assertFalse(resetController, "Reset controller with nil artwork URL must reject late responses")
        }
    }
}
