import AppKit
import Defaults
import SwiftUI

/// Asynchronously resolved, memory-cached application icon view.
struct LaunchpadAppIconImage: View {
    let bundlePath: String
    let size: CGFloat

    @State private var loadedImage: NSImage?

    var body: some View {
        Group {
            if let image = loadedImage ?? LaunchpadIconCache.shared.cachedIcon(for: bundlePath) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
            } else {
                Image(systemName: "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
                    .padding(size * 0.14)
            }
        }
        .frame(width: size, height: size)
        .task(id: bundlePath) {
            if let cached = LaunchpadIconCache.shared.cachedIcon(for: bundlePath) {
                loadedImage = cached
                return
            }
            let path = bundlePath
            let image = await Task.detached(priority: .userInitiated) {
                LaunchpadIconCache.shared.loadIcon(for: path)
            }.value
            loadedImage = image
        }
    }
}

/// Interactive Launchpad tile representing either an Application or a Folder.
struct LaunchpadTileView: View {
    let node: LaunchpadNode
    let iconSize: CGFloat
    let showLabel: Bool
    let isEditingMode: Bool
    let isMergeTarget: Bool
    let isBeingDragged: Bool
    let isKeyboardHighlighted: Bool
    var sourceFolderId: UUID? = nil
    var allowsEditing: Bool = true
    var showInsertBefore: Bool = false
    var showInsertAfter: Bool = false
    var onOpenApp: (LaunchpadAppItem) -> Void
    var onOpenFolder: (LaunchpadFolderItem) -> Void
    var onRequestTrash: ((LaunchpadAppItem) -> Void)? = nil

    let manager: LaunchpadManager
    let dragCoordinator: LaunchpadDragCoordinator

    @State private var isHovering = false
    @State private var jiggleAngle: Double = 0
    @State private var pressOrigin: CGPoint? = nil
    @State private var holdTask: Task<Void, Never>? = nil
    @State private var didHoldTriggerEdit = false
    @State private var didCancelTapByMove = false
    @State private var isPressingScale = false

    private var labelFontSize: CGFloat {
        max(12.5, min(16.5, (iconSize * 0.145).rounded()))
    }

    private var jiggleSeedOffset: Double {
        var hash = 0
        for byte in node.id.utf8 {
            hash = (hash &* 31) &+ Int(byte)
        }
        return abs(hash) % 2 == 0 ? 1.0 : -1.0
    }

