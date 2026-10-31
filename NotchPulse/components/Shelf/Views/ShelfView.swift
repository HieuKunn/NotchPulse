import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var isShelfTargeted = false
    @State private var dropEventResetTask: Task<Void, Never>?
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .frame(width: 130)
                .frame(maxHeight: .infinity)
                .environmentObject(vm)
            panel
                .frame(maxHeight: .infinity)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isShelfTargeted) { providers in
                    handleDrop(providers: providers)
                }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isShelfTargeted) { _, targeted in
            vm.shelfDropTargeting = targeted
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .onChange(of: vm.notchState) { _, newState in
            if newState == .closed && !NotchPulseViewCoordinator.shared.openLastTabByDefault {
                tvm.isPinned = false
            }
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        isShelfTargeted = false
        vm.shelfDropTargeting = false
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        dropEventResetTask?.cancel()
        dropEventResetTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            vm.dropEvent = false
            if !tvm.isPinned,
               !CalendarStateViewModel.shared.isPinned,
               !vm.anyDropZoneTargeting,
               !vm.isMouseHovering() {
                vm.close()
            }
        }
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isShelfTargeted
                            ? Color.accentColor.opacity(0.9)
                            : Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 6])
                    )
            )
            .overlay {
                content
                    .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                pinButton
                    .padding(10)
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
    }

    var pinButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                tvm.isPinned.toggle()
            }
            if !tvm.isPinned && !vm.isMouseHovering() {
                vm.close()
            }
        } label: {
            Image(systemName: tvm.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tvm.isPinned ? Color.effectiveAccent : Color.white.opacity(0.65))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tvm.isPinned ? Color.effectiveAccent.opacity(0.22) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(tvm.isPinned ? Color.effectiveAccent.opacity(0.6) : Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(tvm.isPinned ? loc("Unpin Shelf (Close on hover exit)") : loc("Pin Shelf (Keep open when hovering out)"))
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(
                            isShelfTargeted ? Color.accentColor : Color.white.opacity(0.75)
                        )
                        .scaleEffect(isShelfTargeted ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShelfTargeted)
                    
                    Text(loc("Drop files here"))
                        .foregroundStyle(.white.opacity(0.85))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: spacing) {
                            ForEach(tvm.items) { item in
                                ShelfItemView(item: item)
                                    .environmentObject(quickLookService)
                                    .id(item.id)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .background(ShelfScrollWheelHelper())
                    .scrollIndicators(.never)
                    .onChange(of: tvm.items.count) { oldCount, newCount in
                        guard newCount > oldCount, let lastID = tvm.items.last?.id else { return }
                        Task { @MainActor in
                            await Task.yield()
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .trailing)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}

/// Routes a regular mouse wheel's vertical delta into the Shelf's horizontal
/// `NSScrollView`. Trackpad horizontal gestures keep their native behavior.
private struct ShelfScrollWheelHelper: NSViewRepresentable {
    func makeNSView(context: Context) -> HelperView {
        HelperView()
    }

    func updateNSView(_ nsView: HelperView, context: Context) {
        nsView.installMonitorIfNeeded()
    }

    final class HelperView: NSView {
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                removeMonitor()
            } else {
                installMonitorIfNeeded()
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if superview != nil {
                installMonitorIfNeeded()
            }
        }

        deinit {
            removeMonitor()
        }

        func installMonitorIfNeeded() {
            guard monitor == nil, window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self,
                      let window = self.window,
                      event.window === window,
                      let scrollView = self.enclosingScrollView else {
                    return event
                }

                let point = scrollView.convert(event.locationInWindow, from: nil)
                guard scrollView.bounds.contains(point) else { return event }

                let deltaX = event.scrollingDeltaX
                let deltaY = event.scrollingDeltaY
                guard abs(deltaY) > abs(deltaX), abs(deltaY) > 0 else { return event }

                let clipView = scrollView.contentView
                let documentWidth = scrollView.documentView?.bounds.width ?? 0
                let maximumX = max(0, documentWidth - clipView.bounds.width)
                guard maximumX > 0 else { return event }

                let multiplier: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 16
                var origin = clipView.bounds.origin
                origin.x = min(maximumX, max(0, origin.x - deltaY * multiplier))
                clipView.scroll(to: origin)
                scrollView.reflectScrolledClipView(clipView)
                return nil
            }
        }

        func removeMonitor() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
    }
}
