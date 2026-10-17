import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect
    
    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 38 : 28)
        let iconFont: Font = (scale == .large) ? .title2.weight(.semibold) : .subheadline.weight(.medium)
        
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovering ? Color.primary.opacity(0.12) : Color.clear)
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(isHovering ? 0.16 : 0), lineWidth: 0.8)
                    )
                    .frame(width: size, height: size)
                
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .contentTransition(contentTransition)
                    .font(iconFont)
                    .scaleEffect(isHovering ? 1.06 : 1.0)
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.75)) {
                isHovering = hovering
            }
        }
    }
}
