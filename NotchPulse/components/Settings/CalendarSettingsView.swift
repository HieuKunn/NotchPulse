import AppKit
import Defaults
import EventKit
import SwiftUI

struct CalendarSettingsView: View {
    @Environment(\.settingsHighlightedId) private var highlightedId
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.appLanguage) private var appLanguage
    @Default(.alternateCalendarType) private var alternateCalendarType
    @Default(.showLunarCalendar) private var showLunarCalendar

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc("Enable Calendar"))
                            .font(.headline)
                        Text(loc("Show upcoming calendar events, reminders, and lunar dates in the Notch."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 40)
                    Defaults.Toggle("", key: .showCalendar)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
            .id("calendar_integration")
            .searchHighlight(highlightedId == "calendar_integration")

            Section(header: Text(loc("Display Options")).id("calendar_options")) {
                Defaults.Toggle(key: .hideCompletedReminders) {
                    Text(loc("Hide completed reminders"))
                }
                Defaults.Toggle(key: .hideAllDayEvents) {
                    Text(loc("Hide all-day events"))
                }
                Defaults.Toggle(key: .autoScrollToNextEvent) {
                    Text(loc("Auto-scroll to next event"))
                }
                Defaults.Toggle(key: .showFullEventTitles) {
                    Text(loc("Always show full event titles"))
                }
            }
            .id("calendar_options")
            .searchHighlight(highlightedId == "calendar_options")

            Section(header: Text(loc("Lunar Calendar Region")).id("calendar_alternate")) {
                Picker(loc("Lunar Calendar Region"), selection: $alternateCalendarType) {
                    ForEach(AlternateCalendarType.allCases) { type in
                        Text(type.localizedName(for: appLanguage)).tag(type)
                    }
                }

                Defaults.Toggle(key: .showLunarCalendar) {
                    Text(loc("Show lunar date in month grid"))
                }

                Text(loc("Supports lunar calendar calculation according to local regional timezone (Vietnam UTC+7, Taiwan / China UTC+8)."))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .id("calendar_alternate")
            .searchHighlight(highlightedId == "calendar_alternate")

            Section(header: Text(loc("Calendars"))) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    Text(loc("Calendar access is denied. Please enable it in System Settings."))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(loc("Open Calendar Settings")) {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .tint(Color(nsColor: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }

            Section(header: Text(loc("Reminders"))) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    Text(loc("Reminder access is denied. Please enable it in System Settings."))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button(loc("Open Reminder Settings")) {
                        if let settingsURL = URL(
                            string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                        ) {
                            NSWorkspace.shared.open(settingsURL)
                        }
                    }
                } else {
                    List {
                        ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                            Toggle(
                                isOn: Binding(
                                    get: { calendarManager.getCalendarSelected(calendar) },
                                    set: { isSelected in
                                        Task {
                                            await calendarManager.setCalendarSelected(
                                                calendar, isSelected: isSelected)
                                        }
                                    }
                                )
                            ) {
                                Text(calendar.title)
                            }
                            .tint(Color(nsColor: calendar.color))
                            .disabled(!showCalendar)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .accentColor(.effectiveAccent)
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}

typealias CalendarSettings = CalendarSettingsView

