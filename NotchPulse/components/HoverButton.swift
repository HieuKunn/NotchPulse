//
//  HoverButton.swift
//  NotchPulse
//
//  Created by Kraigo on 04.09.2024.
//

import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;
    
    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 40 : 30)
        
        Button(action: action) {
            ZStack {
                Color.black.opacity(0.001)
                Capsule()
                    .fill(isHovering ? Color.gray.opacity(0.2) : .clear)
                    .frame(width: size, height: size)
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .contentTransition(contentTransition)
                    .font(scale == .large ? .largeTitle : .body)
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}
