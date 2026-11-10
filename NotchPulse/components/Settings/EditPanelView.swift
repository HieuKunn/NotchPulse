import SwiftUI

struct EditPanelView: View {
    @State var wallpaperPath: URL?
    var body: some View {
        VStack {
            HStack {
                Text(loc("Edit layout"))
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    NSApp.keyWindow?.orderOut(nil)
                } label: {
                    Label(loc("Close"), systemImage: "xmark")
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context _: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
        visualEffectView.state = .active
        return visualEffectView
    }

    func updateNSView(_ visualEffectView: NSVisualEffectView, context _: Context) {
        visualEffectView.material = material
        visualEffectView.blendingMode = blendingMode
    }
}

#Preview {
    EditPanelView()
}
