import AppKit
import Defaults
import SwiftUI

struct CalendarSettingsPage: View {
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showCalendar) var showCalendar: Bool
    @Default(.hideCompletedReminders) var hideCompletedReminders
    @Default(.hideAllDayEvents) var hideAllDayEvents
    @Default(.autoScrollToNextEvent) var autoScrollToNextEvent
    @Default(.showFullEventTitles) var showFullEventTitles
    @Default(.appLanguage) private var appLanguage
    @Default(.alternateCalendarType) private var alternateCalendarType
    @Default(.showLunarCalendar) private var showLunarCalendar

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $showCalendar) {
                    Text(loc("Enable Calendar"))
                        .font(.headline)
                    Text(loc("Show upcoming calendar events, reminders, and lunar dates in the Notch."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
            }

            Section(header: Text(loc("Display Options"))) {
                Toggle(loc("Hide completed reminders"), isOn: $hideCompletedReminders)
                Toggle(loc("Hide all-day events"), isOn: $hideAllDayEvents)
                Toggle(loc("Auto-scroll to next event"), isOn: $autoScrollToNextEvent)
                Toggle(loc("Always show full event titles"), isOn: $showFullEventTitles)
            }
            .disabled(!showCalendar)

            Section(header: Text(loc("Lunar Calendar Region"))) {
                Picker(loc("Lunar Calendar Region"), selection: $alternateCalendarType) {
                    ForEach(AlternateCalendarType.allCases) { type in
                        Text(type.localizedName(for: appLanguage)).tag(type)
                    }
                }

                Toggle(loc("Show lunar date in month grid"), isOn: $showLunarCalendar)

                Text(loc("Supports lunar calendar calculation according to local regional timezone (Vietnam UTC+7, Taiwan / China UTC+8)."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!showCalendar)

            Section(header: Text(loc("Calendars"))) {
                if calendarManager.calendarAuthorizationStatus != .fullAccess {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc("Calendar access is denied. Please enable it in System Settings."))
                            .foregroundStyle(.red)
                            .font(.subheadline)
                        Button(loc("Open Calendar Settings")) {
                            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                                NSWorkspace.shared.open(settingsURL)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(calendarManager.eventCalendars, id: \.id) { calendar in
                        Toggle(
                            isOn: Binding(
                                get: { calendarManager.getCalendarSelected(calendar) },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarSelected(calendar, isSelected: isSelected)
                                    }
                                }
                            )
                        ) {
                            Text(calendar.title)
                        }
                        .tint(lighterColor(from: calendar.color))
                        .disabled(!showCalendar)
                    }
                }
            }

            Section(header: Text(loc("Reminders"))) {
                if calendarManager.reminderAuthorizationStatus != .fullAccess {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(loc("Reminder access is denied. Please enable it in System Settings."))
                            .foregroundStyle(.red)
                            .font(.subheadline)
                        Button(loc("Open Reminder Settings")) {
                            if let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders") {
                                NSWorkspace.shared.open(settingsURL)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                } else {
                    ForEach(calendarManager.reminderLists, id: \.id) { calendar in
                        Toggle(
                            isOn: Binding(
                                get: { calendarManager.getCalendarSelected(calendar) },
                                set: { isSelected in
                                    Task {
                                        await calendarManager.setCalendarSelected(calendar, isSelected: isSelected)
                                    }
                                }
                            )
                        ) {
                            Text(calendar.title)
                        }
                        .tint(lighterColor(from: calendar.color))
                        .disabled(!showCalendar)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            Task {
                await calendarManager.checkCalendarAuthorization()
                await calendarManager.checkReminderAuthorization()
            }
        }
    }
}
