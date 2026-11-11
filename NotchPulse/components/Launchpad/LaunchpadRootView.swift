import AppKit
import Defaults
import SwiftUI

/// Native NSVisualEffectView wrapper providing macOS fullscreen frosted wallpaper blur.
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

/// Fullscreen paged Launchpad Home view styled cleanly according to Apple HIG.
struct LaunchpadRootView: View {
    @ObservedObject var manager: LaunchpadManager
    @ObservedObject var windowController: LaunchpadWindowController
    @StateObject private var dragCoordinator = LaunchpadDragCoordinator()

    @Default(.launchpadColumns) private var columns
    @Default(.launchpadRows) private var rows
    @Default(.launchpadIconSize) private var iconSize
    @Default(.launchpadShowLabels) private var showLabels
    @Default(.launchpadBackgroundStyle) private var backgroundStyle

    @FocusState private var isSearchFocused: Bool
    @State private var appPendingTrash: LaunchpadAppItem? = nil

    var body: some View {
        GeometryReader { canvasGeo in
            ZStack {
                backdropLayer

                VStack(spacing: 0) {
                    topSearchAndControlsBar
                        .padding(.top, 44)
                        .padding(.bottom, 18)

                    if !manager.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        searchResultsView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if manager.isScanning && manager.pages.isEmpty {
                        ProgressView()
                            .controlSize(.large)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        pagedCarouselView(canvasSize: canvasGeo.size)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if manager.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && manager.pages.count > 1 {
                        pageDotsIndicator
                            .padding(.top, 10)
                            .padding(.bottom, 34)
                    } else {
                        Spacer(minLength: 34)
                            .frame(height: 34)
                    }
                }

                if let activeFolder = manager.activeFolder {
                    LaunchpadFolderOverlayView(
                        folder: activeFolder,
                        iconSize: CGFloat(iconSize),
                        showLabels: showLabels,
                        onOpenApp: { manager.launchApp($0) },
                        onRequestTrash: { appPendingTrash = $0 },
                        onDismiss: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
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
                    floatingDragPreview(for: draggedNode)
                        .position(dragCoordinator.dragLocation)
                        .allowsHitTesting(false)
                        .zIndex(40)
                }
            }
            .coordinateSpace(name: "LaunchpadCanvas")
            .onAppear {
                dragCoordinator.updateCanvasSize(canvasGeo.size)
                if windowController.isPresented {
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                }
            }
            .onChange(of: canvasGeo.size) { _, newSize in
                dragCoordinator.updateCanvasSize(newSize)
            }
            .onChange(of: windowController.isPresented) { _, presented in
                if presented {
                    DispatchQueue.main.async {
                        isSearchFocused = true
                    }
                } else {
                    isSearchFocused = false
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

    // MARK: - Backdrop

    @ViewBuilder
    private var backdropLayer: some View {
        ZStack {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                Color(nsColor: .windowBackgroundColor)
            } else {
                LaunchpadVisualEffectBackdrop(style: backgroundStyle)
                if backgroundStyle == .dimmed {
                    Color.black.opacity(0.28)
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {
            if manager.isEditingMode {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    manager.isEditingMode = false
                }
            } else if manager.activeFolderId != nil {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    manager.activeFolderId = nil
                }
            } else {
                windowController.dismiss(restorePreviousApp: true)
            }
        }
    }

    // MARK: - Top Search & Toolbar

    @ViewBuilder
    private var topSearchAndControlsBar: some View {
        ZStack {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)

                TextField(loc("Search applications..."), text: $manager.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .focused($isSearchFocused)
                    .onSubmit {
                        if let first = manager.searchResults.first {
                            manager.launchApp(first)
                        }
                    }

                if !manager.searchQuery.isEmpty {
                    Button {
                        manager.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(loc("Clear"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(width: 280)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.6)
            )

            HStack(spacing: 8) {
                Spacer()

                if manager.isEditingMode {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            manager.isEditingMode = false
                        }
                    } label: {
                        Label(loc("Done"), systemImage: "checkmark")
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.effectiveAccent)
                    .controlSize(.small)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            manager.isEditingMode = true
                        }
                    } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.medium))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .background(.regularMaterial, in: Circle())
                    .help(loc("Edit Layout"))
                }

                Button {
                    manager.refreshApps(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .help(loc("Refresh Applications"))

                Button {
                    windowController.dismiss(restorePreviousApp: false) {
                        SettingsWindowController.shared.showWindow()
                        NotificationCenter.default.post(name: Notification.Name("OpenLaunchpadSettings"), object: nil)
                    }
                } label: {
                    Image(systemName: "gearshape")
                        .font(.body.weight(.medium))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .help(loc("Settings"))
            }
            .padding(.trailing, 32)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Horizontal Paging Carousel

    @ViewBuilder
    private func pagedCarouselView(canvasSize: CGSize) -> some View {
        let pageWidth = max(1, canvasSize.width)
        let horizontalInset = max(60, min(140, canvasSize.width * 0.09))
        let safeRows = max(3, min(8, rows))
        let safeCols = max(4, min(10, columns))
        let availableGridHeight = max(320, canvasSize.height - 175)
        let perRowBudget = availableGridHeight / CGFloat(safeRows)
        let labelOverhead: CGFloat = showLabels ? 44 : 22
        let fittedIconSize = min(CGFloat(iconSize), max(46, (perRowBudget - labelOverhead) / 1.18))
        let fittedRowHeight = fittedIconSize * 1.18 + (showLabels ? 36 : 16)
        let verticalSpacing = max(8, min(28, perRowBudget - fittedRowHeight))
        let gridColumns = Array(
            repeating: GridItem(.flexible(minimum: fittedIconSize + 24), spacing: 18),
            count: safeCols
        )

        HStack(spacing: 0) {
            ForEach(Array(manager.pages.enumerated()), id: \.element.id) { pageIndex, page in
                LaunchpadPageGridView(
                    page: page,
                    isCurrentPage: pageIndex == manager.currentPageIndex,
                    gridColumns: gridColumns,
                    verticalSpacing: verticalSpacing,
                    iconSize: fittedIconSize,
                    showLabels: showLabels,
                    horizontalInset: horizontalInset,
                    manager: manager,
                    dragCoordinator: dragCoordinator,
                    onOpenApp: { manager.launchApp($0) },
                    onOpenFolder: { folder in
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.85)) {
                            manager.activeFolderId = folder.id
                        }
                    },
                    onRequestTrash: { appPendingTrash = $0 }
                )
                .frame(width: pageWidth)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .frame(width: pageWidth * CGFloat(max(1, manager.pages.count)), alignment: .leading)
        .offset(x: -CGFloat(manager.currentPageIndex) * pageWidth + windowController.liveSwipeOffset)
        .frame(width: pageWidth, alignment: .leading)
        .clipped()
    }

    // MARK: - Search Results Grid

    @ViewBuilder
    private var searchResultsView: some View {
        let results = manager.searchResults
        if results.isEmpty {
            ContentUnavailableView {
                Label(loc("No applications found"), systemImage: "magnifyingglass")
            } description: {
                Text(loc("Try searching with a different application name."))
            }
        } else {
            let searchColumns = Array(
                repeating: GridItem(.flexible(minimum: CGFloat(iconSize) + 28), spacing: 20),
                count: max(4, min(10, columns))
            )
            ScrollView {
                LazyVGrid(columns: searchColumns, spacing: 26) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, app in
                        LaunchpadTileView(
                            node: .app(app),
                            iconSize: CGFloat(iconSize),
                            showLabel: showLabels,
                            isEditingMode: false,
                            isMergeTarget: false,
                            isBeingDragged: false,
                            isKeyboardHighlighted: index == 0,
                            onOpenApp: { manager.launchApp($0) },
                            onOpenFolder: { _ in },
                            onRequestTrash: { appPendingTrash = $0 },
                            manager: manager,
                            dragCoordinator: dragCoordinator
                        )
                    }
                }
                .padding(.horizontal, 110)
                .padding(.vertical, 24)
            }
            .scrollIndicators(.never)
        }
    }

    // MARK: - Bottom Page Dots

    @ViewBuilder
    private var pageDotsIndicator: some View {
        HStack(spacing: 10) {
            ForEach(0..<manager.pages.count, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        manager.currentPageIndex = index
                    }
                } label: {
                    Circle()
                        .fill(index == manager.currentPageIndex ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: index == manager.currentPageIndex ? 9 : 7, height: index == manager.currentPageIndex ? 9 : 7)
                        .padding(3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
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

    @ViewBuilder
    private func floatingDragPreview(for node: LaunchpadNode) -> some View {
        VStack(spacing: 6) {
            switch node {
            case .app(let app):
                LaunchpadAppIconImage(bundlePath: app.bundlePath, size: CGFloat(iconSize) * 1.12)
                    .shadow(color: Color.black.opacity(0.32), radius: 14, y: 8)
            case .folder(let folder):
                LaunchpadFolderThumbnailView(folder: folder, size: CGFloat(iconSize) * 1.12)
                    .shadow(color: Color.black.opacity(0.32), radius: 14, y: 8)
            }
            if showLabels {
                Text(node.displayName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }
}

/// Renders one horizontal Launchpad page and tracks tile geometry for drag/drop hit testing.
private struct LaunchpadPageGridView: View {
    let page: LaunchpadPage
    let isCurrentPage: Bool
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

    @State private var tileFrames: [String: CGRect] = [:]

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: verticalSpacing) {
            ForEach(page.nodes) { node in
                LaunchpadTileView(
                    node: node,
                    iconSize: iconSize,
                    showLabel: showLabels,
                    isEditingMode: manager.isEditingMode,
                    isMergeTarget: dragCoordinator.mergeTargetNodeId == node.id,
                    isBeingDragged: dragCoordinator.activeNode?.id == node.id,
                    isKeyboardHighlighted: false,
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
                                tileFrames[node.id] = geo.frame(in: .named("LaunchpadCanvas"))
                                if isCurrentPage && (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction) {
                                    syncTileFrames()
                                }
                            }
                            .onChange(of: geo.frame(in: .named("LaunchpadCanvas"))) { _, newRect in
                                tileFrames[node.id] = newRect
                                if isCurrentPage && (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction) {
                                    syncTileFrames()
                                }
                            }
                    }
                )
            }
        }
        .padding(.horizontal, horizontalInset)
        .padding(.top, 12)
        .onChange(of: isCurrentPage) { _, active in
            if active && (manager.activeFolderId == nil || dragCoordinator.isFolderHiddenForExtraction) {
                syncTileFrames()
            }
        }
        .onChange(of: manager.activeFolderId) { _, folderId in
            if isCurrentPage && (folderId == nil || dragCoordinator.isFolderHiddenForExtraction) {
                syncTileFrames()
            }
        }
        .onChange(of: dragCoordinator.isFolderHiddenForExtraction) { _, hidden in
            if isCurrentPage && hidden {
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
        let filtered = tileFrames.filter { ids.contains($0.key) }
        dragCoordinator.updateTileFrames(orderedIds: ids, frames: filtered)
    }
}
