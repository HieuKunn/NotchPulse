//
//  NotchPulseCalendar.swift
//  NotchPulse
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Defaults
import SwiftUI

struct Config {
    var past: Int = 730    // 2 full years in the past (730 days)
    var future: Int = 1095 // 3 full years in the future (1095 days)
    var steps: Int = 1     // Each step is one day
    var spacing: CGFloat = 2
    var showsText: Bool = true
    var offset: Int = 2    // Number of dates to the left of the selected date
}

private let dayOfWeekFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "E"
    return formatter
}()

private struct CalendarScrollWheelHelper: NSViewRepresentable {
    var onVisibleCenterChange: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> HelperView {
        let view = HelperView()
        view.onVisibleCenterChange = onVisibleCenterChange
        return view
    }

    func updateNSView(_ nsView: HelperView, context: Context) {
        nsView.onVisibleCenterChange = onVisibleCenterChange
        nsView.checkSetup()
    }

    class HelperView: NSView {
        var onVisibleCenterChange: ((CGFloat) -> Void)?
        private var monitor: Any?
        private var boundsObserver: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                checkSetup()
                DispatchQueue.main.async { [weak self] in
                    self?.checkSetup()
                }
            } else {
                removeMonitor()
                removeBoundsObserver()
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if superview != nil {
                checkSetup()
            }
        }

        deinit {
            removeMonitor()
            removeBoundsObserver()
        }

        private func removeMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        private func removeBoundsObserver() {
            if let bo = boundsObserver {
                NotificationCenter.default.removeObserver(bo)
                boundsObserver = nil
            }
        }

        func checkSetup() {
            guard window != nil else { return }
            setupBoundsObserver()
            setupMonitor()
        }

        private func setupBoundsObserver() {
            guard boundsObserver == nil else { return }
            guard let scrollView = enclosingScrollView else { return }
            let clipView = scrollView.contentView
            clipView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: clipView,
                queue: .main
            ) { [weak self, weak clipView] _ in
                guard let self = self, let cv = clipView else { return }
                let visibleCenterInClipView = CGPoint(x: cv.bounds.midX, y: cv.bounds.midY)
                let centerInHStack = self.convert(visibleCenterInClipView, from: cv)
                self.onVisibleCenterChange?(centerInHStack.x)
            }
        }

        private func setupMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self = self,
                      let window = self.window,
                      event.window === window,
                      let scrollView = self.enclosingScrollView else {
                    return event
                }

                let locationInWindow = event.locationInWindow
                let locationInSV = scrollView.convert(locationInWindow, from: nil)
                guard scrollView.bounds.contains(locationInSV) else {
                    return event
                }

                // If user scrolls vertically (physical mouse wheel or vertical gesture),
                // convert deltaY to smooth horizontal scrolling of this NSScrollView!
                if event.scrollingDeltaX == 0 && event.scrollingDeltaY != 0 {
                    let clipView = scrollView.contentView
                    var origin = clipView.bounds.origin
                    let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 16.0
                    let delta = event.scrollingDeltaY * multiplier
                    let docWidth = scrollView.documentView?.bounds.width ?? 0
                    let maxX = max(0, docWidth - clipView.bounds.width)
                    origin.x = min(maxX, max(0, origin.x - delta))
                    clipView.scroll(to: origin)
                    scrollView.reflectScrolledClipView(clipView)
                    return nil // Handled: prevent event from closing notch or other handlers
                }

                return event
            }
        }
    }
}

struct CalendarDateButton: View {
    let date: Date
    let isSelected: Bool
    let id: Int
    let onClick: () -> Void
    @State private var isHovered: Bool = false

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    private var dayString: String {
        dayOfWeekFormatter.string(from: date)
    }

    private var dayNumberString: String {
        "\(Calendar.current.component(.day, from: date))"
    }

