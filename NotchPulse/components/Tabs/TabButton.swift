import SwiftUI

struct TabButton: View {
    let label: String
    let icon: String
    let selected: Bool
    let onClick: () -> Void
    
    var body: some View {
        Button(action: onClick) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: selected ? .semibold : .medium))
                .padding(.horizontal, 13)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    TabButton(label: "Home", icon: "tray.fill", selected: true) {
        print("Tapped")
    }
}
