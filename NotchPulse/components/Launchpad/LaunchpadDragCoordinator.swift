import AppKit
import Combine
import Foundation
import SwiftUI

/// Isolated observable pointer position so 120Hz drag motion only invalidates the single floating drag preview.
@MainActor
final class LaunchpadDragCursor: ObservableObject {
    @Published var location: CGPoint = .zero
}

/// Coordinates smooth, 120Hz pointer drag-and-drop across Launchpad pages,
/// edge page-flipping, folder creation/addition, and extracting apps from folders.
@MainActor
final class LaunchpadDragCoordinator: ObservableObject {
    let cursor = LaunchpadDragCursor()

    @Published private(set) var activeNode: LaunchpadNode? = nil
    @Published private(set) var sourceFolderId: UUID? = nil
    @Published private(set) var mergeTargetNodeId: String? = nil
    @Published private(set) var reorderTargetIndex: Int? = nil
    @Published private(set) var edgeTurnDirection: Int? = nil
    @Published private(set) var isFolderHiddenForExtraction: Bool = false

    private var tileFrames: [String: CGRect] = [:]
    private var orderedTileIds: [String] = []
    private var folderCardRect: CGRect = .zero
    private var canvasSize: CGSize = .zero

    private var folderHoverTask: Task<Void, Never>?
    private var pendingMergeCandidateId: String? = nil
    private var edgeTurnTask: Task<Void, Never>?
    private var folderExitTask: Task<Void, Never>?

    var isDragging: Bool {
        activeNode != nil
    }

    func updateCanvasSize(_ size: CGSize) {
        canvasSize = size
    }

    func updateFolderCardFrame(_ rect: CGRect) {
        folderCardRect = rect
    }

    func updateTileFrames(orderedIds: [String], frames: [String: CGRect]) {
        orderedTileIds = orderedIds
        tileFrames = frames
    }

    func beginDrag(node: LaunchpadNode, fromFolderId: UUID? = nil, at location: CGPoint) {
        guard activeNode == nil else { return }
        cursor.location = location
        activeNode = node
        sourceFolderId = fromFolderId
        mergeTargetNodeId = nil
        reorderTargetIndex = nil
        edgeTurnDirection = nil
    }

