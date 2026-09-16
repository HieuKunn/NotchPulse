//
//  NotchBatteryView.swift
//  NotchPulse
//
//  Created for NotchPulse v3.8 - Native Battery & Smart Charging Hub
//

import SwiftUI
import Defaults

struct NotchBatteryView: View {
    @ObservedObject var battery = NativeBatteryManager.shared
    @State private var showingHelperInstall: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // MARK: - Left Card: 3 Charging Modes (BatteryToolkit Style)
            VStack(alignment: .leading, spacing: 10) {
                // Section Title
                HStack {
                    Image(systemName: "bolt.badge.automatic.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.green)
                    Text("Chế độ sạc pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if battery.isDesktopMode {
                        Text("Desktop Mode")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                
                // 3 Mode Segmented Buttons
                HStack(spacing: 6) {
                    ForEach(NativeBatteryManager.ChargingMode.allCases) { mode in
                        let isSelected = battery.chargingMode == mode
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                battery.setMode(mode)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 13, weight: .medium))
                                Text(mode.title)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? Color.green.opacity(0.28) : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? Color.green.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .foregroundStyle(isSelected ? .green : .white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Custom Charge Limit Slider (when in To Limit mode)
                if battery.chargingMode == .toLimit {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Dừng sạc ở mức:")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(battery.chargeLimit)%")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                        
                        Slider(
                            value: Binding(
                                get: { Double(battery.chargeLimit) },
                                set: { battery.setChargeLimit(percent: Int($0)) }
                            ),
                            in: 50...95,
                            step: 5
                        )
                        .tint(.green)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if battery.chargingMode == .inhibit {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 11))
                            .foregroundStyle(.cyan)
                        Text("Đang chạy nguồn AC trực tiếp, sạc pin đã tạm ngắt để bảo vệ pin.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(Color.cyan.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                        Text("Sạc pin tự do đến 100% không giới hạn.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                
                Spacer(minLength: 0)
                
                // Helper Control Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(battery.isHelperInstalled ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(battery.isHelperInstalled ? "Quyền SMC sẵn sàng" : "Chưa cài quyền SMC")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if !battery.isHelperInstalled {
                        Button("Cài đặt quyền") {
                            battery.installHelper { _ in }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(.orange)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // MARK: - Right Card: Live Hardware Stats & Telemetry
            VStack(alignment: .leading, spacing: 8) {
                // Top: Battery Level & Live Pill
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("\(battery.level)%")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            if battery.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.green)
                            } else if battery.isPluggedIn {
                                Image(systemName: "powerplug.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.cyan)
                            }
                        }
                        
                        Text(battery.isCharging ? "Đang sạc..." : (battery.isPluggedIn ? "Nguồn điện ngoài (AC)" : "Đang dùng pin"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Battery Visual Fill Pill
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 52, height: 18)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: battery.level <= 20 ? [.red, .orange] : [.green, Color(red: 0.2, green: 0.9, blue: 0.4)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, 52 * CGFloat(battery.level) / 100.0), height: 18)
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.1))
                
                // Telemetry Data Rows
                VStack(spacing: 5) {
                    HStack {
                        Label("Sức khoẻ pin", systemImage: "heart.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%% • %d chu kỳ", battery.healthPercent, battery.cycleCount))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Label("Công suất", systemImage: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%+.1f W", battery.wattage))
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(battery.wattage > 0 ? .green : (battery.wattage < 0 ? .orange : .secondary))
                    }
                    
                    HStack {
                        Label("Nhiệt độ", systemImage: "thermometer.medium")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f °C", battery.temperature))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(battery.temperature > 38 ? .orange : .white)
                    }
                    
                    HStack {
                        Label("Củ sạc (Adapter)", systemImage: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(battery.adapterWatts > 0 ? "\(battery.adapterWatts)W \(battery.adapterName)" : battery.adapterName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .onAppear {
            battery.updateBatteryStatus()
        }
    }
}

#Preview {
    NotchBatteryView()
        .frame(width: 640, height: 160)
        .background(Color.black)
}