    var body: some View {
        Button(action: onClick) {
            VStack(spacing: 4) {
                Text(dayString)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : Color(white: 0.65))

                ZStack {
                    if isToday {
                        Circle()
                            .fill(isSelected ? Color.clear : Color.effectiveAccentBackground)
                            .frame(width: 24, height: 24)
                    }
                    Circle()
                        .stroke(isSelected ? Color.clear : (isToday ? Color.effectiveAccentBackground : Color.clear), lineWidth: 1)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .stroke(Color.gray.opacity(0.3), lineWidth: 0)
                        )
                    Text(dayNumberString)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : Color(white: isToday ? 0.9 : 0.65))
                }
            }
            .frame(width: 36, height: 50)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.effectiveAccentBackground : (isHovered ? Color.white.opacity(0.08) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .id(id)
    }
}

struct WheelPicker: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Binding var selectedDate: Date
    @Binding var displayedDate: Date
    @State private var scrollPosition: Int?
    @State private var haptics: Bool = false
    let config: Config

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: config.spacing) {
                let spacerNum = config.offset
                let dateCount = totalDateItems()
                let totalItems = dateCount + 2 * spacerNum
                ForEach(0..<totalItems, id: \.self) { index in
                    if index < spacerNum || index >= spacerNum + dateCount {
                        // Leading/trailing spacers sized to match a date cell
                        Spacer()
                            .frame(width: 36, height: 50)
                            .id(index)
                    } else {
                        let date = dateForItemIndex(index: index, spacerNum: spacerNum)
                        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
                        CalendarDateButton(date: date, isSelected: isSelected, id: index) {
                            selectDate(date, index: index)
                        }
                    }
                }
            }
            .frame(height: 50)
            .background(CalendarScrollWheelHelper(onVisibleCenterChange: { visibleCenterX in
                let itemWidth = 36.0 + config.spacing
                let floatIndex = (visibleCenterX - 18.0) / itemWidth
                let index = Int(round(floatIndex))
                let date = dateForItemIndex(index: index, spacerNum: config.offset)
                if Calendar.current.component(.month, from: date) != Calendar.current.component(.month, from: displayedDate) ||
                   Calendar.current.component(.year, from: date) != Calendar.current.component(.year, from: displayedDate) {
                    displayedDate = date
                }
            }))
        }
        .scrollIndicators(.never)
        .scrollPosition(id: $scrollPosition, anchor: .center)
        .safeAreaPadding(.horizontal)
        .sensoryFeedback(.alignment, trigger: haptics)
        .onAppear {
            scrollToToday(config: config)
        }
        .onChange(of: scrollPosition) { _, newPosition in
            guard let newIndex = newPosition else { return }
            let date = dateForItemIndex(index: newIndex, spacerNum: config.offset)
            if Calendar.current.component(.month, from: date) != Calendar.current.component(.month, from: displayedDate) ||
               Calendar.current.component(.year, from: date) != Calendar.current.component(.year, from: displayedDate) {
                displayedDate = date
            }
        }
        // When parent updates the bound selectedDate (e.g., view reopen or external select), center the wheel on it
        .onChange(of: selectedDate) { _, newValue in
            let targetIndex = indexForDate(newValue)
            if scrollPosition != targetIndex {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    scrollPosition = targetIndex
                }
            }
            displayedDate = newValue
        }
    }

    private func selectDate(_ date: Date, index: Int) {
        selectedDate = date
        displayedDate = date
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            scrollPosition = index
        }
        if Defaults[.enableHaptics] {
            haptics.toggle()
        }
        Task { @MainActor in
            await calendarManager.updateCurrentDate(date)
        }
    }

    private func scrollToToday(config: Config) {
        let today = Date()
        scrollPosition = indexForDate(today)
        selectedDate = today
        displayedDate = today
    }

    // MARK: - Index/Date mapping with steps and spacers
    private func indexForDate(_ date: Date) -> Int {
        let spacerNum = config.offset
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.startOfDay(for: cal.date(byAdding: .day, value: -config.past, to: today) ?? today)
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: startDate, to: target).day ?? 0
        let stepIndex = max(0, min(days / max(config.steps, 1), totalDateItems() - 1))
        return spacerNum + stepIndex
    }

    private func dateForItemIndex(index: Int, spacerNum: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let startDate = cal.date(byAdding: .day, value: -config.past, to: today) ?? today
        let stepIndex = max(0, min(totalDateItems() - 1, index - spacerNum))
        return cal.date(byAdding: .day, value: stepIndex * max(config.steps, 1), to: startDate) ?? today
    }

    private func totalDateItems() -> Int {
        let range = config.past + config.future
        let step = max(config.steps, 1)
        return Int(ceil(Double(range) / Double(step))) + 1
    }
}