    func updateDrag(at location: CGPoint, manager: LaunchpadManager) {
        guard let activeNode else { return }
        cursor.location = location

        // If dragging an app inside an open folder, detect dragging outside the folder card to close the folder and keep dragging on the grid
        if let sourceFolderId, manager.activeFolderId == sourceFolderId, !isFolderHiddenForExtraction {
            let exitRect = folderCardRect.insetBy(dx: -8, dy: -8)
            let immediateExitRect = folderCardRect.insetBy(dx: -36, dy: -36)
            if !folderCardRect.isEmpty && !immediateExitRect.contains(location) {
                folderExitTask?.cancel()
                folderExitTask = nil
                withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                    self.isFolderHiddenForExtraction = true
                }
            } else if !folderCardRect.isEmpty && !exitRect.contains(location) {
                if folderExitTask == nil {
                    folderExitTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(95))
                        guard let self, !Task.isCancelled, self.activeNode != nil else { return }
                        withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                            self.isFolderHiddenForExtraction = true
                        }
                    }
                }
                cancelMergeAndEdgeTimers()
                return
            } else {
                folderExitTask?.cancel()
                folderExitTask = nil
            }
        }

        let isOverlayFolderActive = manager.activeFolderId != nil && !isFolderHiddenForExtraction

        // Hit-test target tiles FIRST so trying to merge near left/right edge columns never flips pages
        var foundCenterTarget: String? = nil
        if !isOverlayFolderActive && !activeNode.isFolder {
            for id in orderedTileIds where id != activeNode.id {
                guard let rect = tileFrames[id] else { continue }
                let centerZone = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
                if centerZone.contains(location) {
                    foundCenterTarget = id
                    break
                }
            }
        }

        // Check left/right edge auto-page flip only when NOT targeting any app/folder and pushed flush against bezel
        if foundCenterTarget == nil && !isOverlayFolderActive && manager.searchQuery.isEmpty && canvasSize.width > 0 {
            let edgeMargin: CGFloat = 14
            let desiredDirection: Int?
            if location.x <= edgeMargin && manager.currentPageIndex > 0 {
                desiredDirection = -1
            } else if location.x >= canvasSize.width - edgeMargin {
                // Allow creating 1 extra page when dragging past last page (unless current page only had this dragged node)
                let currentCount = manager.pages[safe: manager.currentPageIndex]?.nodes.count ?? 0
                if manager.currentPageIndex < manager.pages.count - 1 || currentCount > 1 {
                    desiredDirection = 1
                } else {
                    desiredDirection = nil
                }
            } else {
                desiredDirection = nil
            }

            if desiredDirection != edgeTurnDirection {
                edgeTurnDirection = desiredDirection
                edgeTurnTask?.cancel()
                edgeTurnTask = nil
                if let dir = desiredDirection {
                    edgeTurnTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(850))
                        guard let self, !Task.isCancelled, self.activeNode != nil else { return }
                        let targetPage = manager.currentPageIndex + dir
                        if targetPage >= manager.pages.count {
                            _ = manager.ensurePage(at: targetPage)
                        }
                        if targetPage >= 0 && targetPage < manager.pages.count {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                manager.currentPageIndex = targetPage
                            }
                            self.mergeTargetNodeId = nil
                            self.reorderTargetIndex = nil
                        }
                        self.edgeTurnDirection = nil
                    }
                }
            }
        } else {
            cancelEdgeTimer()
        }

        if let candidate = foundCenterTarget {
            if pendingMergeCandidateId != candidate {
                pendingMergeCandidateId = candidate
                mergeTargetNodeId = nil
                folderHoverTask?.cancel()
                folderHoverTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(110))
                    guard let self, !Task.isCancelled, self.pendingMergeCandidateId == candidate else { return }
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                        self.mergeTargetNodeId = candidate
                        self.reorderTargetIndex = nil
                    }
                }
            }
        } else {
            pendingMergeCandidateId = nil
            folderHoverTask?.cancel()
            folderHoverTask = nil
            if mergeTargetNodeId != nil {
                withAnimation(.easeOut(duration: 0.15)) {
                    mergeTargetNodeId = nil
                }
            }
            let newIndex = computeNearestInsertIndex(at: location, excluding: activeNode.id)
            if reorderTargetIndex != newIndex {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    reorderTargetIndex = newIndex
                }
            }
        }
    }

    func endDrag(manager: LaunchpadManager) {
        guard let draggedNode = activeNode else {
            resetState()
            return
        }

        defer { resetState() }

        let currentPage = max(0, min(manager.currentPageIndex, max(0, manager.pages.count - 1)))

        // Case 1: Dragging an app that started inside a folder
        if let originFolderId = sourceFolderId {
            if !isFolderHiddenForExtraction, manager.activeFolderId == originFolderId, let app = draggedNode.asApp {
                if let targetIdx = reorderTargetIndex {
                    manager.reorderApp(app.id, insideFolder: originFolderId, toIndex: targetIdx)
                }
            } else if let app = draggedNode.asApp {
                if let mergeId = mergeTargetNodeId, !mergeId.hasPrefix("folder:") {
                    manager.moveAppOutOfFolder(appId: app.id, fromFolder: originFolderId, toPage: currentPage, index: nil)
                    manager.dropNode(draggedNode.id, onto: mergeId)
                } else if let mergeId = mergeTargetNodeId, mergeId.hasPrefix("folder:"),
                          let targetFolderUUID = UUID(uuidString: String(mergeId.dropFirst("folder:".count))) {
                    manager.moveAppOutOfFolder(appId: app.id, fromFolder: originFolderId, toPage: currentPage, index: nil)
                    manager.addApp(app.id, toFolder: targetFolderUUID)
                } else {
                    manager.moveAppOutOfFolder(appId: app.id, fromFolder: originFolderId, toPage: currentPage, index: reorderTargetIndex)
                }
                manager.activeFolderId = nil
            }
            return
        }

        // Case 2: Main grid drop onto another node -> merge into folder / add to folder
        if let mergeId = mergeTargetNodeId {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.84)) {
                manager.dropNode(draggedNode.id, onto: mergeId)
            }
            return
        }

        // Case 3: Reorder or cross-page move
        if let insertIdx = reorderTargetIndex {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                manager.moveNode(nodeId: draggedNode.id, toPage: currentPage, index: insertIdx)
            }
        } else if let existingPageIdx = manager.pages.firstIndex(where: { $0.nodes.contains(where: { $0.id == draggedNode.id }) }),
                  existingPageIdx != currentPage {
            withAnimation(.spring(response: 0.30, dampingFraction: 0.86)) {
                manager.moveNode(nodeId: draggedNode.id, toPage: currentPage, index: nil)
            }
        } else {
            manager.pruneEmptyPages()
        }
    }

    private func computeNearestInsertIndex(at point: CGPoint, excluding excludedId: String) -> Int? {
        guard !orderedTileIds.isEmpty else { return 0 }

        // Filter out the excluded id so candidate slots map directly to positions in the remaining list
        let validIds = orderedTileIds.filter { $0 != excludedId }
        guard !validIds.isEmpty else { return 0 }

        var bestIdx: Int?
        var bestDist: CGFloat = .greatestFiniteMagnitude

        for (index, id) in validIds.enumerated() {
            guard let rect = tileFrames[id] else { continue }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let dist = hypot(point.x - center.x, point.y - center.y)
            if dist < bestDist {
                bestDist = dist
                bestIdx = point.x > center.x ? index + 1 : index
            }
        }

        // Allow dropping into trailing space after the last tile on the page without hijacking last-row labels
        if let lastId = validIds.last,
           let lastRect = tileFrames[lastId],
           point.y > lastRect.maxY + 8 || (point.x > lastRect.maxX + 4 && point.y > lastRect.minY) {
            return validIds.count
        }
        return bestIdx.map { max(0, min($0, validIds.count)) }
    }

    private func cancelEdgeTimer() {
        edgeTurnDirection = nil
        edgeTurnTask?.cancel()
        edgeTurnTask = nil
    }

    private func cancelMergeAndEdgeTimers() {
        pendingMergeCandidateId = nil
        folderHoverTask?.cancel()
        folderHoverTask = nil
        mergeTargetNodeId = nil
        cancelEdgeTimer()
    }

    private func resetState() {
        folderExitTask?.cancel()
        folderExitTask = nil
        cancelMergeAndEdgeTimers()
        activeNode = nil
        sourceFolderId = nil
        reorderTargetIndex = nil
        isFolderHiddenForExtraction = false
        cursor.location = .zero
    }
}

extension LaunchpadManager {
    func addApp(_ appId: String, toFolder folderId: UUID) {
        dropNode("app:\(appId)", onto: "folder:\(folderId.uuidString)")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