    var body: some View {
        let unifiedTileGesture = DragGesture(minimumDistance: 0, coordinateSpace: .named("LaunchpadCanvas"))
            .onChanged { value in
                if pressOrigin == nil {
                    pressOrigin = value.location
                    didHoldTriggerEdit = false
                    didCancelTapByMove = false
                    withAnimation(.easeOut(duration: 0.1)) {
                        isPressingScale = true
                    }

                    if allowsEditing && !isEditingMode {
                        holdTask?.cancel()
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(360))
                            guard !Task.isCancelled, pressOrigin != nil, !didCancelTapByMove else { return }
                            didHoldTriggerEdit = true
                            isPressingScale = false
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.78)) {
                                manager.isEditingMode = true
                            }
                        }
                    }
                }

                guard let origin = pressOrigin else { return }
                let moveDistance = hypot(value.location.x - origin.x, value.location.y - origin.y)

                if dragCoordinator.isDragging {
                    dragCoordinator.updateDrag(at: value.location, manager: manager)
                    return
                }

                if moveDistance >= 7 {
                    didCancelTapByMove = true
                    holdTask?.cancel()
                    holdTask = nil
                    isPressingScale = false

                    if allowsEditing && (isEditingMode || didHoldTriggerEdit) {
                        dragCoordinator.beginDrag(
                            node: node,
                            fromFolderId: sourceFolderId,
                            at: value.location
                        )
                    }
                }
            }
            .onEnded { _ in
                holdTask?.cancel()
                holdTask = nil
                withAnimation(.easeOut(duration: 0.12)) {
                    isPressingScale = false
                }

                let wasDragging = dragCoordinator.isDragging
                let movedBeforeRelease = didCancelTapByMove
                let enteredEditOnThisPress = didHoldTriggerEdit

                pressOrigin = nil
                didHoldTriggerEdit = false
                didCancelTapByMove = false

                if wasDragging {
                    dragCoordinator.endDrag(manager: manager)
                    return
                }

                if !movedBeforeRelease && !enteredEditOnThisPress {
                    switch node {
                    case .app(let app):
                        if !isEditingMode {
                            onOpenApp(app)
                        }
                    case .folder(let folder):
                        onOpenFolder(folder)
                    }
                }
            }

        ZStack(alignment: .topLeading) {
            VStack(spacing: max(6, iconSize * 0.08)) {
                ZStack {
                    if isMergeTarget {
                        RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: iconSize * 0.24, style: .continuous)
                                    .stroke(Color.effectiveAccent, lineWidth: 2)
                            )
                            .frame(width: iconSize * 1.18, height: iconSize * 1.18)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))
                    }

                    tileArtwork
                        .scaleEffect(isPressingScale ? 0.94 : (isHovering && !isBeingDragged ? 1.05 : 1.0))
                        .scaleEffect(isMergeTarget ? 0.9 : 1.0)
                        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovering)
                        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isMergeTarget)
                        .animation(.easeOut(duration: 0.1), value: isPressingScale)
                }
                .frame(width: iconSize * 1.18, height: iconSize * 1.18)

                if showLabel {
                    Text(node.displayName)
                        .font(.system(size: labelFontSize, weight: .regular))
                        .foregroundStyle(sourceFolderId != nil ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
                        .shadow(color: sourceFolderId != nil ? .clear : Color.black.opacity(0.55), radius: 2.5, y: 1)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Group {
                                if isKeyboardHighlighted {
                                    Capsule()
                                        .fill(Color.effectiveAccent.opacity(0.32))
                                }
                            }
                        )
                }
            }
            .frame(width: max(iconSize * 1.24, 96))
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
            }
            .gesture(unifiedTileGesture)
            .contextMenu {
                contextMenuItems
            }

            if isEditingMode, case .app(let app) = node, manager.canMoveToTrash(app) {
                Button {
                    onRequestTrash?(app)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: max(18, iconSize * 0.21), weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .regularMaterial)
                        .padding(4)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .offset(x: max(4, (max(iconSize * 1.24, 96) - iconSize * 0.86) / 2 - 10), y: -2)
                .accessibilityLabel(loc("Move to Trash"))
            }
        }
        .overlay(alignment: .leading) {
            if showInsertBefore {
                Capsule()
                    .fill(Color.effectiveAccent)
                    .frame(width: 3, height: iconSize * 0.78)
                    .offset(x: -4, y: showLabel ? -10 : 0)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .trailing) {
            if showInsertAfter {
                Capsule()
                    .fill(Color.effectiveAccent)
                    .frame(width: 3, height: iconSize * 0.78)
                    .offset(x: 4, y: showLabel ? -10 : 0)
                    .allowsHitTesting(false)
            }
        }
        .opacity(isBeingDragged ? 0.22 : 1.0)
        .rotationEffect(.degrees(isEditingMode && !isBeingDragged ? jiggleAngle : 0))
        .onAppear {
            updateJiggleAnimation()
        }
        .onChange(of: isEditingMode) { _, _ in
            updateJiggleAnimation()
        }
        .onDisappear {
            holdTask?.cancel()
            holdTask = nil
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var tileArtwork: some View {
        switch node {
        case .app(let app):
            LaunchpadAppIconImage(bundlePath: app.bundlePath, size: iconSize)

        case .folder(let folder):
            LaunchpadFolderThumbnailView(folder: folder, size: iconSize)
        }
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        switch node {
        case .app(let app):
            Button {
                onOpenApp(app)
            } label: {
                Label(loc("Open"), systemImage: "arrow.up.forward.app")
            }

            Button {
                manager.revealInFinder(app)
            } label: {
                Label(loc("Show in Finder"), systemImage: "folder")
            }

            Divider()

            if let sourceFolderId {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        manager.moveAppOutOfFolder(
                            appId: app.id,
                            fromFolder: sourceFolderId,
                            toPage: manager.currentPageIndex,
                            index: nil
                        )
                    }
                } label: {
                    Label(loc("Move Out of Folder"), systemImage: "arrow.up.left.square")
                }
            } else {
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        manager.createFolderFromContextMenu(app: app)
                    }
                } label: {
                    Label(loc("New Folder with App"), systemImage: "folder.badge.plus")
                }
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    manager.isEditingMode.toggle()
                }
            } label: {
                Label(
                    manager.isEditingMode ? loc("Done Editing") : loc("Edit Layout"),
                    systemImage: manager.isEditingMode ? "checkmark.circle" : "pencil"
                )
            }

            if manager.canMoveToTrash(app) {
                Divider()
                Button(role: .destructive) {
                    onRequestTrash?(app)
                } label: {
                    Label(loc("Move to Trash"), systemImage: "trash")
                }
            }

        case .folder(let folder):
            Button {
                onOpenFolder(folder)
            } label: {
                Label(loc("Open Folder"), systemImage: "folder")
            }

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    manager.isEditingMode.toggle()
                }
            } label: {
                Label(
                    manager.isEditingMode ? loc("Done Editing") : loc("Edit Layout"),
                    systemImage: manager.isEditingMode ? "checkmark.circle" : "pencil"
                )
            }
        }
    }

    private func updateJiggleAnimation() {
        if isEditingMode && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            jiggleAngle = -1.5 * jiggleSeedOffset
            withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) {
                jiggleAngle = 1.5 * jiggleSeedOffset
            }
        } else {
            withAnimation(.easeOut(duration: 0.12)) {
                jiggleAngle = 0
            }
        }
    }
}

/// 3x3 mini-grid preview inside a rounded frosted folder icon tile.
struct LaunchpadFolderThumbnailView: View {
    let folder: LaunchpadFolderItem
    let size: CGFloat

    var body: some View {
        let previewApps = Array(folder.items.prefix(9))
        let boxSize = size * 0.86
        let gridPadding = size * 0.095
        let cellSize = size * 0.19
        let spacing = size * 0.05

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: size * 0.215, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.215, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.75)
                )

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 3),
                alignment: .leading,
                spacing: spacing
            ) {
                ForEach(previewApps) { app in
                    LaunchpadAppIconImage(bundlePath: app.bundlePath, size: cellSize)
                }
            }
            .padding(gridPadding)
            .frame(width: boxSize, height: boxSize, alignment: .topLeading)
        }
        .frame(width: boxSize, height: boxSize, alignment: .topLeading)
        .contentShape(RoundedRectangle(cornerRadius: size * 0.215, style: .continuous))
    }
}

