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
        view.appearance = nil
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

/// Subclassed NSTextField (instead of NSSearchField) so the magnifying glass icon and text input
/// live in isolated layout frames, preventing icon/text overlap while refusing auto-focus on panel open.
private final class LaunchpadSearchTextField: NSTextField {
    var allowFirstResponder: Bool = false

    override var canBecomeKeyView: Bool {
        allowFirstResponder
    }

    override func becomeFirstResponder() -> Bool {
        guard allowFirstResponder else { return false }
        return super.becomeFirstResponder()
    }

    override func mouseDown(with event: NSEvent) {
        allowFirstResponder = true
        super.mouseDown(with: event)
    }
}

/// Container that forwards clicks anywhere on the pill (including over the icon/padding) to the text field.
private final class LaunchpadSearchContainerView: NSView {
    weak var textField: LaunchpadSearchTextField?

    override func mouseDown(with event: NSEvent) {
        if let field = textField {
            field.allowFirstResponder = true
            if window?.firstResponder != field.currentEditor() {
                window?.makeFirstResponder(field)
                if let editor = field.currentEditor() as? NSTextView {
                    editor.setSelectedRange(NSRange(location: field.stringValue.count, length: 0))
                }
            }
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// Settings-matched capsule Search field embedded inside native Liquid Glass (NSGlassEffectView on macOS 26+).
private struct LaunchpadNativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onSubmit: () -> Void
    var focusToken: Int

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LaunchpadNativeSearchField
        weak var textField: LaunchpadSearchTextField?
        weak var clearButton: NSButton?
        var lastFocusToken: Int = 0
        var lastPlaceholder: String = ""

        init(_ parent: LaunchpadNativeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
            clearButton?.isHidden = field.stringValue.isEmpty
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            (obj.object as? LaunchpadSearchTextField)?.allowFirstResponder = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if !parent.text.isEmpty {
                    parent.text = ""
                    textField?.stringValue = ""
                    clearButton?.isHidden = true
                    textField?.allowFirstResponder = false
                    textField?.window?.makeFirstResponder(nil)
                    return true
                }
            }
            return false
        }

        @objc func clearTapped() {
            parent.text = ""
            textField?.stringValue = ""
            clearButton?.isHidden = true
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSView {
        let iconConfig = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(iconConfig)
        iconView.contentTintColor = .secondaryLabelColor
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        iconView.setContentCompressionResistancePriority(.required, for: .horizontal)

        let field = LaunchpadSearchTextField()
        field.translatesAutoresizingMaskIntoConstraints = false
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.lineBreakMode = .byClipping
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.font = NSFont.systemFont(ofSize: 13.5, weight: .regular)
        field.textColor = .labelColor
        field.delegate = context.coordinator
        context.coordinator.textField = field
        context.coordinator.lastPlaceholder = placeholder
        applyPlaceholder(to: field)

        let clearButton = NSButton()
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.isBordered = false
        clearButton.bezelStyle = .regularSquare
        clearButton.title = ""
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 13, weight: .regular))
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = context.coordinator
        clearButton.action = #selector(Coordinator.clearTapped)
        clearButton.isHidden = text.isEmpty
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        context.coordinator.clearButton = clearButton

        let innerContainer = LaunchpadSearchContainerView()
        innerContainer.translatesAutoresizingMaskIntoConstraints = false
        innerContainer.textField = field
        innerContainer.addSubview(iconView)
        innerContainer.addSubview(field)
        innerContainer.addSubview(clearButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: innerContainer.leadingAnchor, constant: 12),
            iconView.centerYAnchor.constraint(equalTo: innerContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            field.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 7),
            field.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: innerContainer.centerYAnchor),

