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

// MARK: - Vietnamese Lunar Calendar Engine (Dr. Ho Ngoc Duc algorithm, UTC+7)
struct VietnameseLunarCalculator {
    static func jdFromDate(dd: Int, mm: Int, yy: Int) -> Int {
        let a = (14 - mm) / 12
        let y = yy + 4800 - a
        let m = mm + 12 * a - 3
        var jd = dd + ((153 * m + 2) / 5) + 365 * y + (y / 4) - (y / 100) + (y / 400) - 32045
        if jd < 2299161 {
            jd = dd + ((153 * m + 2) / 5) + 365 * y + (y / 4) - 32083
        }
        return jd
    }

    static func getNewMoonDay(k: Int, timeZone: Double = 7.0) -> Int {
        let T = Double(k) / 1236.85
        let T2 = T * T
        let T3 = T2 * T
        let dr = Double.pi / 180.0
        var Jd1 = 2415020.75933 + 29.53058868 * Double(k) + 0.0001178 * T2 - 0.000000155 * T3
        Jd1 += 0.00033 * sin((166.56 + 132.87 * T - 0.009173 * T2) * dr)
        let M = 359.2242 + 29.10535608 * Double(k) - 0.0000333 * T2 - 0.00000347 * T3
        let Mpr = 306.0253 + 385.81691806 * Double(k) + 0.0107306 * T2 + 0.00001236 * T3
        let F = 21.2964 + 390.67050646 * Double(k) - 0.0016528 * T2 - 0.00000239 * T3
        var C1 = (0.1734 - 0.000393 * T) * sin(M * dr) + 0.0021 * sin(2.0 * M * dr)
        C1 -= 0.4068 * sin(Mpr * dr) + 0.0161 * sin(2.0 * Mpr * dr)
        C1 -= 0.0004 * sin(3.0 * Mpr * dr)
        C1 += 0.0104 * sin(2.0 * F * dr) - 0.0051 * sin((M + Mpr) * dr)
        C1 -= 0.0074 * sin((M - Mpr) * dr) + 0.0004 * sin((2.0 * F + M) * dr)
        C1 -= 0.0004 * sin((2.0 * F - M) * dr) - 0.0006 * sin((2.0 * F + Mpr) * dr)
        C1 += 0.0010 * sin((2.0 * F - Mpr) * dr) + 0.0005 * sin((M + 2.0 * Mpr) * dr)
        let JdNew = Jd1 + C1
        return Int(floor(JdNew + 0.5 + timeZone / 24.0))
    }

    static func getSunLongitude(jdn: Int, timeZone: Double = 7.0) -> Int {
        let T = (Double(jdn) - 0.5 - timeZone / 24.0 - 2451545.0) / 36525.0
        let T2 = T * T
        let dr = Double.pi / 180.0
        let M = 357.52910 + 35999.05030 * T - 0.0001559 * T2 - 0.00000048 * T * T2
        let L0 = 280.46645 + 36000.76983 * T + 0.0003032 * T2
        var DL = (1.914600 - 0.004817 * T - 0.000014 * T2) * sin(M * dr)
        DL += (0.019993 - 0.000101 * T) * sin(2.0 * M * dr) + 0.000290 * sin(3.0 * M * dr)
        var L = L0 + DL
        L = L.truncatingRemainder(dividingBy: 360.0)
        if L < 0 { L += 360.0 }
        return Int(floor(L / 30.0))
    }

    static func getLunarMonth11(yy: Int, timeZone: Double = 7.0) -> Int {
        let off = jdFromDate(dd: 31, mm: 12, yy: yy) - 2415021
        let k = Int(floor(Double(off) / 29.530588853))
        var nm = getNewMoonDay(k: k, timeZone: timeZone)
        let sunLong = getSunLongitude(jdn: nm, timeZone: timeZone)
        if sunLong >= 9 {
            nm = getNewMoonDay(k: k - 1, timeZone: timeZone)
        }
        return nm
    }

    static func getLeapMonthOffset(a11: Int, timeZone: Double = 7.0) -> Int {
        let k = Int(floor(Double(a11 - 2415021) / 29.530588853 + 0.5))
        var last = 0
        var i = 1
        var arc = getSunLongitude(jdn: getNewMoonDay(k: k + i, timeZone: timeZone), timeZone: timeZone)
        repeat {
            last = arc
            i += 1
            arc = getSunLongitude(jdn: getNewMoonDay(k: k + i, timeZone: timeZone), timeZone: timeZone)
        } while (arc != last && i < 14)
        return i - 1
    }

