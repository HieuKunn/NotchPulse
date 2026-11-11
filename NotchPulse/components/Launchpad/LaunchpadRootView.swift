@preconcurrency import AppKit
import CoreImage
import Defaults
import SwiftUI

/// Caches downsampled, Gaussian-blurred desktop wallpaper images per screen URL
/// so classic Launchpad backdrop opens instantaneously without main-thread hitches.
final class LaunchpadBlurredWallpaperCache: @unchecked Sendable {
    static let shared = LaunchpadBlurredWallpaperCache()

    private let cache = NSCache<NSURL, NSImage>()
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private init() {
        cache.countLimit = 4
    }

    func cachedImage(for url: URL) -> NSImage? {
        cache.object(forKey: url as NSURL)
    }

    func loadBlurredWallpaper(from url: URL) -> NSImage? {
        if let existing = cache.object(forKey: url as NSURL) {
            return existing
        }
        guard let sourceImage = NSImage(contentsOf: url),
              let tiffData = sourceImage.tiffRepresentation,
              let ciInput = CIImage(data: tiffData) else {
            return nil
        }

        let extent = ciInput.extent
        guard extent.width > 0, extent.height > 0 else { return nil }

        // Keep high-res clarity (1440px) with a gentle classic macOS depth blur so real wallpaper details stay crisp
        let maxDim: CGFloat = 1440
        let scale = min(1.0, maxDim / max(extent.width, extent.height))
        let scaled = ciInput.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let clamped = scaled.clampedToExtent()

        guard let blur = CIFilter(name: "CIGaussianBlur") else { return nil }
        blur.setValue(clamped, forKey: kCIInputImageKey)
        blur.setValue(11.0, forKey: kCIInputRadiusKey)

        guard let blurred = blur.outputImage?.cropped(to: scaled.extent),
              let cgResult = ciContext.createCGImage(blurred, from: scaled.extent) else {
            return nil
        }

        let finalImage = NSImage(cgImage: cgResult, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
        cache.setObject(finalImage, forKey: url as NSURL)
        return finalImage
    }
}

/// Non-reactive reference store for tile frames so 120Hz animations/swipes never trigger SwiftUI body invalidations.
private final class LaunchpadTileFrameStore {
    var frames: [String: CGRect] = [:]
    var originY: CGFloat? = nil
}

/// Native NSVisualEffectView fallback when desktop wallpaper file cannot be read directly.
private struct LaunchpadVisualEffectBackdrop: NSViewRepresentable {
    let style: LaunchpadBackgroundStyle

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.appearance = NSAppearance(named: .darkAqua)
        view.blendingMode = .behindWindow
        view.state = .active
        switch style {
        case .systemGlass:
            view.material = .fullScreenUI
        case .dimmed:
            view.material = .hudWindow
        }
    }
}