struct CalendarView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var selectedDate = Date()
    @State private var displayedDate = Date()

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading) {
                    Text(displayedDate.formatted(.dateTime.month(.abbreviated)))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(displayedDate.formatted(.dateTime.year()))
                        .font(.title3)
                        .fontWeight(.light)
                        .foregroundColor(Color(white: 0.65))
                }
                .frame(minWidth: 48, alignment: .leading)
                .padding(.top, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        selectedDate = Date.now
                        displayedDate = Date.now
                    }
                }

                ZStack(alignment: .top) {
                    WheelPicker(selectedDate: $selectedDate, displayedDate: $displayedDate, config: Config())
                    HStack(alignment: .top) {
                        LinearGradient(
                            colors: [Color.black, .clear], startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 20)
                        Spacer()
                        LinearGradient(
                            colors: [.clear, Color.black], startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 20)
                    }
                    .allowsHitTesting(false)
                }
            }

            let filteredEvents = EventListView.filteredEvents(
                events: calendarManager.events
            )
            Group {
                if filteredEvents.isEmpty {
                    EmptyEventsView(selectedDate: selectedDate)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    EventListView(events: calendarManager.events)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        }
        .listRowBackground(Color.clear)
        .frame(height: 148)
        .clipped()
        .onChange(of: selectedDate) {
            Task { @MainActor in
                await calendarManager.updateCurrentDate(selectedDate)
            }
        }
        .onChange(of: vm.notchState) { _, _ in
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
                displayedDate = Date.now
            }
        }
        .onAppear {
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
                displayedDate = Date.now
            }
        }
    }
}

struct EmptyEventsView: View {
    let selectedDate: Date
    
    var body: some View {
        VStack {
            Image(systemName: "calendar.badge.checkmark")
                .font(.title)
                .foregroundColor(Color(white: 0.65))
            Text(Calendar.current.isDateInToday(selectedDate) ? "No events today" : "No events")
                .font(.subheadline)
                .foregroundColor(.white)
            Text("Enjoy your free time!")
                .font(.caption)
                .foregroundColor(Color(white: 0.65))
        }
    }
}

struct EventListView: View {
    @Environment(\.openURL) private var openURL
    @ObservedObject private var calendarManager = CalendarManager.shared
    let events: [EventModel]
    @Default(.autoScrollToNextEvent) private var autoScrollToNextEvent
    @Default(.showFullEventTitles) private var showFullEventTitles


    static func filteredEvents(events: [EventModel]) -> [EventModel] {
        events.filter { event in
            if event.type.isReminder {
                if case .reminder(let completed) = event.type {
                    return !completed || !Defaults[.hideCompletedReminders]
                }
            }
            // Filter out all-day events if setting is enabled
            if event.isAllDay && Defaults[.hideAllDayEvents] {
                return false
            }
            return true
        }
    }

