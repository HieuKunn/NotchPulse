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
            // MARK: - Left Card: 3 Charging Modes (50% Width)
            VStack(alignment: .leading, spacing: 6) {
                // Section Title
                HStack {
                    Image(systemName: "bolt.badge.automatic.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.green)
                    Text("Charging Mode")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    if battery.isDesktopMode {
                        Text("Desktop Mode")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.cyan)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.cyan.opacity(0.18))
                            .clipShape(Capsule())
                    }
                }
                
                // 3 Mode Segmented Buttons
                HStack(spacing: 5) {
                    ForEach(NativeBatteryManager.ChargingMode.allCases) { mode in
                        let isSelected = battery.chargingMode == mode
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                battery.setMode(mode)
                            }
                        } label: {
                            VStack(spacing: 3) {
                                Image(systemName: mode.icon)
                                    .font(.system(size: 11.5, weight: .medium))
                                Text(mode.title)
                                    .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? Color.green.opacity(0.28) : Color.white.opacity(0.06))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(isSelected ? Color.green.opacity(0.8) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                            .foregroundStyle(isSelected ? .green : .white.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                // Custom Charge Limit Slider (when in Charge to Limit mode)
                if battery.chargingMode == .toLimit {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Auto-stop limit:")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(battery.chargeLimit)%")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
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
                        .controlSize(.mini)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                } else if battery.chargingMode == .inhibit {
                    HStack(spacing: 5) {
                        Image(systemName: "powerplug.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.cyan)
                        Text("Direct AC power active; battery charging is paused.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(5)
                    .background(Color.cyan.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.yellow)
                        Text("Top up to 100% full capacity.")
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(5)
                    .background(Color.yellow.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                
                Spacer(minLength: 0)
                
                // Helper Control Status
                HStack(spacing: 4) {
                    Circle()
                        .fill(battery.isHelperInstalled ? Color.green : Color.orange)
                        .frame(width: 5, height: 5)
                    Text(battery.isHelperInstalled ? "SMC Access Ready" : "SMC Helper Required")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    if !battery.isHelperInstalled {
                        Button("Install") {
                            battery.installHelper { _ in }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                        .tint(.orange)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            
            // MARK: - Right Card: Live Hardware Stats & Telemetry (50% Width)
            VStack(alignment: .leading, spacing: 4) {
                // Top: Battery Level & Live Pill
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            Text("\(battery.level)%")
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            
                            if battery.isCharging {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.green)
                            } else if battery.isPluggedIn {
                                Image(systemName: "powerplug.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.cyan)
                            }
                        }
                        
                        Text(battery.isCharging ? "Charging..." : (battery.isPluggedIn ? "AC Connected (Idle)" : "On Battery"))
                            .font(.system(size: 8.5))
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Battery Visual Fill Pill
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.15))
                            .frame(width: 44, height: 15)
                        
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: battery.level <= 20 ? [.red, .orange] : [.green, Color(red: 0.2, green: 0.9, blue: 0.4)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(6, 44 * CGFloat(battery.level) / 100.0), height: 15)
                    }
                }
                
                Divider()
                    .background(Color.white.opacity(0.08))
                    .padding(.vertical, 1)
                
                // Telemetry Data Rows
                VStack(spacing: 3) {
                    HStack {
                        Label("Battery Health", systemImage: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f%% • %d cycles", battery.healthPercent, battery.cycleCount))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    
                    HStack {
                        Label("Power", systemImage: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%+.1f W", battery.wattage))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(battery.wattage > 0 ? .green : (battery.wattage < 0 ? .orange : .secondary))
                    }
                    
                    HStack {
                        Label("Temperature", systemImage: "thermometer.medium")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1f °C", battery.temperature))
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(battery.temperature > 38 ? .orange : .white)
                    }
                    
                    HStack {
                        Label("Power Adapter", systemImage: "bolt.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(battery.adapterWatts > 0 ? "\(battery.adapterWatts)W \(battery.adapterName)" : battery.adapterName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .padding(.horizontal, 18)
        .padding(.top, 2)
        .padding(.bottom, 14)
        .onAppear {
            battery.startMonitoring()
        }
        .onDisappear {
            battery.stopMonitoring()
        }
    }
}

#Preview {
    NotchBatteryView()
        .frame(width: 640, height: 160)
        .background(Color.black)
}
