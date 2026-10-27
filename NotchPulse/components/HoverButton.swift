import SwiftUI

struct HoverButton: View {
    var icon: String
    var iconColor: Color = .primary
    var scale: Image.Scale = .medium
    var action: () -> Void
    var contentTransition: ContentTransition = .symbolEffect;
    
    @State private var isHovering = false

    var body: some View {
        let size = CGFloat(scale == .large ? 36 : 28)
        
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovering ? Color.white.opacity(0.12) : Color.clear)
                    .frame(width: size, height: size)
                Circle()
                    .stroke(isHovering ? Color.white.opacity(0.16) : Color.clear, lineWidth: 0.5)
                    .frame(width: size, height: size)
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
                    .contentTransition(contentTransition)
                    .font(scale == .large ? .title3.weight(.bold) : .system(size: 12, weight: .semibold))
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.3)) {
                isHovering = hovering
            }
        }
    }
}
