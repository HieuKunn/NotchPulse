//
//  InlineHUDs.swift
//  NotchPulse
//
//  Created by Richard Kunkli on 14/09/2024.
//

import SwiftUI
import Defaults

struct InlineHUD: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @Default(.notchStyle) var notchStyle
    @Binding var type: SneakContentType
    @Binding var value: CGFloat
    @Binding var icon: String
    @Binding var hoverAnimation: Bool
    @Binding var gestureProgress: CGFloat
    var body: some View {
        let isDynamicIsland = notchStyle == .dynamicIsland
        let hudHeight: CGFloat = isDynamicIsland ? 32.0 : vm.effectiveClosedNotchHeight
        HStack {
            HStack(spacing: 5) {
                Group {
                    switch (type) {
                        case .volume:
                            if icon.isEmpty {
                                Image(systemName: SpeakerSymbol(value))
                                    .contentTransition(.interpolate)
                                    .symbolVariant(value > 0 ? .none : .slash)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            } else {
                                Image(systemName: icon)
                                    .contentTransition(.interpolate)
                                    .opacity(value.isZero ? 0.6 : 1)
                                    .scaleEffect(value.isZero ? 0.85 : 1)
                                    .frame(width: 20, height: 15, alignment: .leading)
                            }
                        case .brightness:
                            Button(action: {
                                brightnessManager.toggleTargetDisplay()
                            }) {
                                Image(systemName: icon.isEmpty ? (brightnessManager.isCurrentBuiltin ? BrightnessSymbol(value) : "display") : icon)
                                    .contentTransition(.interpolate)
                                    .frame(width: 20, height: 15, alignment: .center)
                            }
                            .buttonStyle(PlainButtonStyle())
                        case .backlight:
                            Image(systemName: value > 0.5 ? "light.max" : "light.min")
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .mic:
                            Image(systemName: "mic")
                                .symbolRenderingMode(.hierarchical)
                                .symbolVariant(value > 0 ? .none : .slash)
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 15, alignment: .center)
                        case .battery:
                            Image(systemName: icon.isEmpty ? "headphones" : icon)
                                .font(.system(size: 14, weight: .semibold))
                                .contentTransition(.interpolate)
                                .frame(width: 20, height: 16, alignment: .center)
                        default:
                            EmptyView()
                    }
                }
                .foregroundStyle(.white)
                .symbolVariant(.fill)
                
                if type == .brightness {
                    Button(action: {
                        brightnessManager.toggleTargetDisplay()
                    }) {
                        Text(Type2Name(type))
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(1)
                            .allowsTightening(true)
                            .contentTransition(.numericText())
                    }
                    .buttonStyle(PlainButtonStyle())
                } else if type != .battery {
                    Text(Type2Name(type))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .contentTransition(.numericText())
                }
            }
            .padding(.leading, 14)
            .frame(width: InlineHUD.leftColumnWidth(for: type) + gestureProgress / 2, height: max(0, hudHeight - (hoverAnimation ? 0 : 12)), alignment: type == .battery ? .center : .leading)
            
            Rectangle()
                .fill(.black)
                .frame(width: InlineHUD.centerSpacerWidth(isDynamicIsland: isDynamicIsland, closedNotchWidth: vm.closedNotchSize.width))
            
            HStack {
                if (type == .battery) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.18), lineWidth: 2.2)
                        Circle()
                            .trim(from: 0, to: max(0.01, min(1.0, value)))
                            .stroke(
                                Color.green,
                                style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(round(value * 100)))")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .allowsTightening(true)
                    }
                    .frame(width: 22, height: 22)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if (type == .mic) {
                    Text(value.isZero ? "muted" : "unmuted")
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .allowsTightening(true)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .contentTransition(.interpolate)
                } else {
                    HStack {
                        DraggableProgressBar(value: $value, onChange: { v in
                            if type == .volume {
                                VolumeManager.shared.setAbsolute(Float32(v))
                            } else if type == .brightness {
                                BrightnessManager.shared.setAbsolute(value: Float32(v))
                            }
                        })
                        if (type == .volume && value.isZero) {
                            Text(loc("muted"))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .multilineTextAlignment(.trailing)
                        } else if Defaults[.showClosedNotchHUDPercentage] {
                            Text("\(Int(value * 100))%")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.gray)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .contentTransition(.numericText())
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }
            }
            .padding(.trailing, 14)
            .frame(width: InlineHUD.rightColumnWidth(for: type) + gestureProgress / 2, height: max(0, hudHeight - (hoverAnimation ? 0 : 12)), alignment: .center)
        }
        .frame(height: hudHeight + (hoverAnimation ? 8 : 0), alignment: .center)
    }
    
    func SpeakerSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0:
                return "speaker"
            case 0...0.3:
                return "speaker.wave.1"
            case 0.3...0.8:
                return "speaker.wave.2"
            case 0.8...1:
                return "speaker.wave.3"
            default:
                return "speaker.wave.2"
        }
    }
    
    func BrightnessSymbol(_ value: CGFloat) -> String {
        switch(value) {
            case 0...0.6:
                return "sun.min"
            case 0.6...1:
                return "sun.max"
            default:
                return "sun.min"
        }
    }
    
    func Type2Name(_ type: SneakContentType) -> String {
        switch(type) {
            case .volume:
                return "Volume"
            case .brightness:
                return brightnessManager.currentDisplayName
            case .backlight:
                return "Backlight"
            case .mic:
                return "Mic"
            case .battery:
                return ""
            default:
                return ""
        }
    }

    static func leftColumnWidth(for type: SneakContentType) -> CGFloat {
        switch type {
        case .brightness:
            return 98
        case .backlight:
            return 88
        case .mic:
            return 64
        case .battery:
            return 38
        default:
            return 88
        }
    }

    static func rightColumnWidth(for type: SneakContentType) -> CGFloat {
        switch type {
        case .mic:
            return 64
        case .battery:
            return 38
        default:
            return 94
        }
    }

    static func centerSpacerWidth(isDynamicIsland: Bool, closedNotchWidth: CGFloat) -> CGFloat {
        max(0, closedNotchWidth - 12)
    }

    static func totalWidth(for type: SneakContentType, isDynamicIsland: Bool, closedNotchWidth: CGFloat) -> CGFloat {
        let left = leftColumnWidth(for: type)
        let right = rightColumnWidth(for: type)
        let center = centerSpacerWidth(isDynamicIsland: isDynamicIsland, closedNotchWidth: closedNotchWidth)
        let padding: CGFloat = isDynamicIsland ? 12 : 14
        return left + center + right + padding
    }
}

#Preview {
    InlineHUD(type: .constant(.brightness), value: .constant(0.4), icon: .constant(""), hoverAnimation: .constant(false), gestureProgress: .constant(0))
        .padding(.horizontal, 8)
        .background(Color.black)
        .padding()
        .environmentObject(NotchPulseViewModel())
}