    static func convertSolarToLunar(dd: Int, mm: Int, yy: Int, timeZone: Double = 7.0) -> (day: Int, month: Int, year: Int, isLeap: Bool) {
        let dayNumber = jdFromDate(dd: dd, mm: mm, yy: yy)
        var k = Int(floor(Double(dayNumber - 2415021) / 29.530588853))
        var monthStart = getNewMoonDay(k: k + 1, timeZone: timeZone)
        if monthStart > dayNumber {
            monthStart = getNewMoonDay(k: k, timeZone: timeZone)
        } else {
            k += 1
        }
        var a11 = getLunarMonth11(yy: yy, timeZone: timeZone)
        var b11 = a11
        var lunarYear: Int
        if a11 >= monthStart {
            lunarYear = yy
            a11 = getLunarMonth11(yy: yy - 1, timeZone: timeZone)
        } else {
            lunarYear = yy + 1
            b11 = getLunarMonth11(yy: yy + 1, timeZone: timeZone)
        }
        let lunarDay = dayNumber - monthStart + 1
        let diff = (monthStart - a11) / 29
        var lunarLeap = false
        var lunarMonth = diff + 11
        if (b11 - a11) > 365 {
            let leapOff = getLeapMonthOffset(a11: a11, timeZone: timeZone)
            if diff >= leapOff {
                lunarMonth = diff + 10
                if diff == leapOff {
                    lunarLeap = true
                }
            }
        }
        if lunarMonth > 12 {
            lunarMonth -= 12
        }
        return (lunarDay, lunarMonth, lunarYear, lunarLeap)
    }
}

// MARK: - Alternate Calendar Helper
struct CalendarDateInfo {
    let day: Int
    let month: Int
    let year: Int
    let isLeap: Bool
}

struct AlternateCalendarHelper {
    static func dateInfo(for date: Date, type: AlternateCalendarType) -> CalendarDateInfo {
        switch type {
        case .vietnamese:
            let cal = Calendar.current
            let d = cal.component(.day, from: date)
            let m = cal.component(.month, from: date)
            let y = cal.component(.year, from: date)
            let res = VietnameseLunarCalculator.convertSolarToLunar(dd: d, mm: m, yy: y, timeZone: 7.0)
            return CalendarDateInfo(day: res.day, month: res.month, year: res.year, isLeap: res.isLeap)
        case .chinese:
            let cal = Calendar(identifier: .chinese)
            let d = cal.component(.day, from: date)
            let m = cal.component(.month, from: date)
            let y = cal.component(.year, from: date)
            return CalendarDateInfo(day: d, month: m, year: y, isLeap: false)
        case .islamic:
            let cal = Calendar(identifier: .islamicCivil)
            let d = cal.component(.day, from: date)
            let m = cal.component(.month, from: date)
            let y = cal.component(.year, from: date)
            return CalendarDateInfo(day: d, month: m, year: y, isLeap: false)
        case .hebrew:
            let cal = Calendar(identifier: .hebrew)
            let d = cal.component(.day, from: date)
            let m = cal.component(.month, from: date)
            let y = cal.component(.year, from: date)
            return CalendarDateInfo(day: d, month: m, year: y, isLeap: false)
        case .buddhist:
            let cal = Calendar(identifier: .buddhist)
            let d = cal.component(.day, from: date)
            let m = cal.component(.month, from: date)
            let y = cal.component(.year, from: date)
            return CalendarDateInfo(day: d, month: m, year: y, isLeap: false)
        case .persian:
            let cal = Calendar(identifier: .persian)
            let d = cal.component(.day, from: date)
            let m = cal.component(.month, from: date)
            let y = cal.component(.year, from: date)
            return CalendarDateInfo(day: d, month: m, year: y, isLeap: false)
        }
    }

    /// Formats the string displayed beneath the day number in the month grid cell.
    /// E.g. "(15)" or if first day of lunar month "(1/8)".
    static func gridCellString(for date: Date, type: AlternateCalendarType) -> String {
        let info = dateInfo(for: date, type: type)
        if info.day == 1 {
            return "(\(info.day)/\(info.month))"
        } else {
            return "(\(info.day))"
        }
    }

