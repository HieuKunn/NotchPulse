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
    var onOpenApp: (LaunchpadAppItem) -> Void
    var onOpenFolder: (LaunchpadFolderItem) -> Void
    var onRequestTrash: ((LaunchpadAppItem) -> Void)? = nil

    @ObservedObject var manager: LaunchpadManager
    @ObservedObject var dragCoordinator: LaunchpadDragCoordinator

    @State private var isHovering = false
    @State private var jiggleAngle: Double = 0

    private var labelFontSize: CGFloat {
        max(12.5, min(16.5, (iconSize * 0.145).rounded()))
    }

    var body: some View {
        let tileDragGesture = DragGesture(minimumDistance: 8, coordinateSpace: .named("LaunchpadCanvas"))
            .onChanged { value in
                if !dragCoordinator.isDragging {
                    dragCoordinator.beginDrag(
                        node: node,
                        fromFolderId: sourceFolderId,
                        at: value.location
                    )
                } else {
                    dragCoordinator.updateDrag(at: value.location, manager: manager)
                }
            }
            .onEnded { _ in
                dragCoordinator.endDrag(manager: manager)
            }

        VStack(spacing: max(6, iconSize * 0.08)) {
            ZStack(alignment: .topLeading) {
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
                    .scaleEffect(isHovering && !isBeingDragged ? 1.06 : 1.0)
                    .scaleEffect(isMergeTarget ? 0.9 : 1.0)
                    .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovering)
                    .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isMergeTarget)

                if isEditingMode, case .app(let app) = node, manager.canMoveToTrash(app) {
                    Button {
                        onRequestTrash?(app)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: max(18, iconSize * 0.21), weight: .semibold))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.primary, .regularMaterial)
                    }
                    .buttonStyle(.plain)
                    .offset(x: -6, y: -6)
                    .accessibilityLabel(loc("Move to Trash"))
                }
            }
            .frame(width: iconSize * 1.18, height: iconSize * 1.18)

            if showLabel {
                Text(node.displayName)
                    .font(.system(size: labelFontSize, weight: .regular))
                    .foregroundStyle(.primary)
                    .shadow(color: Color.black.opacity(0.60), radius: 2, y: 1)
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
        .opacity(isBeingDragged ? 0.22 : 1.0)
        .rotationEffect(.degrees(isEditingMode && !isBeingDragged ? jiggleAngle : 0))
        .onAppear {
            updateJiggleAnimation()
        }
        .onChange(of: isEditingMode) { _, _ in
            updateJiggleAnimation()
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onTapGesture {
            guard !dragCoordinator.isDragging else { return }
            switch node {
            case .app(let app):
                if isEditingMode {
                    manager.isEditingMode = false
                } else {
                    onOpenApp(app)
                }
            case .folder(let folder):
                onOpenFolder(folder)
            }
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45)
                .onEnded { _ in
                    guard !dragCoordinator.isDragging else { return }
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        manager.isEditingMode = true
                    }
                }
        )
        .gesture(tileDragGesture, including: isEditingMode ? .all : .none)
        .gesture(
            LongPressGesture(minimumDuration: 0.24)
                .sequenced(before: tileDragGesture),
            including: isEditingMode ? .none : .all
        )
        .contextMenu {
            contextMenuItems
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var tileArtwork: some View {
        switch node {
        case .app(let app):
            LaunchpadAppIconImage(bundlePath: app.bundlePath, size: iconSize)
                .shadow(color: Color.black.opacity(0.24), radius: 4, y: 2)

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
            jiggleAngle = -1.6
            withAnimation(.easeInOut(duration: 0.13).repeatForever(autoreverses: true)) {
                jiggleAngle = 1.6
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
        let cellSize = size * 0.21
        let spacing = size * 0.048

        ZStack {
            RoundedRectangle(cornerRadius: size * 0.215, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.215, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.75)
                )

            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(cellSize), spacing: spacing), count: 3),
                spacing: spacing
            ) {
                ForEach(previewApps) { app in
                    LaunchpadAppIconImage(bundlePath: app.bundlePath, size: cellSize)
                }
            }
            .padding(size * 0.11)
        }
        .frame(width: size * 0.86, height: size * 0.86)
        .shadow(color: Color.black.opacity(0.24), radius: 7, y: 3)
    }
}

