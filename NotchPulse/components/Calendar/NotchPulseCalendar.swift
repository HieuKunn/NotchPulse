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
    var onScrollOriginChanged: ((CGFloat, CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> HelperView {
        let view = HelperView()
        view.onScrollOriginChanged = onScrollOriginChanged
        return view
    }

    func updateNSView(_ nsView: HelperView, context: Context) {
        nsView.onScrollOriginChanged = onScrollOriginChanged
        nsView.checkSetup()
    }

    class HelperView: NSView {
        private var monitor: Any?
        private var boundsObserver: NSObjectProtocol?
        var onScrollOriginChanged: ((CGFloat, CGFloat) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                checkSetup()
            } else {
                cleanup()
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if superview != nil {
                checkSetup()
            }
        }

        deinit {
            cleanup()
        }

        private func cleanup() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
            if let b = boundsObserver {
                NotificationCenter.default.removeObserver(b)
                boundsObserver = nil
            }
        }

        func checkSetup() {
            guard window != nil else { return }

            if let scrollView = enclosingScrollView, boundsObserver == nil {
                let clipView = scrollView.contentView
                clipView.postsBoundsChangedNotifications = true
                boundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self] _ in
                    guard let self = self, let sv = self.enclosingScrollView else { return }
                    let clip = sv.contentView
                    self.onScrollOriginChanged?(clip.bounds.origin.x, clip.bounds.width)
                }
            }

            if monitor == nil {
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
            VStack(spacing: 2) {
                Text(dayString)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : Color(white: 0.65))

                ZStack {
                    if isToday {
                        Circle()
                            .fill(isSelected ? Color.clear : Color.effectiveAccentBackground)
                            .frame(width: 22, height: 22)
                    }
                    Circle()
                        .stroke(isSelected ? Color.clear : (isToday ? Color.effectiveAccentBackground : Color.clear), lineWidth: 1)
                        .frame(width: 24, height: 24)
                    Text(dayNumberString)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(isSelected ? .white : Color(white: isToday ? 0.95 : 0.65))
                }
            }
            .frame(width: 32, height: 40)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.effectiveAccentBackground : (isHovered ? Color.white.opacity(0.08) : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
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
                            .frame(width: 32, height: 40)
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
            .frame(height: 40)
            .background(CalendarScrollWheelHelper { originX, viewportWidth in
                let cellWidth: CGFloat = 34.0 // 32 item width + 2 spacing
                let centerX = originX + (viewportWidth / 2.0)
                let itemIndex = Int(round((centerX - 16.0) / cellWidth))
                let date = dateForItemIndex(index: itemIndex, spacerNum: config.offset)
                if Calendar.current.component(.month, from: date) != Calendar.current.component(.month, from: displayedDate) ||
                   Calendar.current.component(.year, from: date) != Calendar.current.component(.year, from: displayedDate) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        displayedDate = date
                    }
                }
            })
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


// MARK: - Calendar Navigation Button (Hover and click feedback)
struct CalendarNavButton: View {
    let icon: String
    let helpText: String?
    let action: () -> Void
    @State private var isHovered: Bool = false

    init(icon: String, helpText: String? = nil, action: @escaping () -> Void) {
        self.icon = icon
        self.helpText = helpText
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isHovered ? .white : Color(white: 0.7))
                .frame(width: 24, height: 24)
                .background(Color.white.opacity(isHovered ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(helpText ?? "")
    }
}

// MARK: - Month Day Cell Button
private struct MonthDayCellButton: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let dayNumber: Int
    let onClick: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onClick) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.effectiveAccentBackground).frame(width: 24, height: 24)
                } else if isHovered {
                    Circle().fill(Color.white.opacity(0.12)).frame(width: 24, height: 24)
                } else if isToday {
                    Circle().stroke(Color.effectiveAccentBackground, lineWidth: 1.5).frame(width: 24, height: 24)
                }
                Text("\(dayNumber)")
                    .font(.system(size: 11, weight: isToday || isSelected ? .bold : .medium, design: .rounded))
                    .foregroundColor(isSelected ? .white : (isToday ? Color.effectiveAccent : (isHovered ? .white : Color(white: 0.78))))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Full Month Calendar (standalone grid, used in fullMonth and dayDetail modes)
