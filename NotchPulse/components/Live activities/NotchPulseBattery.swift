import SwiftUI
import Defaults

/// A view that displays the battery status with an icon and charging indicator.
struct BatteryView: View {

    var levelBattery: Float
    var isPluggedIn: Bool
    var isCharging: Bool
    var isInLowPowerMode: Bool
    var batteryWidth: CGFloat = 26
    var isForNotification: Bool

    var icon: String = "battery.0"

    /// Determines the icon to display when charging.
    var iconStatus: String {
        if isCharging {
            return "bolt"
        }
        else if isPluggedIn {
            return "plug"
        }
        else {
            return ""
        }
    }

    /// Determines the color of the battery based on its status.
    var batteryColor: Color {
        if isInLowPowerMode {
            return .yellow
        } else if levelBattery <= 20 && !isCharging && !isPluggedIn {
            return .red
        } else if isCharging || isPluggedIn || levelBattery == 100 {
            return .green
        } else {
            return .white
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {

            Image(systemName: icon)
                .resizable()
                .fontWeight(.thin)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.5))
                .frame(
                    width: batteryWidth + 1
                )

            RoundedRectangle(cornerRadius: 2.5)
                .fill(batteryColor)
                .frame(
                    width: CGFloat(((CGFloat(CFloat(levelBattery)) / 100) * (batteryWidth - 6))),
                    height: (batteryWidth - 2.75) - 18
                )
                .padding(.leading, 2)

            if iconStatus != "" && (isForNotification || Defaults[.showPowerStatusIcons]) {
                ZStack {
                    Image(iconStatus)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .foregroundColor(.white)
                        .frame(
                            width: 17,
                            height: 17
                        )
                }
                .frame(width: batteryWidth, height: batteryWidth)
            }
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

/// A view that displays detailed battery information and settings.
struct BatteryMenuView: View {
    
    var isPluggedIn: Bool
    var isCharging: Bool
    var levelBattery: Float
    var maxCapacity: Float
    var timeToFullCharge: Int
    var isInLowPowerMode: Bool
    var onDismiss: () -> Void

    @Environment(\.openURL) private var openURL
    @StateObject private var batteryManager = NativeBatteryManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("Battery Status")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(batteryManager.level)%")
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(batteryManager.level <= 20 ? .red : .green)
            }
            
            // Health & Hardware info
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Health: \(String(format: "%.1f", batteryManager.healthPercent))%", systemImage: "heart.fill")
                    Spacer()
                    Text("\(batteryManager.cycleCount) Cycles")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
                
                if batteryManager.wattage != 0 {
                    HStack {
                        if batteryManager.wattage > 0 {
                            Label("Power: +\(String(format: "%.1f", batteryManager.wattage))W", systemImage: "bolt.fill")
                                .foregroundColor(.green)
                        } else {
                            Label("Power: \(String(format: "%.1f", batteryManager.wattage))W", systemImage: "arrow.down")
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        if batteryManager.temperature > 0 {
                            Text("\(String(format: "%.1f", batteryManager.temperature))°C")
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.subheadline)
                }
                
                if batteryManager.adapterWatts > 0 {
                    Label("Adapter: \(batteryManager.adapterWatts)W (\(batteryManager.adapterName))", systemImage: "powerplug.fill")
                        .font(.subheadline)
                }
                
                if isInLowPowerMode {
                    Label("Low Power Mode", systemImage: "bolt.circle")
                        .font(.subheadline)
                        .foregroundColor(.yellow)
                }
                
                if batteryManager.isDesktopMode {
                    HStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("Desktop Mode (Dừng sạc ở \(batteryManager.chargeLimit)%)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.green)
                    }
                    .padding(.vertical, 2)
                } else if isCharging && timeToFullCharge > 0 {
                    Label("Còn \(timeToFullCharge) phút để sạc đầy", systemImage: "clock")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)

            Divider().background(Color.white.opacity(0.3))
            
            // Charge Limit controls
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Giới hạn sạc:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Spacer()
                    Text("\(batteryManager.chargeLimit)%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
                
                HStack(spacing: 8) {
                    Button {
                        batteryManager.toggleChargeLimit()
                    } label: {
                        HStack {
                            Image(systemName: batteryManager.chargeLimitEnabled ? "checkmark.circle.fill" : "circle")
                            Text(batteryManager.chargeLimitEnabled ? "Đang bật (\(batteryManager.chargeLimit)%)" : "Bật giới hạn")
                        }
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(batteryManager.chargeLimitEnabled ? Color.green.opacity(0.2) : Color.white.opacity(0.1))
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    
                    if batteryManager.isPluggedIn {
                        Button {
                            batteryManager.requestFullCharge()
                        } label: {
                            HStack {
                                Image(systemName: "battery.100.bolt")
                                Text("Sạc đầy")
                            }
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().background(Color.white.opacity(0.3))

            Button(action: openBatteryPreferences) {
                Label("System Settings...", systemImage: "gearshape")
                    .font(.subheadline)
                    .fontWeight(.regular)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .buttonStyle(.plain)
        }
        .padding()
        .frame(width: 290)
        .foregroundColor(.white)
        .onAppear {
            batteryManager.startMonitoring()
        }
        .onDisappear {
            batteryManager.stopMonitoring()
        }
    }

    private func openBatteryPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.battery") {
            openURL(url)
            onDismiss()
        }
    }
}

/// A view that displays the battery status and allows interaction to show detailed information.
struct NotchPulseBatteryView: View {
    
    @State var batteryWidth: CGFloat = 26
    var isCharging: Bool = false
    var isInLowPowerMode: Bool = false
    var isPluggedIn: Bool = false
    var levelBattery: Float = 0
    var maxCapacity: Float = 0
    var timeToFullCharge: Int = 0
    @State var isForNotification: Bool = false
    
    @State private var showPopupMenu: Bool = false
    @State private var isPressed: Bool = false
    @State private var isHoveringButton: Bool = false
    @State private var isHoveringPopover: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    @EnvironmentObject var vm: NotchPulseViewModel

    var body: some View {
        Button(action: {
            withAnimation {
                showPopupMenu.toggle()
            }
        }) {
            HStack {
                if Defaults[.showBatteryPercentage] {
                    Text("\(Int32(levelBattery))%")
                        .font(.callout)
                        .foregroundStyle(.white)
                }
                BatteryView(
                    levelBattery: levelBattery,
                    isPluggedIn: isPluggedIn,
                    isCharging: isCharging,
                    isInLowPowerMode: isInLowPowerMode,
                    batteryWidth: batteryWidth,
                    isForNotification: isForNotification
                )
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .popover(
            isPresented: $showPopupMenu,
            arrowEdge: .bottom) {
            BatteryMenuView(
                isPluggedIn: isPluggedIn,
                isCharging: isCharging,
                levelBattery: levelBattery,
                maxCapacity: maxCapacity,
                timeToFullCharge: timeToFullCharge,
                isInLowPowerMode: isInLowPowerMode,
                onDismiss: { 
                    showPopupMenu = false
                }
            )
            .onHover { hovering in
                isHoveringPopover = hovering
                if hovering {
                    hideTask?.cancel()
                    hideTask = nil
                } else {
                    scheduleHideIfNeeded()
                }
            }
        }
        .onChange(of: showPopupMenu) {
            vm.isBatteryPopoverActive = showPopupMenu
        }
        .onDisappear {
            hideTask?.cancel()
            hideTask = nil
        }
    }

    private func scheduleHideIfNeeded() {
        if isHoveringButton || isHoveringPopover { return }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation { showPopupMenu = false } }
        }
    }
}

#Preview {
    NotchPulseBatteryView(
        batteryWidth: 30,
        isCharging: false,
        isInLowPowerMode: false,
        isPluggedIn: true,
        levelBattery: 80,
        maxCapacity: 100,
        timeToFullCharge: 10,
        isForNotification: false
    ).frame(width: 200, height: 200)
}