    /// Formats the string displayed beside the solar date in the 2/5 day detail panel.
    /// E.g. "(17/8 Lunar Cal)".
    static func dayDetailString(for date: Date, type: AlternateCalendarType) -> String {
        let info = dateInfo(for: date, type: type)
        let leapStr = info.isLeap ? " Nhuận" : ""
        let calSuffix: String
        switch type {
        case .vietnamese, .chinese:
            calSuffix = "Lunar Cal"
        case .islamic:
            calSuffix = "Hijri Cal"
        case .hebrew:
            calSuffix = "Hebrew Cal"
        case .buddhist:
            calSuffix = "Buddhist Cal"
        case .persian:
            calSuffix = "Solar Hijri"
        }
        return "(\(info.day)/\(info.month)\(leapStr) \(calSuffix))"
    }
}

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


// MARK: - Calendar State & Pin Button
@MainActor
final class CalendarStateViewModel: ObservableObject {
    static let shared = CalendarStateViewModel()
    @Published var isPinned: Bool = false
    private init() {}
}

struct CalendarPinButton: View {
    @ObservedObject private var state = CalendarStateViewModel.shared
    @EnvironmentObject var vm: NotchPulseViewModel

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                state.isPinned.toggle()
            }
            if !state.isPinned && !vm.isMouseHovering() {
                vm.close()
            }
        } label: {
            Image(systemName: state.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.isPinned ? Color.green : Color.white.opacity(0.65))
                .rotationEffect(.degrees(state.isPinned ? 0 : 45))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(state.isPinned ? Color.green.opacity(0.22) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(state.isPinned ? Color.green.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(state.isPinned ? "Unpin Calendar (Close on hover exit)" : "Pin Calendar (Keep open when hovering out)")
    }
}

// MARK: - Calendar Navigation Button (Hover and click feedback)
struct CalendarNavButton: View {
    let icon: String
    let helpText: String?
    var isToggled: Bool = false
    let action: () -> Void
    @State private var isHovered: Bool = false

    init(icon: String, helpText: String? = nil, isToggled: Bool = false, action: @escaping () -> Void) {
        self.icon = icon
        self.helpText = helpText
        self.isToggled = isToggled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(isToggled ? Color.effectiveAccent : (isHovered ? .white : Color(white: 0.7)))
                .frame(width: 24, height: 24)
                .background(isToggled ? Color.effectiveAccent.opacity(0.18) : Color.white.opacity(isHovered ? 0.16 : 0.08), in: RoundedRectangle(cornerRadius: 6))
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
    let showLunar: Bool
    let alternateCalendarType: AlternateCalendarType
    let onClick: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onClick) {
            ZStack {
                if isSelected {
                    Circle().fill(Color.effectiveAccentBackground).frame(width: 25, height: 25)
                } else if isHovered {
                    Circle().fill(Color.white.opacity(0.12)).frame(width: 25, height: 25)
                } else if isToday {
                    Circle().stroke(Color.effectiveAccentBackground, lineWidth: 1.5).frame(width: 25, height: 25)
                }

                if showLunar {
                    VStack(spacing: 0) {
                        Text("\(dayNumber)")
                            .font(.system(size: 9.5, weight: isToday || isSelected ? .bold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? .white : (isToday ? Color.effectiveAccent : (isHovered ? .white : Color(white: 0.85))))
                        Text(AlternateCalendarHelper.gridCellString(for: date, type: alternateCalendarType))
                            .font(.system(size: 7.0, weight: .regular, design: .rounded))
                            .foregroundColor(isSelected ? .white.opacity(0.9) : (isToday ? Color.effectiveAccent.opacity(0.9) : Color(white: 0.52)))
                            .lineLimit(1)
                    }
                } else {
                    Text("\(dayNumber)")
                        .font(.system(size: 11, weight: isToday || isSelected ? .bold : .medium, design: .rounded))
                        .foregroundColor(isSelected ? .white : (isToday ? Color.effectiveAccent : (isHovered ? .white : Color(white: 0.78))))
                }
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
struct FullMonthCalendarGrid<TrailingContent: View>: View {
    @Binding var selectedDate: Date
    @Binding var displayedDate: Date
    let showHeader: Bool
    let onSelectDay: (Date) -> Void
    let onPrevMonth: () -> Void
    let onNextMonth: () -> Void
    @ViewBuilder var trailingHeaderButton: () -> TrailingContent

    @Default(.showLunarCalendar) private var showLunarCalendar
    @Default(.alternateCalendarType) private var alternateCalendarType

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
        VStack(spacing: 5) {
            if showHeader {
                HStack(spacing: 8) {
                    Text(displayedDate.formatted(.dateTime.month(.wide).year()))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    HStack(spacing: 3) {
                        CalendarNavButton(icon: "chevron.left", helpText: "Previous month") {
                            onPrevMonth()
                        }
                        CalendarNavButton(icon: "chevron.right", helpText: "Next month") {
                            onNextMonth()
                        }
                        CalendarNavButton(
                            icon: showLunarCalendar ? "moon.fill" : "moon",
                            helpText: showLunarCalendar ? "Hide lunar calendar" : "Show lunar calendar",
                            isToggled: showLunarCalendar
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showLunarCalendar.toggle()
                            }
                        }
                    }

                    Spacer(minLength: 0)

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
                            showLunar: showLunarCalendar,
                            alternateCalendarType: alternateCalendarType,
                            onClick: { onSelectDay(date) }
                        )
                    } else {
                        Color.clear.frame(height: 26)
                    }
                }
            }

            if showLunarCalendar {
                Text("Note: This calendar is for quick reference only; timezone offsets and lunar calculations may result in up to ~98% accuracy across all days.")
                    .font(.system(size: 8, weight: .regular, design: .rounded))
                    .foregroundColor(Color(white: 0.45))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
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
    let onCollapse: () -> Void
    @ObservedObject private var calendarManager = CalendarManager.shared
    @Default(.showFullEventTitles) private var showFullEventTitles
    @Default(.alternateCalendarType) private var alternateCalendarType

    private var filteredEvents: [EventModel] {
        EventListView.filteredEvents(events: calendarManager.events)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Day header with Pin and Collapse buttons
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundColor(Color(white: 0.55))
                        .textCase(.uppercase)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Calendar.current.component(.day, from: selectedDate))")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(Calendar.current.isDateInToday(selectedDate) ? Color.effectiveAccent : .white)

                        Text(AlternateCalendarHelper.dayDetailString(for: selectedDate, type: alternateCalendarType))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(Color(white: 0.6))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                HStack(spacing: 6) {
                    CalendarPinButton()
                    CalendarNavButton(icon: "arrow.down.right.and.arrow.up.left", helpText: "Collapse calendar") {
                        onCollapse()
                    }
                }
            }
            .padding(.bottom, 2)
            .padding(.trailing, 2)

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
                    .padding(.bottom, 6)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.trailing, 6)
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
        .frame(height: frameHeight, alignment: .top)
        .clipped()
        .onChange(of: selectedDate) { _, newValue in
            Task { @MainActor in
                await calendarManager.updateCurrentDate(newValue)
            }
        }
        .onChange(of: coordinator.currentView) { _, newView in
            if newView != .home {
                mode = .normal
                CalendarStateViewModel.shared.isPinned = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    vm.customOpenHeight = nil
                }
            }
        }
        .onChange(of: vm.notchState) { _, newState in
            if newState == .closed {
                mode = .normal
                CalendarStateViewModel.shared.isPinned = false
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
                CalendarStateViewModel.shared.isPinned = false
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
            CalendarStateViewModel.shared.isPinned = false
            vm.customOpenHeight = nil
        }
    }

    private var frameHeight: CGFloat {
        switch mode {
        case .normal: return 148
        case .fullMonth: return 240
        case .dayDetail: return 240
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
            HStack(spacing: 6) {
                CalendarPinButton()
                CalendarNavButton(icon: "arrow.down.right.and.arrow.up.left", helpText: "Collapse calendar") {
                    exitFullPage()
                }
            }
        }
        .frame(maxWidth: 580)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Day detail mode (3/5 month + 2/5 events, media hidden)
    private var dayDetailModeView: some View {
        GeometryReader { geo in
            let totalW = geo.size.width
            let spacing: CGFloat = 14
            let dividerW: CGFloat = 1
            let remainW = max(0, totalW - spacing - dividerW)
            let leftW = remainW * 0.58
            let rightW = remainW * 0.42

            HStack(alignment: .top, spacing: spacing) {
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
                    EmptyView()
                }
                .frame(width: leftW, alignment: .top)

                // Thin divider
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(width: dividerW)
                    .padding(.vertical, 4)

                // 2/5 — Day events panel
                DayEventsPanelView(selectedDate: selectedDate) {
                    exitFullPage()
                }
                .frame(width: rightW, alignment: .topLeading)
            }
        }
        .frame(height: 240, alignment: .top)
        .padding(.horizontal, 14)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Helpers
    private func enterFullMonth() {
        displayedDate = selectedDate
        CalendarStateViewModel.shared.isPinned = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            mode = .dayDetail
            vm.customOpenHeight = 270
        }
        Task { @MainActor in
            await calendarManager.updateCurrentDate(selectedDate)
        }
    }

    private func exitFullPage() {
        CalendarStateViewModel.shared.isPinned = false
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