            clearButton.trailingAnchor.constraint(equalTo: innerContainer.trailingAnchor, constant: -10),
            clearButton.centerYAnchor.constraint(equalTo: innerContainer.centerYAnchor),
            clearButton.widthAnchor.constraint(equalToConstant: 16),
            clearButton.heightAnchor.constraint(equalToConstant: 16)
        ])

        if #available(macOS 26.0, *),
           let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassClass.init()
            glass.setValue(0, forKey: "style")
            glass.setValue(CGFloat(16), forKey: "cornerRadius")
            if glass.responds(to: NSSelectorFromString("setEffectIsInteractive:")) {
                glass.setValue(false, forKey: "effectIsInteractive")
            }
            glass.setValue(innerContainer, forKey: "contentView")
            return glass
        } else {
            let effect = NSVisualEffectView()
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
        guard let field = context.coordinator.textField else { return }

        if field.stringValue != text {
            field.stringValue = text
        }
        context.coordinator.clearButton?.isHidden = text.isEmpty

        if context.coordinator.lastPlaceholder != placeholder {
            context.coordinator.lastPlaceholder = placeholder
            applyPlaceholder(to: field)
        }

        if context.coordinator.lastFocusToken != focusToken && focusToken > 0 {
            context.coordinator.lastFocusToken = focusToken
            DispatchQueue.main.async {
                field.allowFirstResponder = true
                if let window = field.window, window.firstResponder != field.currentEditor() {
                    window.makeFirstResponder(field)
                    if let editor = field.currentEditor() as? NSTextView {
                        editor.setSelectedRange(NSRange(location: field.stringValue.count, length: 0))
                    }
                }
            }
        }
    }

    private func applyPlaceholder(to field: NSTextField) {
        field.placeholderAttributedString = NSAttributedString(
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
    @Environment(\.colorScheme) private var colorScheme

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

                let isFolderVisuallyOpen = manager.activeFolderId != nil && !dragCoordinator.isFolderHiddenForExtraction

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
                .scaleEffect(isFolderVisuallyOpen ? 0.94 : 1.0)
                .blur(radius: isFolderVisuallyOpen ? 10 : 0)
                .opacity(isFolderVisuallyOpen ? 0.42 : 1.0)

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
            .coordinateSpace(name: "LaunchpadCanvas")
            .onAppear {
                dragCoordinator.updateCanvasSize(size)
                loadWallpaperIfNeeded()
                triggerOpenZoomIfNeeded()
            }
            .onChange(of: size) { _, newSize in
                dragCoordinator.updateCanvasSize(newSize)
            }
            .onChange(of: dragCoordinator.isDragging) { _, dragging in
                windowController.isLaunchpadDragActive = dragging
                if dragging {
                    isMouseSwipingPage = false
                    windowController.swipeState.offset = 0
                }
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
                let overlayOpacity: Double = colorScheme == .dark
                    ? (backgroundStyle == .dimmed ? 0.36 : 0.14)
                    : (backgroundStyle == .dimmed ? 0.20 : 0.04)
                Color.black.opacity(overlayOpacity)
            } else {
                LaunchpadVisualEffectBackdrop(style: backgroundStyle)
                if backgroundStyle == .dimmed {
                    Color.black.opacity(colorScheme == .dark ? 0.36 : 0.18)
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
        if windowController.resignSearchFocusIfActive() {
            return
        }
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
            // Keep background-dismiss and empty-space swipe strictly behind interactive app/folder tiles
            // so dragging or grouping icons NEVER triggers an accidental tab switch on release.
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    handleBackgroundTap()
                }
                .gesture(
                    DragGesture(minimumDistance: 14, coordinateSpace: .local)
                        .onChanged { value in
                            guard !dragCoordinator.isDragging,
                                  !windowController.isLaunchpadDragActive,
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
                            guard isMouseSwipingPage,
                                  !dragCoordinator.isDragging,
                                  !windowController.isLaunchpadDragActive else {
                                isMouseSwipingPage = false
                                windowController.swipeState.offset = 0
                                return
                            }
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
                    .foregroundStyle(Color.white)
                    .shadow(color: Color.black.opacity(0.55), radius: 2.5, y: 1)
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

    private var isLayoutFrozen: Bool {
        dragCoordinator.isDragging || (manager.activeFolderId != nil && !dragCoordinator.isFolderHiddenForExtraction)
    }

    private var displayNodes: [LaunchpadNode] {
        guard dragCoordinator.isDragging,
              isCurrentPage,
              dragCoordinator.mergeTargetNodeId == nil,
              (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction),
              let activeNode = dragCoordinator.activeNode
        else {
            return page.nodes
        }

        let remaining = page.nodes.filter { $0.id != activeNode.id }
        if let targetIndex = dragCoordinator.reorderTargetIndex {
            let clamped = max(0, min(targetIndex, remaining.count))
            var result = remaining
            result.insert(activeNode, at: clamped)
            return result
        }
        return page.nodes
    }

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: verticalSpacing) {
            ForEach(displayNodes, id: \.id) { node in
                let excludedFolderAppId: String? = {
                    if case .folder(let folder) = node,
                       dragCoordinator.sourceFolderId == folder.id {
                        return dragCoordinator.activeNode?.asApp?.id
                    }
                    return nil
                }()

                LaunchpadTileView(
                    node: node,
                    iconSize: iconSize,
                    showLabel: showLabels,
                    isEditingMode: manager.isEditingMode && isCurrentPage,
                    isMergeTarget: dragCoordinator.mergeTargetNodeId == node.id,
                    isBeingDragged: dragCoordinator.activeNode?.id == node.id,
                    isKeyboardHighlighted: false,
                    excludedFolderAppId: excludedFolderAppId,
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
                                guard !isLayoutFrozen else { return }
                                frameStore.frames[node.id] = geo.frame(in: .named(pageCoordSpaceName))
                            }
                            .onChange(of: geo.frame(in: .named(pageCoordSpaceName))) { _, newRect in
                                guard !isLayoutFrozen else { return }
                                frameStore.frames[node.id] = newRect
                            }
                    }
                )
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: displayNodes.map(\.id))
        .padding(.horizontal, horizontalInset)
        .padding(.top, 8)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        guard !isLayoutFrozen else { return }
                        frameStore.originY = geo.frame(in: .named("LaunchpadCanvas")).minY
                    }
                    .onChange(of: geo.frame(in: .named("LaunchpadCanvas")).minY) { _, newY in
                        guard !isLayoutFrozen else { return }
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
                dragCoordinator.updateDrag(at: dragCoordinator.cursor.location, manager: manager)
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