/// Pure AppKit NSSearchField embedded inside native Liquid Glass (NSGlassEffectView on macOS 26+).
private struct LaunchpadNativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var focusToken: Int

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: LaunchpadNativeSearchField
        weak var searchField: NSSearchField?
        var lastFocusToken: Int = 0

        init(_ parent: LaunchpadNativeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if !parent.text.isEmpty {
                    parent.text = ""
                    searchField?.stringValue = ""
                    return true
                }
            }
            return false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let field = NSSearchField()
        field.appearance = NSAppearance(named: .darkAqua)
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.controlSize = .regular
        field.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        field.textColor = .labelColor
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.delegate = context.coordinator
        context.coordinator.searchField = field

        applyPlaceholder(to: field)

        let innerContainer = NSView()
        innerContainer.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.addSubview(field)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor, constant: 10),
            field.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor, constant: -10),
            field.centerYAnchor.constraint(equalTo: innerContainer.centerYAnchor)
        ])

        if #available(macOS 26.0, *),
           let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassClass.init()
            glass.appearance = NSAppearance(named: .darkAqua)
            glass.setValue(0, forKey: "style")
            glass.setValue(CGFloat(16), forKey: "cornerRadius")
            if glass.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
                glass.setValue(true, forKey: "effectIsInteractive")
            }
            glass.setValue(innerContainer, forKey: "contentView")
            return glass
        } else {
            let effect = NSVisualEffectView()
            effect.appearance = NSAppearance(named: .darkAqua)
            effect.material = .hudWindow
            effect.blendingMode = .withinWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = 16
            effect.layer?.masksToBounds = true
            effect.addSubview(innerContainer)
            NSLayoutConstraint.activate([
                innerContainer.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                innerContainer.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                innerContainer.topAnchor.constraint(equalTo: effect.topAnchor),
                innerContainer.bottomAnchor.constraint(equalTo: effect.bottomAnchor)
            ])
            return effect
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let field = context.coordinator.searchField else { return }

        if field.stringValue != text {
            field.stringValue = text
        }
        applyPlaceholder(to: field)

        if context.coordinator.lastFocusToken != focusToken && focusToken > 0 {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                if let window = field.window, window.firstResponder != field.currentEditor() {
                    window.makeFirstResponder(field)
                    if let editor = field.currentEditor() as? NSTextView {
                        editor.setSelectedRange(NSRange(location: field.stringValue.count, length: 0))
                    }
                }
            }
        }
    }

    private func applyPlaceholder(to field: NSSearchField) {
        guard let cell = field.cell as? NSSearchFieldCell else { return }
        cell.placeholderAttributedString = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
                .font: NSFont.systemFont(ofSize: 13.5, weight: .regular)
            ]
        )
    }
}

/// Fullscreen paged Launchpad Home view styled cleanly after classic macOS Launchpad.
struct LaunchpadRootView: View {
    @ObservedObject var manager: LaunchpadManager
    @ObservedObject var windowController: LaunchpadWindowController
    @StateObject private var dragCoordinator = LaunchpadDragCoordinator()

    @Default(.launchpadColumns) private var columns
    @Default(.launchpadRows) private var rows
    @Default(.launchpadIconSize) private var iconSize
    @Default(.launchpadShowLabels) private var showLabels
    @Default(.launchpadBackgroundStyle) private var backgroundStyle

    @State private var appPendingTrash: LaunchpadAppItem? = nil
    @State private var blurredWallpaper: NSImage? = nil
    @State private var zoomScale: CGFloat = 1.0
    @State private var isMouseSwipingPage = false