struct FullMonthCalendarGrid: View {
    @Binding var selectedDate: Date
    @Binding var displayedDate: Date
    let showHeader: Bool
    let onSelectDay: (Date) -> Void
    let onPrevMonth: () -> Void
    let onNextMonth: () -> Void
    @ViewBuilder var trailingHeaderButton: () -> some View

    private let calendar = Calendar.current
    private let daysOfWeek = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedDate) else { return [] }
        let monthStart = monthInterval.start
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let numberOfDays = calendar.range(of: .day, in: .month, for: displayedDate)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: firstWeekday - 1)
        for day in 0..<numberOfDays {
            if let date = calendar.date(byAdding: .day, value: day, to: monthStart) {
                days.append(date)
            }
        }
        return days
    }

    var body: some View {
        VStack(spacing: 6) {
            if showHeader {
                HStack(spacing: 6) {
                    CalendarNavButton(icon: "chevron.left", helpText: "Previous month") {
                        onPrevMonth()
                    }

                    Text(displayedDate.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)

                    CalendarNavButton(icon: "chevron.right", helpText: "Next month") {
                        onNextMonth()
                    }

                    trailingHeaderButton()
                }
                .padding(.horizontal, 4)

                // Day of week row
                HStack(spacing: 0) {
                    ForEach(daysOfWeek, id: \.self) { dow in
                        Text(dow)
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundColor(Color(white: 0.5))
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
            LazyVGrid(columns: columns, spacing: 3) {
                ForEach(0..<daysInMonth.count, id: \.self) { index in
                    if let date = daysInMonth[index] {
                        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
                        let isToday = calendar.isDateInToday(date)
                        MonthDayCellButton(
                            date: date,
                            isSelected: isSelected,
                            isToday: isToday,
                            dayNumber: calendar.component(.day, from: date),
                            onClick: { onSelectDay(date) }
                        )
                    } else {
                        Color.clear.frame(height: 26)
                    }
                }
            }
        }
    }

    func changeMonth(by amount: Int) {
        if let newDate = calendar.date(byAdding: .month, value: amount, to: displayedDate) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                displayedDate = newDate
            }
        }
    }
}

