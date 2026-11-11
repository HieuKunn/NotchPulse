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

    private var folderColumns: Int {
        min(5, max(3, Int(ceil(sqrt(Double(max(1, folder.items.count)))))))
    }

    var body: some View {
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
                        .foregroundStyle(.primary)
                        .shadow(color: Color.black.opacity(0.45), radius: 3, y: 1)
                        .multilineTextAlignment(.center)
                        .focused($isTitleFocused)
                        .onSubmit {
                            commitTitle()
                            isTitleFocused = false
                        }
                        .onChange(of: isTitleFocused) { _, focused in
                            if !focused { commitTitle() }
                        }

                    if (isTitleFocused || manager.isEditingMode) && !folderTitle.isEmpty {
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
                .padding(.horizontal, (isTitleFocused || manager.isEditingMode) ? 18 : 24)
                .padding(.vertical, 6)
                .background {
                    if isTitleFocused || manager.isEditingMode {
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
                        columns: Array(repeating: GridItem(.flexible(minimum: iconSize + 24), spacing: 18), count: folderColumns),
                        alignment: .leading,
                        spacing: 22
                    ) {
                        ForEach(Array(folder.items.enumerated()), id: \.element.id) { index, app in
                            let node = LaunchpadNode.app(app)
                            let isDragging = dragCoordinator.isDragging
                            let insertBefore = isDragging && dragCoordinator.reorderTargetIndex == index && dragCoordinator.activeNode?.id != node.id
                            let insertAfter = isDragging && index == folder.items.count - 1 && dragCoordinator.reorderTargetIndex == folder.items.count && dragCoordinator.activeNode?.id != node.id

                            LaunchpadTileView(
                                node: node,
                                iconSize: iconSize,
                                showLabel: showLabels,
                                isEditingMode: manager.isEditingMode,
                                isMergeTarget: false,
                                isBeingDragged: dragCoordinator.activeNode?.id == node.id,
                                isKeyboardHighlighted: false,
                                sourceFolderId: folder.id,
                                showInsertBefore: insertBefore,
                                showInsertAfter: insertAfter,
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
                                            tileFrames[node.id] = geo.frame(in: .named("LaunchpadCanvas"))
                                            syncDragFrames()
                                        }
                                        .onChange(of: geo.frame(in: .named("LaunchpadCanvas"))) { _, newFrame in
                                            tileFrames[node.id] = newFrame
                                            syncDragFrames()
                                        }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 34)
                    .padding(.vertical, 26)
                }
                .scrollIndicators(.never)
                .frame(maxHeight: 490)
                .frame(minWidth: 460, maxWidth: min(780, max(540, CGFloat(folderColumns) * (iconSize + 52) + 68)))
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
        dragCoordinator.updateTileFrames(
            orderedIds: folder.items.map { "app:\($0.id)" },
            frames: tileFrames
        )
    }
}

