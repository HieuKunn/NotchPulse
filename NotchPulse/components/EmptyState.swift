import SwiftUI

struct EmptyStateView: View {
    var message: String
    @State private var isVisible = true
    
    var body: some View {
        HStack {
            Image(systemName: "music.note")
                .font(.system(size: 20))
                .foregroundColor(.gray)
            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.gray)
        }.transition(.blurReplace.animation(.spring(.bouncy(duration: 0.3)))) // Smooth animation
    }
}

#Preview {
    EmptyStateView(message: "Play some music babies")
}