    private var filteredEvents: [EventModel] {
        Self.filteredEvents(events: events)
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy) {
        let now = Date()
        // Determine a single target using preferred search order:
        // 1) first non-all-day upcoming/in-progress event
        // 2) first all-day event
        // 3) last event (fallback)
        let nonAllDayUpcoming = filteredEvents.first(where: { !$0.isAllDay && $0.end > now })
        let firstAllDay = filteredEvents.first(where: { $0.isAllDay })
        let lastEvent = filteredEvents.last
        guard let target = nonAllDayUpcoming ?? firstAllDay ?? lastEvent else { return }

        Task { @MainActor in
            withTransaction(Transaction(animation: nil)) {
                proxy.scrollTo(target.id, anchor: .top)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredEvents) { event in
                    Button(action: {
                        if let url = event.calendarAppURL() {
                            openURL(url)
                        }
                    }) {
                        eventRow(event)
                    }
                    .id(event.id)
                    .padding(.leading, -5)
                    .buttonStyle(PlainButtonStyle())
                    .listRowSeparator(.automatic)
                    .listRowSeparatorTint(.gray.opacity(0.2))
                    .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollIndicators(.never)
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .onAppear {
                scrollToRelevantEvent(proxy: proxy)
            }
            .onChange(of: filteredEvents) { _, _ in
                scrollToRelevantEvent(proxy: proxy)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private func eventRow(_ event: EventModel) -> some View {
        if event.type.isReminder {
            let isCompleted: Bool
            if case .reminder(let completed) = event.type {
                isCompleted = completed
            } else {
                isCompleted = false
            }
            return AnyView(
                HStack(spacing: 8) {
                    ReminderToggle(
                        isOn: Binding(
                            get: { isCompleted },
                            set: { newValue in
                                Task {
                                    await calendarManager.setReminderCompleted(
                                        reminderID: event.id, completed: newValue
                                    )
                                }
                            }
                        ),
                        color: Color(event.calendar.color)
                    )
                    .opacity(1.0)  // Ensure the toggle is always fully opaque
                    HStack {
                        Text(event.title)
                            .font(.callout)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 1)
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 4) {
                            if event.isAllDay {
                                Text("All-day")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            } else {
                                Text(event.start, style: .time)
                                    .foregroundColor(.white)
                                    .font(.caption)
                            }
                        }
                    }
                    .opacity(
                        isCompleted
                            ? 0.4
                            : event.start < Date.now && Calendar.current.isDateInToday(event.start)
                                ? 0.6 : 1.0
                    )
                }
                .padding(.vertical, 4)
            )
        } else {
            return AnyView(
                HStack(alignment: .top, spacing: 4) {
                    Rectangle()
                        .fill(Color(event.calendar.color))
                        .frame(width: 3)
                        .cornerRadius(1.5)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.callout)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .lineLimit(showFullEventTitles ? nil : 2)

                        if let location = event.location, !location.isEmpty {
                            Text(location)
                                .font(.caption)
                                .foregroundColor(Color(white: 0.65))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if event.isAllDay {
                            Text("All-day")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .lineLimit(1)
                        } else {
                            Text(event.start, style: .time)
                                .foregroundColor(.white)
                            Text(event.end, style: .time)
                                .foregroundColor(Color(white: 0.65))
                        }
                    }
                    .font(.caption)
                    .frame(minWidth: 44, alignment: .trailing)
                }
                .opacity(
                    event.eventStatus == .ended && Calendar.current.isDateInToday(event.start)
                        ? 0.6 : 1.0)
            )
        }
    }
}

struct ReminderToggle: View {
    @Binding var isOn: Bool
    var color: Color

    var body: some View {
        Button(action: {
            isOn.toggle()
        }) {
            ZStack {
                // Outer ring
                Circle()
                    .strokeBorder(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                // Inner fill
                if isOn {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Circle()
                    .fill(Color.black.opacity(0.001))
                    .frame(width: 14, height: 14)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .padding(0)
        .accessibilityLabel(isOn ? "Mark as incomplete" : "Mark as complete")
    }
}

#Preview {
    CalendarView()
        .frame(width: 215, height: 130)
        .background(.black)
        .environmentObject(NotchPulseViewModel())
}
