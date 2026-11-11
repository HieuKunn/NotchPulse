import Defaults
import SwiftUI

/// Centered iPadOS / macOS Launchpad folder popup supporting inline title editing,
/// reordering apps inside the folder, and dragging an app outside to extract it.
struct LaunchpadFolderOverlayView: View {
    let folder: LaunchpadFolderItem
    let iconSize: CGFloat
    let showLabels: Bool
    var onOpenApp: (LaunchpadAppItem) -> Void
    var onRequestTrash: (LaunchpadAppItem) -> Void
    var onDismiss: () -> Void

    @ObservedObject var manager: LaunchpadManager
    @ObservedObject var dragCoordinator: LaunchpadDragCoordinator

    @State private var folderTitle: String = ""
    @State private var tileFrames: [String: CGRect] = [:]
    @FocusState private var isTitleFocused: Bool

    private let folderColumns: Int = 3

    private var squareCardSize: CGFloat {
        let cellSlotWidth = max(iconSize * 1.24, 96)
        let idealGrid = CGFloat(folderColumns) * cellSlotWidth + CGFloat(folderColumns - 1) * 18 + 68
        return min(660, max(500, idealGrid))
    }

    private var displayApps: [LaunchpadAppItem] {
        guard dragCoordinator.isDragging,
              !dragCoordinator.isFolderHiddenForExtraction,
              let activeNode = dragCoordinator.activeNode,
              let activeApp = activeNode.asApp,
              dragCoordinator.sourceFolderId == folder.id
        else {
            return folder.items
        }

        let remaining = folder.items.filter { $0.id != activeApp.id }
        if let targetIndex = dragCoordinator.reorderTargetIndex {
            let clamped = max(0, min(targetIndex, remaining.count))
            var result = remaining
            result.insert(activeApp, at: clamped)
            return result
        }
        return folder.items
    }

    var body: some View {
        let isEditingTitle = isTitleFocused || manager.isEditingMode

        ZStack {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    commitTitle()
                    onDismiss()
                }

            VStack(spacing: 22) {
                HStack(spacing: 8) {
                    TextField(loc("Folder Name"), text: $folderTitle)
                        .textFieldStyle(.plain)
                        .focusEffectDisabled()
                        .font(.largeTitle.weight(.light))
                        .foregroundStyle(isEditingTitle ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.white))
                        .shadow(color: isEditingTitle ? .clear : Color.black.opacity(0.45), radius: 3, y: 1)
                        .multilineTextAlignment(.center)
                        .focused($isTitleFocused)
                        .onSubmit {
                            commitTitle()
                            isTitleFocused = false
                        }
                        .onChange(of: isTitleFocused) { _, focused in
                            if !focused { commitTitle() }
                        }

                    if isEditingTitle && !folderTitle.isEmpty {
                        Button {
                            folderTitle = ""
                            isTitleFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, isEditingTitle ? 18 : 24)
                .padding(.vertical, 6)
                .background {
                    if isEditingTitle {
                        Capsule(style: .continuous)
                            .fill(.regularMaterial)
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(Color(nsColor: .separatorColor), lineWidth: 0.75)
                            )
                    }
                }
                .frame(maxWidth: 420)

                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(minimum: iconSize + 16), spacing: 18), count: folderColumns),
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(displayApps, id: \.id) { app in
                            let node = LaunchpadNode.app(app)

                            LaunchpadTileView(
                                node: node,
                                iconSize: iconSize,
                                showLabel: showLabels,
                                isEditingMode: manager.isEditingMode,
                                isMergeTarget: false,
                                isBeingDragged: dragCoordinator.activeNode?.id == node.id,
                                isKeyboardHighlighted: false,
                                sourceFolderId: folder.id,
                                onOpenApp: onOpenApp,
                                onOpenFolder: { _ in },
                                onRequestTrash: onRequestTrash,
                                manager: manager,
                                dragCoordinator: dragCoordinator
                            )
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .onAppear {
                                            guard !dragCoordinator.isDragging else { return }
                                            tileFrames[node.id] = geo.frame(in: .named("LaunchpadCanvas"))
                                            syncDragFrames()
                                        }
                                        .onChange(of: geo.frame(in: .named("LaunchpadCanvas"))) { _, newFrame in
                                            guard !dragCoordinator.isDragging else { return }
                                            tileFrames[node.id] = newFrame
                                            syncDragFrames()
                                        }
                                }
                            )
                        }
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.82), value: displayApps.map(\.id))
                    .padding(.horizontal, 34)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.never)
                .frame(width: squareCardSize, height: squareCardSize)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 34, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 0.75)
                )
                .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
                .onTapGesture {
                    if isTitleFocused {
                        commitTitle()
                        isTitleFocused = false
                    }
                }
                .shadow(color: Color.black.opacity(0.32), radius: 32, y: 14)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .onAppear {
                                dragCoordinator.updateFolderCardFrame(geo.frame(in: .named("LaunchpadCanvas")))
                            }
                            .onChange(of: geo.frame(in: .named("LaunchpadCanvas"))) { _, rect in
                                dragCoordinator.updateFolderCardFrame(rect)
                            }
                    }
                )
            }
            .padding(40)
            .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
        .onAppear {
            folderTitle = folder.name
            syncDragFrames()
        }
        .onChange(of: folder.name) { _, newName in
            if !isTitleFocused {
                folderTitle = newName
            }
        }
        .onChange(of: folder.items) { _, _ in
            syncDragFrames()
        }
        .onDisappear {
            commitTitle()
        }
    }

    private func commitTitle() {
        manager.renameFolder(folderId: folder.id, name: folderTitle)
    }

    private func syncDragFrames() {
        guard !dragCoordinator.isFolderHiddenForExtraction else { return }
        dragCoordinator.updateTileFrames(
            orderedIds: folder.items.map { "app:\($0.id)" },
            frames: tileFrames
        )
    }
}