    var body: some View {
        GeometryReader { canvasGeo in
            let size = canvasGeo.size
            let metrics = LaunchpadGridLayoutMetrics(
                canvasSize: size,
                topNotchSafeInset: windowController.topNotchSafeInset,
                rows: rows,
                columns: columns,
                preferredIconSize: CGFloat(iconSize),
                showLabels: showLabels
            )
            ZStack {
                backdropLayer(size: size)

                VStack(spacing: 0) {
                    topSearchAndControlsBar
                        .padding(.top, windowController.topNotchSafeInset)
                        .padding(.bottom, 12)

                    if !manager.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchResultsView(metrics: metrics)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if manager.isScanning && manager.pages.isEmpty {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        pagedCarouselView(canvasSize: size, metrics: metrics)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if manager.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && manager.pages.count > 1 {
                        pageDotsIndicator
                            .padding(.top, 8)
                            .padding(.bottom, metrics.bottomDotsPadding)
                    } else {
                        Spacer(minLength: metrics.bottomDotsPadding)
                            .frame(height: metrics.bottomDotsPadding)
                    }
                }
                .frame(width: size.width, height: size.height)
                .scaleEffect(zoomScale)
                .scaleEffect(manager.activeFolderId != nil ? 0.94 : 1.0)
                .conditionalModifier(manager.activeFolderId != nil) { view in
                    view.blur(radius: 10).opacity(0.42)
                }

                if let activeFolder = manager.activeFolder {
                    LaunchpadFolderOverlayView(
                        folder: activeFolder,
                        iconSize: metrics.fittedIconSize,
                        showLabels: showLabels,
                        onOpenApp: { manager.launchApp($0) },
                        onRequestTrash: { appPendingTrash = $0 },
                        onDismiss: {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                manager.activeFolderId = nil
                            }
                        },
                        manager: manager,
                        dragCoordinator: dragCoordinator
                    )
                    .opacity(dragCoordinator.isFolderHiddenForExtraction ? 0 : 1)
                    .allowsHitTesting(!dragCoordinator.isFolderHiddenForExtraction)
                    .zIndex(20)
                }

                if let edgeDir = dragCoordinator.edgeTurnDirection, dragCoordinator.isDragging {
                    edgeTurnIndicator(direction: edgeDir)
                        .zIndex(25)
                }

                if let draggedNode = dragCoordinator.activeNode {
                    LaunchpadFloatingDragOverlay(
                        cursor: dragCoordinator.cursor,
                        node: draggedNode,
                        iconSize: metrics.fittedIconSize,
                        showLabel: showLabels
                    )
                    .allowsHitTesting(false)
                    .zIndex(40)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            .environment(\.colorScheme, .dark)
            .coordinateSpace(name: "LaunchpadCanvas")
            .onAppear {
                dragCoordinator.updateCanvasSize(size)
                loadWallpaperIfNeeded()
                triggerOpenZoomIfNeeded()
            }
            .onChange(of: size) { _, newSize in
                dragCoordinator.updateCanvasSize(newSize)
            }
            .onChange(of: windowController.currentScreenWallpaperURL) { _, _ in
                loadWallpaperIfNeeded()
            }
            .onChange(of: windowController.isPresented) { _, presented in
                if presented {
                    loadWallpaperIfNeeded()
                    triggerOpenZoomIfNeeded()
                } else {
                    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        withAnimation(.easeIn(duration: 0.14)) {
                            zoomScale = 1.05
                        }
                    }
                }
            }
            .alert(
                loc("Move Application to Trash?"),
                isPresented: Binding(
                    get: { appPendingTrash != nil },
                    set: { if !$0 { appPendingTrash = nil } }
                ),
                presenting: appPendingTrash
            ) { app in
                Button(loc("Move to Trash"), role: .destructive) {
                    manager.moveAppToTrash(app)
                    appPendingTrash = nil
                }
                Button(loc("Cancel"), role: .cancel) {
                    appPendingTrash = nil
                }
            } message: { app in
                Text(loc("Are you sure you want to move %@ to the Trash?", app.name))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Backdrop & Transitions

    private func triggerOpenZoomIfNeeded() {
        guard windowController.isPresented else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            zoomScale = 1.0
        } else {
            zoomScale = 1.05
            withAnimation(.spring(response: 0.22, dampingFraction: 0.90)) {
                zoomScale = 1.0
            }
        }
    }

    private func loadWallpaperIfNeeded() {
        guard let url = windowController.currentScreenWallpaperURL else {
            blurredWallpaper = nil
            return
        }
        if let cached = LaunchpadBlurredWallpaperCache.shared.cachedImage(for: url) {
            blurredWallpaper = cached
            return
        }
        Task.detached(priority: .userInitiated) {
            _ = LaunchpadBlurredWallpaperCache.shared.loadBlurredWallpaper(from: url)
            await MainActor.run {
                if LaunchpadWindowController.shared.currentScreenWallpaperURL == url {
                    blurredWallpaper = LaunchpadBlurredWallpaperCache.shared.cachedImage(for: url)
                }
            }
        }
    }

    @ViewBuilder
    private func backdropLayer(size: CGSize) -> some View {
        ZStack {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else if let wallpaper = blurredWallpaper {
                Image(nsImage: wallpaper)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(1.03)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                Color.black.opacity(backgroundStyle == .dimmed ? 0.36 : 0.14)
            } else {
                LaunchpadVisualEffectBackdrop(style: backgroundStyle)
                if backgroundStyle == .dimmed {
                    Color.black.opacity(0.36)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            handleBackgroundTap()
        }
    }

    private func handleBackgroundTap() {
        guard !isMouseSwipingPage else { return }
        if manager.isEditingMode {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                manager.isEditingMode = false
            }
        } else if manager.activeFolderId != nil {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                manager.activeFolderId = nil
            }
        } else {
            windowController.dismiss(restorePreviousApp: true)
        }
    }

    // MARK: - Top Classic Search Bar

    @ViewBuilder
    private var topSearchAndControlsBar: some View {
        LaunchpadNativeSearchField(
            text: $manager.searchQuery,
            placeholder: loc("Search"),
            onSubmit: {
                if let first = manager.searchResults.first {
                    manager.launchApp(first)
                }
            },
            focusToken: windowController.focusSearchToken
        )
        .frame(width: 268, height: 32)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Horizontal Paging Carousel

    @ViewBuilder
    private func pagedCarouselView(canvasSize: CGSize, metrics: LaunchpadGridLayoutMetrics) -> some View {
        let pageWidth = max(1, canvasSize.width)
        let pageTopOffset = windowController.topNotchSafeInset + 44

        ZStack {
            // Keep background-dismiss hit target strictly behind interactive app/folder tiles
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    handleBackgroundTap()
                }

            LaunchpadCarouselOffsetContainer(
                swipeState: windowController.swipeState,
                baseOffset: -CGFloat(manager.currentPageIndex) * pageWidth
            ) {
                HStack(spacing: 0) {
                    ForEach(Array(manager.pages.enumerated()), id: \.element.id) { pageIndex, page in
                        if abs(pageIndex - manager.currentPageIndex) <= 1 {
                            LaunchpadPageGridView(
                                page: page,
                                isCurrentPage: pageIndex == manager.currentPageIndex,
                                pageTopOffset: pageTopOffset,
                                gridColumns: metrics.gridColumns,
                                verticalSpacing: metrics.verticalSpacing,
                                iconSize: metrics.fittedIconSize,
                                showLabels: showLabels,
                                horizontalInset: metrics.horizontalInset,
                                manager: manager,
                                dragCoordinator: dragCoordinator,
                                onOpenApp: { manager.launchApp($0) },
                                onOpenFolder: { folder in
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                                        manager.activeFolderId = folder.id
                                    }
                                },
                                onRequestTrash: { appPendingTrash = $0 }
                            )
                            .frame(width: pageWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                        } else {
                            Color.clear
                                .frame(width: pageWidth)
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
                .frame(width: pageWidth * CGFloat(max(1, manager.pages.count)), alignment: .leading)
            }
        }
        .frame(width: pageWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .clipped()
        .simultaneousGesture(
            DragGesture(minimumDistance: 12, coordinateSpace: .local)
                .onChanged { value in
                    guard !dragCoordinator.isDragging,
                          manager.activeFolderId == nil,
                          manager.searchQuery.isEmpty,
                          manager.pages.count > 1 else {
                        return
                    }
                    if !isMouseSwipingPage {
                        guard abs(value.translation.width) >= abs(value.translation.height) * 1.15 else {
                            return
                        }
                        isMouseSwipingPage = true
                    }
                    windowController.applyHorizontalSwipe(rawDeltaX: value.translation.width)
                }
                .onEnded { value in
                    guard isMouseSwipingPage else { return }
                    windowController.commitHorizontalSwipe(
                        deltaX: value.translation.width,
                        predictedDeltaX: value.predictedEndTranslation.width,
                        pageWidth: pageWidth
                    )
                    DispatchQueue.main.async {
                        isMouseSwipingPage = false
                    }
                }
        )
    }

    // MARK: - Search Results Grid

    @ViewBuilder
    private func searchResultsView(metrics: LaunchpadGridLayoutMetrics) -> some View {
        let results = manager.searchResults
        if results.isEmpty {
            ContentUnavailableView {
                Label(loc("No applications found"), systemImage: "magnifyingglass")
            } description: {
                Text(loc("Try searching with a different application name."))
            }
        } else {
            ScrollView {
                LazyVGrid(columns: metrics.gridColumns, spacing: metrics.verticalSpacing) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                        LaunchpadTileView(
                            node: .app(app),
                            iconSize: metrics.fittedIconSize,
                            showLabel: showLabels,
                            isEditingMode: false,
                            isMergeTarget: false,
                            isBeingDragged: false,
                            isKeyboardHighlighted: index == 0,
                            allowsEditing: false,
                            onOpenApp: { manager.launchApp($0) },
                            onOpenFolder: { _ in },
                            onRequestTrash: { appPendingTrash = $0 },
                            manager: manager,
                            dragCoordinator: dragCoordinator
                        )
                    }
                }
                .padding(.horizontal, metrics.horizontalInset)
                .padding(.vertical, 16)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - Classic Floating Page Dots

    @ViewBuilder
    private var pageDotsIndicator: some View {
        HStack(spacing: 10) {
            ForEach(0..<manager.pages.count, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.88)) {
                        manager.currentPageIndex = index
                    }
                } label: {
                    Circle()
                        .fill(index == manager.currentPageIndex ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 8, height: 8)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Drag Helpers

    @ViewBuilder
    private func edgeTurnIndicator(direction: Int) -> some View {
        HStack {
            if direction < 0 {
                Image(systemName: "chevron.compact.left")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(18)
                    .background(.regularMaterial, in: Circle())
                    .padding(.leading, 24)
                Spacer()
            } else {
                Spacer()
                Image(systemName: "chevron.compact.right")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(18)
                    .background(.regularMaterial, in: Circle())
                    .padding(.trailing, 24)
            }
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

}

/// Dedicated 120Hz drag preview view so pointer motion only updates this single overlay.
private struct LaunchpadFloatingDragOverlay: View {
    @ObservedObject var cursor: LaunchpadDragCursor
    let node: LaunchpadNode
    let iconSize: CGFloat
    let showLabel: Bool

    var body: some View {
        VStack(spacing: 6) {
            switch node {
            case .app(let app):
                LaunchpadAppIconImage(bundlePath: app.bundlePath, size: iconSize * 1.12)
                    .shadow(color: Color.black.opacity(0.35), radius: 14, y: 7)
            case .folder(let folder):
                LaunchpadFolderThumbnailView(folder: folder, size: iconSize * 1.12)
                    .shadow(color: Color.black.opacity(0.35), radius: 14, y: 7)
            }
            if showLabel {
                Text(node.displayName)
                    .font(.system(size: max(12.5, min(16.5, (iconSize * 0.145).rounded())), weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
        .position(cursor.location)
    }
}

/// Isolates 120Hz swipe offset updates so page grids and tiles never re-evaluate during trackpad/mouse swipes.
private struct LaunchpadCarouselOffsetContainer<Content: View>: View {
    @ObservedObject var swipeState: LaunchpadSwipeState
    let baseOffset: CGFloat
    let content: Content

    init(
        swipeState: LaunchpadSwipeState,
        baseOffset: CGFloat,
        @ViewBuilder content: () -> Content
    ) {
        self.swipeState = swipeState
        self.baseOffset = baseOffset
        self.content = content()
    }

    var body: some View {
        content
            .offset(x: baseOffset + swipeState.offset)
    }
}

/// Computes display-proportional grid geometry so Launchpad fills any monitor
/// resolution cleanly from small laptops up to 4K/5K/6K external displays.
private struct LaunchpadGridLayoutMetrics {
    let horizontalInset: CGFloat
    let fittedIconSize: CGFloat
    let verticalSpacing: CGFloat
    let bottomDotsPadding: CGFloat
    let gridColumns: [GridItem]

    init(
        canvasSize: CGSize,
        topNotchSafeInset: CGFloat,
        rows: Int,
        columns: Int,
        preferredIconSize: CGFloat,
        showLabels: Bool
    ) {
        let safeRows = max(3, min(8, rows))
        let safeCols = max(4, min(10, columns))
        let userScale = max(0.75, min(1.35, preferredIconSize / 84.0))

        let inset = max(56, canvasSize.width * 0.078)
        let bottomMargin = max(28, canvasSize.height * 0.032)
        let bottomReserved = 22 + bottomMargin // dots bar height + bottom edge margin
        let topBarHeight = topNotchSafeInset + 44 // search field (32) + bottom spacing (12)
        let topGridPadding: CGFloat = 8

        let availableGridWidth = max(320, canvasSize.width - inset * 2)
        let availableGridHeight = max(280, canvasSize.height - topBarHeight - bottomReserved - topGridPadding - 12)

        let colSpacing = max(16, availableGridWidth * 0.016)
        let perColWidth = (availableGridWidth - colSpacing * CGFloat(safeCols - 1)) / CGFloat(safeCols)
        let perRowBudget = availableGridHeight / CGFloat(safeRows)

        // Ideal icon proportion fills ~77% of row slot height, scaled proportionally by user's size preference.
        let idealTileSlot = perRowBudget * 0.77
        let estimatedLabelBlock: CGFloat = showLabels ? max(22, perRowBudget * 0.16) : 6
        let naturalIcon = (idealTileSlot - estimatedLabelBlock) / 1.18
        let horizontalCap = perColWidth * 0.70

        let candidateIcon = naturalIcon * userScale
        let tentativeFont = max(12.5, min(16.5, (candidateIcon * 0.145).rounded()))
        let labelHeightForCap: CGFloat = showLabels ? (tentativeFont + 16) : 4
        let tileStaticVerticalOverhead: CGFloat = 8 + labelHeightForCap // VStack spacing / tile vertical padding
        let maxVerticalIconForMinGap = (perRowBudget - 8 - tileStaticVerticalOverhead) / 1.18

        let resolvedIcon = max(
            44,
            min(156, min(candidateIcon, min(horizontalCap, maxVerticalIconForMinGap)))
        )

        let resolvedFont = max(12.5, min(16.5, (resolvedIcon * 0.145).rounded()))
        let tileLabelBlock: CGFloat = showLabels ? (resolvedFont + 14 + max(6, resolvedIcon * 0.08)) : 0
        let tileRowHeight = resolvedIcon * 1.18 + tileLabelBlock + 8 // includes tile .padding(.vertical, 4)

        let remainingHeight = availableGridHeight - CGFloat(safeRows) * tileRowHeight
        let rowSpacing = safeRows > 1
            ? max(8, remainingHeight / CGFloat(safeRows - 1))
            : 0

        self.horizontalInset = inset
        self.fittedIconSize = resolvedIcon
        self.verticalSpacing = rowSpacing
        self.bottomDotsPadding = bottomMargin
        self.gridColumns = Array(
            repeating: GridItem(.flexible(minimum: resolvedIcon * 1.18), spacing: colSpacing),
            count: safeCols
        )
    }
}

/// Renders one horizontal Launchpad page and records rest-state tile geometry
/// without @State mutations so 120Hz animations and swipes run with zero overhead.
private struct LaunchpadPageGridView: View {
    let page: LaunchpadPage
    let isCurrentPage: Bool
    let pageTopOffset: CGFloat
    let gridColumns: [GridItem]
    let verticalSpacing: CGFloat
    let iconSize: CGFloat
    let showLabels: Bool
    let horizontalInset: CGFloat

    @ObservedObject var manager: LaunchpadManager
    @ObservedObject var dragCoordinator: LaunchpadDragCoordinator

    let onOpenApp: (LaunchpadAppItem) -> Void
    let onOpenFolder: (LaunchpadFolderItem) -> Void
    let onRequestTrash: (LaunchpadAppItem) -> Void

    @State private var frameStore = LaunchpadTileFrameStore()

    private var pageCoordSpaceName: String {
        "LaunchpadPage_\(page.id.uuidString)"
    }

    var body: some View {
        let showReorderIndicators = dragCoordinator.isDragging
            && isCurrentPage
            && dragCoordinator.mergeTargetNodeId == nil
            && (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction)

        LazyVGrid(columns: gridColumns, spacing: verticalSpacing) {
            ForEach(Array(page.nodes.enumerated()), id: \.element.id) { index, node in
                let insertBefore = showReorderIndicators
                    && dragCoordinator.reorderTargetIndex == index
                    && dragCoordinator.activeNode?.id != node.id
                let insertAfter = showReorderIndicators
                    && index == page.nodes.count - 1
                    && dragCoordinator.reorderTargetIndex == page.nodes.count
                    && dragCoordinator.activeNode?.id != node.id

                LaunchpadTileView(
                    node: node,
                    iconSize: iconSize,
                    showLabel: showLabels,
                    isEditingMode: manager.isEditingMode && isCurrentPage,
                    isMergeTarget: dragCoordinator.mergeTargetNodeId == node.id,
                    isBeingDragged: dragCoordinator.activeNode?.id == node.id,
                    isKeyboardHighlighted: false,
                    showInsertBefore: insertBefore,
                    showInsertAfter: insertAfter,
                    onOpenApp: onOpenApp,
                    onOpenFolder: onOpenFolder,
                    onRequestTrash: onRequestTrash,
                    manager: manager,
                    dragCoordinator: dragCoordinator
                )
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                frameStore.frames[node.id] = geo.frame(in: .named(pageCoordSpaceName))
                            }
                            .onChange(of: geo.frame(in: .named(pageCoordSpaceName))) { _, newRect in
                                guard !dragCoordinator.isDragging else { return }
                                frameStore.frames[node.id] = newRect
                            }
                    }
                )
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 8)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        frameStore.originY = geo.frame(in: .named("LaunchpadCanvas")).minY
                    }
                    .onChange(of: geo.frame(in: .named("LaunchpadCanvas")).minY) { _, newY in
                        frameStore.originY = newY
                    }
            }
        )
        .coordinateSpace(name: pageCoordSpaceName)
        .onAppear {
            if isCurrentPage && (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction) {
                syncTileFrames()
            }
        }
        .onChange(of: dragCoordinator.isDragging) { _, dragging in
            if dragging && isCurrentPage && (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction) {
                syncTileFrames()
            }
        }
        .onChange(of: dragCoordinator.isFolderHiddenForExtraction) { _, hidden in
            if hidden && isCurrentPage {
                syncTileFrames()
            }
        }
        .onChange(of: manager.activeFolderId) { _, activeFolder in
            if activeFolder == nil && isCurrentPage {
                syncTileFrames()
            }
        }
        .onChange(of: isCurrentPage) { _, active in
            if active && (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction) {
                syncTileFrames()
            }
        }
        .onChange(of: page.nodes) { _, _ in
            if isCurrentPage && (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction) {
                syncTileFrames()
            }
        }
    }

    private func syncTileFrames() {
        let ids = page.nodes.map(\.id)
        let offsetY = frameStore.originY ?? pageTopOffset
        var canvasFrames: [String: CGRect] = [:]
        canvasFrames.reserveCapacity(ids.count)
        for id in ids {
            if let localRect = frameStore.frames[id] {
                canvasFrames[id] = localRect.offsetBy(dx: 0, dy: offsetY)
            }
        }
        dragCoordinator.updateTileFrames(orderedIds: ids, frames: canvasFrames)
    }
}