// MARK: - Day Events Panel (right side in dayDetail mode)
struct DayEventsPanelView: View {
    let selectedDate: Date
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showFullEventTitles) private var showFullEventTitles

    private var filteredEvents: [EventModel] {
        EventListView.filteredEvents(events: calendarManager.events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Day header
            VStack(alignment: .leading, spacing: 1) {
                Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(Color(white: 0.55))
                    .textCase(.uppercase)
                Text("\(Calendar.current.component(.day, from: selectedDate))")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(Calendar.current.isDateInToday(selectedDate) ? Color.effectiveAccent : .white)
            }
            .padding(.bottom, 2)

            if filteredEvents.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 20))
                        .foregroundColor(Color(white: 0.4))
                    Text("No events")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.5))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredEvents) { event in
                            EventRowItemView(event: event, showFullEventTitles: showFullEventTitles)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Calendar View (main entry point)
private enum CalendarMode {
    case normal       // Half media / half calendar with day-wheel
    case fullMonth    // Full page month grid (media hidden)
    case dayDetail    // 3/5 month grid + 2/5 day events (media hidden)
}

struct CalendarView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject private var calendarManager = CalendarManager.shared
    @ObservedObject private var coordinator = NotchPulseViewCoordinator.shared
    @State private var selectedDate = Date()
    @State private var displayedDate = Date()
    @State private var mode: CalendarMode = .normal

    private var isFullPage: Bool { mode == .fullMonth || mode == .dayDetail }

    var body: some View {
        Group {
            switch mode {
            case .normal:
                normalModeView
            case .fullMonth:
                fullMonthModeView
            case .dayDetail:
                dayDetailModeView
            }
        }
        .frame(height: frameHeight)
        .clipped()
        .onChange(of: selectedDate) { _, newValue in
            Task { @MainActor in
                await calendarManager.updateCurrentDate(newValue)
            }
        }
        .onChange(of: coordinator.currentView) { _, newView in
            if newView != .home {
                mode = .normal
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    vm.customOpenHeight = nil
                }
            }
        }
        .onChange(of: vm.notchState) { _, newState in
            if newState == .closed {
                mode = .normal
                vm.customOpenHeight = nil
            }
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
                displayedDate = Date.now
            }
        }
        .onAppear {
            if coordinator.currentView != .home {
                mode = .normal
                vm.customOpenHeight = nil
            }
            Task {
                await calendarManager.updateCurrentDate(Date.now)
                selectedDate = Date.now
                displayedDate = Date.now
            }
        }
        .onDisappear {
            mode = .normal
            vm.customOpenHeight = nil
        }
    }

    private var frameHeight: CGFloat {
        switch mode {
        case .normal: return 148
        case .fullMonth: return 280
        case .dayDetail: return 280
        }
    }

    // MARK: - Normal mode (day-wheel + events beside media)
    private var normalModeView: some View {
        VStack(spacing: 2) {
            HStack(alignment: .center, spacing: 6) {
                // Month/year header button → go to fullMonth
                Button {
                    enterFullMonth()
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 3) {
                            Text(displayedDate.formatted(.dateTime.month(.abbreviated)))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        Text(displayedDate.formatted(.dateTime.year()))
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(Color(white: 0.65))
                    }
                }
                .buttonStyle(.plain)
                .frame(minWidth: 54, alignment: .leading)

                ZStack(alignment: .top) {
                    WheelPicker(selectedDate: $selectedDate, displayedDate: $displayedDate, config: Config())
                    HStack(alignment: .top) {
                        LinearGradient(colors: [Color.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                        Spacer()
                        LinearGradient(colors: [.clear, Color.black], startPoint: .leading, endPoint: .trailing).frame(width: 16)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 40)

            let filteredEvents = EventListView.filteredEvents(events: calendarManager.events)
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
        .padding(.bottom, 8)
        .listRowBackground(Color.clear)
    }

    // MARK: - Full month mode (full page, media hidden)
    private var fullMonthModeView: some View {
        FullMonthCalendarGrid(
            selectedDate: $selectedDate,
            displayedDate: $displayedDate,
            showHeader: true,
            onSelectDay: { date in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    selectedDate = date
                    displayedDate = date
                    mode = .dayDetail
                }
                Task { @MainActor in
                    await calendarManager.updateCurrentDate(date)
                }
            },
            onPrevMonth: { changeDisplayedMonth(by: -1) },
            onNextMonth: { changeDisplayedMonth(by: 1) }
        ) {
            CalendarNavButton(icon: "arrow.down.right.and.arrow.up.left", helpText: "Collapse calendar") {
                exitFullPage()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Day detail mode (3/5 month + 2/5 events, media hidden)
    private var dayDetailModeView: some View {
        HStack(alignment: .top, spacing: 10) {
            // 3/5 — Full month calendar grid
            FullMonthCalendarGrid(
                selectedDate: $selectedDate,
                displayedDate: $displayedDate,
                showHeader: true,
                onSelectDay: { date in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        selectedDate = date
                        displayedDate = date
                    }
                    Task { @MainActor in
                        await calendarManager.updateCurrentDate(date)
                    }
                },
                onPrevMonth: { changeDisplayedMonth(by: -1) },
                onNextMonth: { changeDisplayedMonth(by: 1) }
            ) {
                CalendarNavButton(icon: "arrow.down.right.and.arrow.up.left", helpText: "Collapse calendar") {
                    exitFullPage()
                }
            }
            .frame(maxWidth: .infinity)

            // Thin divider
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(width: 1)
                .padding(.vertical, 4)

            // 2/5 — Day events panel
            DayEventsPanelView(selectedDate: selectedDate)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers
    private func enterFullMonth() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            mode = .fullMonth
            vm.customOpenHeight = 310
        }
    }

    private func exitFullPage() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            mode = .normal
            vm.customOpenHeight = nil
        }
    }

    private func changeDisplayedMonth(by amount: Int) {
        if let newDate = Calendar.current.date(byAdding: .month, value: amount, to: displayedDate) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                displayedDate = newDate
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

    private func scrollToRelevantEvent(proxy: ScrollViewProxy, animated: Bool = false) {
        guard autoScrollToNextEvent, let targetId = getRelevantTargetId() else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            if animated {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
                                showFullEventTitles: showFullEventTitles
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

// MARK: - Dedicated Clean Event Row Item
struct EventRowItemView: View {
    let event: EventModel
    let showFullEventTitles: Bool
    
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
        .padding(.vertical, 2.5)
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
            // Indicator Bar with calendar color
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
            
            VStack(alignment: .trailing, spacing: 2) {
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
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.06) : Color.clear)
        )
        .opacity(isEnded && !isHovered ? 0.6 : 1.0)
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
