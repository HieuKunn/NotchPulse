//
//  NotchPulseCalendar.swift
//  NotchPulse
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Defaults
import SwiftUI

struct Config: Equatable {
    var past: Int = 180    // ~6 months past
    var future: Int = 365  // 1 full year future
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
    func makeNSView(context: Context) -> HelperView {
        HelperView()
    }

    func updateNSView(_ nsView: HelperView, context: Context) {
        nsView.checkSetup()
    }

    class HelperView: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                checkSetup()
            } else {
                removeMonitor()
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
        }

        private func removeMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        func checkSetup() {
            guard window != nil, monitor == nil else { return }
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
            LazyHStack(spacing: config.spacing) {
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
            .background(CalendarScrollWheelHelper())
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

    private var nextUpcomingEventId: String? {
        let now = Date()
        let isToday = Calendar.current.isDateInToday(calendarManager.currentWeekStartDate)
        guard isToday else { return nil }
        return filteredEvents.first(where: { !$0.isAllDay && $0.start > now })?.id
    }

    private func getRelevantTargetId() -> String? {
        let now = Date()
        let isToday = Calendar.current.isDateInToday(calendarManager.currentWeekStartDate)
        if isToday {
            // 1) Sự kiện đang diễn ra trong khung thời gian hiện tại (ví dụ: 11h)
            if let inProgress = filteredEvents.first(where: { !$0.isAllDay && $0.start <= now && $0.end > now }) {
                return inProgress.id
            }
            // 2) Sự kiện gần nhất tiếp theo sau giờ hiện tại
            if let nextUpcoming = filteredEvents.first(where: { !$0.isAllDay && $0.start > now }) {
                return nextUpcoming.id
            }
            // 3) Fallback nếu tất cả đã kết thúc hoặc chỉ có all-day
            return filteredEvents.first(where: { !$0.isAllDay })?.id ?? filteredEvents.first?.id
        } else {
            // Xem ngày khác trong tương lai/quá khứ: cuộn tới sự kiện đầu tiên
            return filteredEvents.first(where: { !$0.isAllDay })?.id ?? filteredEvents.first?.id
        }
    }

    private func scrollToRelevantEvent(proxy: ScrollViewProxy, animated: Bool = true) {
        guard autoScrollToNextEvent, let targetId = getRelevantTargetId() else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            if animated {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    proxy.scrollTo(targetId, anchor: .top)
                }
            } else {
                proxy.scrollTo(targetId, anchor: .top)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 3) {
                    ForEach(filteredEvents) { event in
                        Button(action: {
                            if let url = event.calendarAppURL() {
                                openURL(url)
                            }
                        }) {
                            EventRowItemView(
                                event: event,
                                showFullEventTitles: showFullEventTitles,
                                isInProgress: Calendar.current.isDateInToday(event.start) && !event.isAllDay && event.start <= Date.now && event.end > Date.now,
                                isNextUp: event.id == nextUpcomingEventId
                            )
                        }
                        .id(event.id)
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 3)
            }
            .scrollIndicators(.never)
            .onAppear {
                scrollToRelevantEvent(proxy: proxy, animated: false)
            }
            .onChange(of: filteredEvents) { _, _ in
                scrollToRelevantEvent(proxy: proxy, animated: true)
            }
            .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                scrollToRelevantEvent(proxy: proxy, animated: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - Dedicated Event Row Item with Real-Time Highlight & Hover
struct EventRowItemView: View {
    let event: EventModel
    let showFullEventTitles: Bool
    let isInProgress: Bool
    let isNextUp: Bool
    
    @ObservedObject private var calendarManager = CalendarManager.shared
    @State private var isHovered: Bool = false
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(event.start)
    }
    
    private var isEnded: Bool {
        isToday && !event.isAllDay && event.end <= Date.now
    }

    var body: some View {
        if event.type.isReminder {
            reminderRow
        } else {
            calendarEventRow
        }
    }

    private var reminderRow: some View {
        let isCompleted: Bool
        if case .reminder(let completed) = event.type {
            isCompleted = completed
        } else {
            isCompleted = false
        }
        
        return HStack(spacing: 8) {
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
            .opacity(1.0)
            
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
                    : (event.start < Date.now && isToday && !isHovered) ? 0.6 : 1.0
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var calendarEventRow: some View {
        HStack(alignment: .top, spacing: 6) {
            // Indicator Bar
            Rectangle()
                .fill(isInProgress ? Color(red: 0.19, green: 0.86, blue: 0.38) : Color(event.calendar.color))
                .frame(width: isInProgress ? 3.5 : 3)
                .cornerRadius(1.5)
                .shadow(color: isInProgress ? Color(red: 0.19, green: 0.86, blue: 0.38).opacity(0.7) : .clear, radius: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(event.title)
                        .font(.callout)
                        .fontWeight(isInProgress ? .bold : .medium)
                        .foregroundColor(.white)
                        .lineLimit(showFullEventTitles ? nil : 2)
                    
                    if isInProgress {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(red: 0.19, green: 0.86, blue: 0.38))
                                .frame(width: 4.5, height: 4.5)
                            Text("Đang diễn ra")
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(red: 0.19, green: 0.86, blue: 0.38))
                        }
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color(red: 0.19, green: 0.86, blue: 0.38).opacity(0.18)))
                    } else if isNextUp {
                        Text("Tiếp theo")
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(Color.cyan)
                            .padding(.horizontal, 4.5)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.cyan.opacity(0.18)))
                    }
                }

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                }
            }
            
            Spacer(minLength: 0)
            
            VStack(alignment: .trailing, spacing: 2) {
                if event.isAllDay {
                    Text("All-day")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .lineLimit(1)
                } else {
                    Text(event.start, style: .time)
                        .fontWeight(isInProgress ? .bold : .regular)
                        .foregroundColor(isInProgress ? Color(red: 0.19, green: 0.86, blue: 0.38) : .white)
                    Text(event.end, style: .time)
                        .foregroundColor(Color(white: 0.65))
                }
            }
            .font(.caption)
            .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isInProgress
                        ? Color.white.opacity(0.08)
                        : (isHovered ? Color.white.opacity(0.06) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isInProgress
                        ? Color(red: 0.19, green: 0.86, blue: 0.38).opacity(0.35)
                        : Color.clear,
                    lineWidth: 1
                )
        )
        .opacity(isEnded && !isHovered ? 0.45 : 1.0)
        .onHover { hovering in
            isHovered = hovering
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
