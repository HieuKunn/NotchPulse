//
//  StandbyClockView.swift
//  NotchPulse
//
//  Created for NotchPulse v2.0 - iPhone StandBy Mode for Lock Screen
//  Features Big Digital, Dual Widget, Retro Flip Clock & Solar Dial
//

import AppKit
import Combine
import Defaults
import IOKit.ps
import SwiftUI

struct StandbyClockView: View {
    @ObservedObject var musicManager = MusicManager.shared
    @Default(.standbyClockStyle) private var clockStyle
    @Default(.standbyTheme) private var theme
    @Default(.standbyNightMode) private var nightMode
    @Default(.standbyShowSeconds) private var showSeconds
    @Default(.standbyShowBattery) private var showBattery
    
    var onToggleMusic: (() -> Void)? = nil
    var onClose: (() -> Void)? = nil
    
    @State private var batteryPercentage: Int = 100
    @State private var isCharging: Bool = false
    @State private var isHoveringControlBar: Bool = false
    
    private let clockTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            let date = timeline.date
            
            VStack(spacing: 16) {
                // Top header bar (Chỉ báo pin, ngày, nút đóng/thu gọn)
                topStatusBar(for: date)
                
                // Màn hình chính theo phong cách được chọn
                Group {
                    switch clockStyle {
                    case .digitalStacked:
                        digitalStackedStyle(date: date)
                    case .dualWidget:
                        dualWidgetStyle(date: date)
                    case .retroFlip:
                        retroFlipStyle(date: date)
                    case .solarDial:
                        solarDialStyle(date: date)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.98)),
                    removal: .opacity.combined(with: .scale(scale: 1.02))
                ))
                
                // Bottom floating style switcher (Thanh đổi kiểu & đổi màu như iOS StandBy)
                bottomStyleSwitcherBar
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 16)
        }
        .frame(width: 780, height: 440)
        .background(
            ZStack {
                // Nền kính mờ sẫm màu
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.black.opacity(nightMode ? 0.92 : 0.75))
                
                // Quầng sáng nền dịu nhẹ theo chủ đề
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(
                        RadialGradient(
                            colors: [
                                primaryTint.opacity(nightMode ? 0.15 : 0.22),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 420
                        )
                    )
                
                // Viền bóng sang trọng
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(nightMode ? 0.08 : 0.18),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .shadow(color: Color.black.opacity(0.55), radius: 32, x: 0, y: 16)
        .shadow(color: primaryTint.opacity(nightMode ? 0.1 : 0.15), radius: 24, x: 0, y: 8)
        .onAppear {
            updateBatteryInfo()
        }
        .onReceive(clockTimer) { _ in
            updateBatteryInfo()
        }
    }
    
    // =========================================================================
    // MARK: - Color Themes & Night Mode
    // =========================================================================
    
    private var isNightRedActive: Bool {
        nightMode || theme == .nightRed
    }
    
    private var primaryTint: Color {
        if isNightRedActive {
            return Color(red: 1.0, green: 0.23, blue: 0.19)
        }
        switch theme {
        case .neonSunset:
            return Color(red: 1.0, green: 0.37, blue: 0.23)
        case .oceanWave:
            return Color(red: 0.0, green: 0.8, blue: 1.0)
        case .cyberMint:
            return Color(red: 0.0, green: 0.9, blue: 0.46)
        case .pureMinimal:
            return Color.white
        case .nightRed:
            return Color(red: 1.0, green: 0.23, blue: 0.19)
        }
    }
    
    private var themeGradient: LinearGradient {
        if isNightRedActive {
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.25, blue: 0.2), Color(red: 0.8, green: 0.12, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        switch theme {
        case .neonSunset:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.42, blue: 0.25), Color(red: 1.0, green: 0.18, blue: 0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .oceanWave:
            return LinearGradient(
                colors: [Color(red: 0.0, green: 0.95, blue: 1.0), Color(red: 0.25, green: 0.55, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .cyberMint:
            return LinearGradient(
                colors: [Color(red: 0.0, green: 0.95, blue: 0.5), Color(red: 0.0, green: 0.7, blue: 1.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .pureMinimal:
            return LinearGradient(
                colors: [Color.white, Color.white.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .nightRed:
            return LinearGradient(
                colors: [Color(red: 1.0, green: 0.25, blue: 0.2), Color(red: 0.75, green: 0.1, blue: 0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    // =========================================================================
    // MARK: - Top Status Bar
    // =========================================================================
    
    private func topStatusBar(for date: Date) -> some View {
        HStack(alignment: .center) {
            // Ngày trong tuần và ngày tháng
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(primaryTint)
                
                Text(dateFormattedHeader(date: date).uppercased())
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08), in: Capsule())
            
            Spacer()
            
            // Pin & Trạng thái sạc
            if showBattery {
                HStack(spacing: 6) {
                    Image(systemName: isCharging ? "bolt.fill" : batteryIconName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isCharging ? Color.green : (batteryPercentage <= 20 ? Color.red : primaryTint))
                    
                    Text("\(batteryPercentage)%")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            
            // Nếu có nhạc đang phát: Nút chuyển nhanh sang giao diện Media
            if musicManager.isPlaying || !musicManager.songTitle.isEmpty {
                Button {
                    onToggleMusic?()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.85))
                        
                        Text(musicManager.songTitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .frame(maxWidth: 140)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Show Lock Screen Media Player")
            }
            
            // Nút đóng / thu gọn (dành cho chế độ xem trước hoặc thoát nhanh)
            if let onClose = onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help("Close StandBy (Esc)")
            }
        }
    }
    
    // =========================================================================
    // MARK: - Style 1: Digital Stacked (iOS Big Bold Digital Clock)
    // =========================================================================
    
    private func digitalStackedStyle(date: Date) -> some View {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        
        let hourStr = String(format: "%02d", hour)
        let minuteStr = String(format: "%02d", minute)
        let secondStr = String(format: "%02d", second)
        
        return HStack(alignment: .center, spacing: 36) {
            // Cụm số giờ và phút cực lớn
            HStack(spacing: 12) {
                Text(hourStr)
                    .font(.system(size: 148, weight: .black, design: .rounded))
                    .foregroundStyle(themeGradient)
                    .shadow(color: primaryTint.opacity(0.35), radius: 24, x: 0, y: 8)
                
                VStack(spacing: 16) {
                    Circle()
                        .fill(primaryTint)
                        .frame(width: 14, height: 14)
                    Circle()
                        .fill(primaryTint)
                        .frame(width: 14, height: 14)
                }
                .opacity(0.85)
                
                Text(minuteStr)
                    .font(.system(size: 148, weight: .black, design: .rounded))
                    .foregroundStyle(themeGradient)
                    .shadow(color: primaryTint.opacity(0.35), radius: 24, x: 0, y: 8)
            }
            
            // Cột bên phải: Giây chạy liên tục, Thứ, Ngày và thời tiết/lịch
            VStack(alignment: .leading, spacing: 14) {
                if showSeconds {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(secondStr)
                            .font(.system(size: 38, weight: .bold, design: .monospaced))
                            .foregroundStyle(primaryTint)
                        
                        Text("SEC")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(dayOfWeekString(date: date).uppercased())
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text(fullDateString(date: date))
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.65))
                }
                
                // Widget nhỏ chỉ báo hệ thống
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 12))
                        .foregroundStyle(primaryTint)
                    Text(Host.current().localizedName ?? "MacBook")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
            }
        }
    }
    
    // =========================================================================
    // MARK: - Style 2: Dual Widget (Analog Clock + Live Calendar)
    // =========================================================================
    
    private func dualWidgetStyle(date: Date) -> some View {
        HStack(spacing: 24) {
            // Widget Trái: Đồng hồ kim Bauhaus tinh xảo
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                
                AnalogClockFace(date: date, tintColor: primaryTint)
                    .padding(20)
            }
            .frame(width: 340, height: 290)
            
            // Widget Phải: Lịch tháng trực quan với ngày hiện tại nổi bật
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                
                StandbyCalendarCard(date: date, tintColor: primaryTint)
                    .padding(20)
            }
            .frame(width: 340, height: 290)
        }
    }
    
    // =========================================================================
    // MARK: - Style 3: Retro Flip Clock (Đồng hồ lật cổ điển)
    // =========================================================================
    
    private func retroFlipStyle(date: Date) -> some View {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: date)
        let minute = cal.component(.minute, from: date)
        let second = cal.component(.second, from: date)
        
        let hourStr = String(format: "%02d", hour)
        let minuteStr = String(format: "%02d", minute)
        let secondStr = String(format: "%02d", second)
        
        return VStack(spacing: 20) {
            HStack(spacing: 20) {
                // Thẻ lật Giờ
                FlipCard(text: hourStr, label: "HOURS", tintColor: primaryTint)
                
                // Thẻ lật Phút
                FlipCard(text: minuteStr, label: "MINUTES", tintColor: primaryTint)
                
                // Thẻ lật Giây (nhỏ hơn)
                if showSeconds {
                    FlipCard(text: secondStr, label: "SECONDS", isSmall: true, tintColor: primaryTint)
                }
            }
            
            // Nhãn ngày kiểu máy đánh chữ cơ khí
            HStack(spacing: 12) {
                Text(dayOfWeekString(date: date).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(primaryTint)
                Text("•")
                    .foregroundStyle(.white.opacity(0.4))
                Text(fullDateString(date: date).uppercased())
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.05), in: Capsule())
        }
    }
    
    // =========================================================================
    // MARK: - Style 4: Solar Dial (Mặt trời & Tối giản)
    // =========================================================================
    
    private func solarDialStyle(date: Date) -> some View {
        let cal = Calendar.current
        let hour = Double(cal.component(.hour, from: date))
        let minute = Double(cal.component(.minute, from: date))
        let progress = (hour * 60 + minute) / (24 * 60)
        let sunAngle = progress * 360 - 90
        
        return HStack(spacing: 48) {
            // Vòng cung quỹ đạo mặt trời 24 giờ
            ZStack {
                // Vòng quỹ đạo nền
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.blue.opacity(0.4),
                                Color.orange.opacity(0.8),
                                Color.yellow.opacity(0.9),
                                Color.purple.opacity(0.6),
                                Color.blue.opacity(0.4)
                            ],
                            center: .center
                        ),
                        lineWidth: 8
                    )
                    .frame(width: 220, height: 220)
                
                // Vòng kim loại tối giản bên trong
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: 200, height: 200)
                
                // Mặt trời phát sáng di chuyển theo thời gian trong ngày
                Circle()
                    .fill(isNightRedActive ? Color.red : Color.yellow)
                    .frame(width: 22, height: 22)
                    .shadow(color: (isNightRedActive ? Color.red : Color.yellow).opacity(0.9), radius: 10)
                    .offset(x: 110 * cos(sunAngle * .pi / 180), y: 110 * sin(sunAngle * .pi / 180))
                
                // Giờ số ở trung tâm
                VStack(spacing: 2) {
                    Text(timeStringShort(date: date))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text(dateFormattedHeader(date: date).uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(primaryTint)
                }
            }
            
            // Thông tin ngày và tọa độ thời gian
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SOLAR POSITION")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .foregroundStyle(primaryTint)
                    
                    Text("\(Int(progress * 100))% OF DAY PASSED")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "sunrise.fill")
                            .foregroundStyle(.orange)
                        Text("Sunrise: 05:45 AM")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    HStack(spacing: 8) {
                        Image(systemName: "sunset.fill")
                            .foregroundStyle(.purple)
                        Text("Sunset: 06:15 PM")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
    
    // =========================================================================
    // MARK: - Bottom Style Switcher Bar
    // =========================================================================
    
    private var bottomStyleSwitcherBar: some View {
        HStack(spacing: 12) {
            // Nút chuyển giữa các kiểu đồng hồ
            HStack(spacing: 4) {
                ForEach(StandbyClockStyle.allCases) { style in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            clockStyle = style
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: style.systemIcon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(style.displayName)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            clockStyle == style
                                ? primaryTint.opacity(0.25)
                                : Color.white.opacity(0.06),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(clockStyle == style ? primaryTint.opacity(0.7) : Color.clear, lineWidth: 1)
                        )
                        .foregroundStyle(clockStyle == style ? .white : .white.opacity(0.65))
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Spacer()
            
            // Bộ chọn Theme màu sắc
            Menu {
                ForEach(StandbyTheme.allCases) { th in
                    Button {
                        theme = th
                    } label: {
                        HStack {
                            Text(th.displayName)
                            if theme == th {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(primaryTint)
                        .frame(width: 10, height: 10)
                    Text(theme.displayName)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            
            // Nút Night Mode nhanh
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    nightMode.toggle()
                }
            } label: {
                Image(systemName: nightMode ? "moon.fill" : "moon")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(nightMode ? Color.red : .white.opacity(0.6))
                    .padding(7)
                    .background(nightMode ? Color.red.opacity(0.2) : Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .help(nightMode ? "Turn off Night Mode" : "Turn on Red Night Mode")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.4), in: Capsule())
    }
    
    // =========================================================================
    // MARK: - Helpers & Formatters
    // =========================================================================
    
    private func updateBatteryInfo() {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for ps in sources {
            if let info = IOPSGetPowerSourceDescription(snapshot, ps).takeUnretainedValue() as? [String: Any] {
                let cur = info[kIOPSCurrentCapacityKey] as? Int ?? 100
                let max = info[kIOPSMaxCapacityKey] as? Int ?? 100
                let charging = (info[kIOPSIsChargingKey] as? Bool) ?? false
                let percent = max > 0 ? Int((Double(cur) / Double(max)) * 100) : cur
                self.batteryPercentage = percent
                self.isCharging = charging
                return
            }
        }
    }
    
    private var batteryIconName: String {
        if batteryPercentage >= 80 {
            return "battery.100"
        } else if batteryPercentage >= 50 {
            return "battery.75"
        } else if batteryPercentage >= 25 {
            return "battery.50"
        } else {
            return "battery.25"
        }
    }
    
    private func timeStringShort(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func dayOfWeekString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }
    
    private func fullDateString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMMM, yyyy"
        return formatter.string(from: date)
    }
    
    private func dateFormattedHeader(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE, d MMM"
        return formatter.string(from: date)
    }
}

// =========================================================================
// MARK: - Subcomponents
// =========================================================================

/// Mặt đồng hồ kim Bauhaus chính xác cao
private struct AnalogClockFace: View {
    let date: Date
    let tintColor: Color
    
    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2
            
            let cal = Calendar.current
            let hour = Double(cal.component(.hour, from: date) % 12)
            let minute = Double(cal.component(.minute, from: date))
            let second = Double(cal.component(.second, from: date)) + Double(cal.component(.nanosecond, from: date)) / 1_000_000_000.0
            
            let hourAngle = (hour + minute / 60.0) * 30.0 - 90.0
            let minuteAngle = (minute + second / 60.0) * 6.0 - 90.0
            let secondAngle = second * 6.0 - 90.0
            
            ZStack {
                // Mặt số tròn
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 2)
                
                // 12 Vạch giờ
                ForEach(0..<12) { i in
                    let isMain = (i % 3 == 0)
                    let angle = Double(i) * 30.0 * .pi / 180.0
                    let innerRadius = isMain ? radius - 16 : radius - 10
                    
                    Path { path in
                        path.move(to: CGPoint(x: center.x + innerRadius * cos(angle), y: center.y + innerRadius * sin(angle)))
                        path.addLine(to: CGPoint(x: center.x + (radius - 4) * cos(angle), y: center.y + (radius - 4) * sin(angle)))
                    }
                    .stroke(isMain ? Color.white : Color.white.opacity(0.3), lineWidth: isMain ? 3 : 1.5)
                }
                
                // Kim Giờ
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white)
                    .frame(width: radius * 0.52, height: 5)
                    .offset(x: radius * 0.26)
                    .rotationEffect(.degrees(hourAngle))
                    .shadow(radius: 3)
                
                // Kim Phút
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white.opacity(0.9))
                    .frame(width: radius * 0.75, height: 3.5)
                    .offset(x: radius * 0.375)
                    .rotationEffect(.degrees(minuteAngle))
                    .shadow(radius: 3)
                
                // Kim Giây lướt mượt mà
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(tintColor)
                        .frame(width: radius * 0.88, height: 1.8)
                        .offset(x: radius * 0.44)
                    
                    Circle()
                        .fill(tintColor)
                        .frame(width: 8, height: 8)
                }
                .rotationEffect(.degrees(secondAngle))
                .shadow(color: tintColor.opacity(0.6), radius: 4)
                
                // Trục tâm
                Circle()
                    .fill(Color.white)
                    .frame(width: 8, height: 8)
            }
        }
    }
}

/// Thẻ Lịch tháng phong cách StandBy
private struct StandbyCalendarCard: View {
    let date: Date
    let tintColor: Color
    
    private let cal = Calendar.current
    private let weekdaySymbols = ["S", "M", "T", "W", "T", "F", "S"]
    
    var body: some View {
        let currentDay = cal.component(.day, from: date)
        let daysInMonth = getDaysInCurrentMonth(for: date)
        let firstWeekdayOffset = getFirstWeekdayOffset(for: date)
        
        VStack(spacing: 12) {
            // Tiêu đề Tháng Năm
            HStack {
                Text(monthYearString(for: date).uppercased())
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(tintColor)
                Spacer()
                Text("TODAY \(currentDay)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            // Tiêu đề các thứ trong tuần
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { sym in
                    Text(sym)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(maxWidth: .infinity)
                }
            }
            
            // Lưới các ngày trong tháng
            let totalSlots = firstWeekdayOffset + daysInMonth.count
            let rows = Int(ceil(Double(totalSlots) / 7.0))
            
            VStack(spacing: 6) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { col in
                            let index = row * 7 + col
                            let dayNum = index - firstWeekdayOffset + 1
                            
                            if dayNum >= 1 && dayNum <= daysInMonth.count {
                                let isToday = (dayNum == currentDay)
                                ZStack {
                                    if isToday {
                                        Circle()
                                            .fill(tintColor)
                                            .frame(width: 24, height: 24)
                                            .shadow(color: tintColor.opacity(0.6), radius: 6)
                                    }
                                    
                                    Text("\(dayNum)")
                                        .font(.system(size: 11, weight: isToday ? .bold : .medium, design: .rounded))
                                        .foregroundStyle(isToday ? .white : .white.opacity(0.85))
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                Text("")
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
            
            Spacer(minLength: 0)
        }
    }
    
    private func monthYearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: date)
    }
    
    private func getDaysInCurrentMonth(for date: Date) -> [Int] {
        guard let range = cal.range(of: .day, in: .month, for: date) else { return Array(1...30) }
        return Array(range)
    }
    
    private func getFirstWeekdayOffset(for date: Date) -> Int {
        guard let startOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: date)) else { return 0 }
        let weekday = cal.component(.weekday, from: startOfMonth)
        return weekday - 1
    }
}

/// Thẻ lật cơ khí Split-Flap 3D
private struct FlipCard: View {
    let text: String
    let label: String
    var isSmall: Bool = false
    let tintColor: Color
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                // Khung nền thẻ lật
                RoundedRectangle(cornerRadius: isSmall ? 14 : 18, style: .continuous)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: isSmall ? 14 : 18, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
                
                // Chữ số thẻ lật
                Text(text)
                    .font(.system(size: isSmall ? 64 : 108, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.white)
                    .shadow(radius: 2)
                
                // Rãnh chia cắt ngang ở giữa (đặc trưng của Flip Clock)
                Rectangle()
                    .fill(Color.black.opacity(0.75))
                    .frame(height: 2)
                    .shadow(color: Color.black.opacity(0.8), radius: 1, y: 1)
            }
            .frame(width: isSmall ? 110 : 180, height: isSmall ? 130 : 180)
            .shadow(color: Color.black.opacity(0.4), radius: 10, y: 6)
            
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(tintColor.opacity(0.85))
        }
    }
}
