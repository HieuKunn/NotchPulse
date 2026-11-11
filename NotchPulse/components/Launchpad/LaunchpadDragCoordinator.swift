import AppKit
import Combine
import Foundation
import SwiftUI

/// Coordinates smooth, 120Hz pointer drag-and-drop across Launchpad pages,
/// edge page-flipping, folder creation/addition, and extracting apps from folders.
@MainActor
final class LaunchpadDragCoordinator: ObservableObject {
    @Published private(set) var activeNode: LaunchpadNode? = nil
    @Published private(set) var sourceFolderId: UUID? = nil
    @Published var dragLocation: CGPoint = .zero
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
        activeNode = node
        sourceFolderId = fromFolderId
        dragLocation = location
        mergeTargetNodeId = nil
        reorderTargetIndex = nil
        edgeTurnDirection = nil
    }

    func updateDrag(at location: CGPoint, manager: LaunchpadManager) {
        guard let activeNode else { return }
        dragLocation = location

        // If dragging an app inside an open folder, check if dragged outside the folder card to extract it
        if let sourceFolderId, manager.activeFolderId == sourceFolderId, !isFolderHiddenForExtraction {
            let expandedRect = folderCardRect.insetBy(dx: -16, dy: -16)
            if !folderCardRect.isEmpty && !expandedRect.contains(location) {
                if folderExitTask == nil {
                    folderExitTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(220))
                        guard let self, !Task.isCancelled, self.activeNode != nil else { return }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.86)) {
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

        // Check left/right edge auto-page flip when on main grid
        if !isOverlayFolderActive && manager.searchQuery.isEmpty && canvasSize.width > 0 {
            let edgeMargin: CGFloat = 72
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
                        try? await Task.sleep(for: .milliseconds(450))
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

        // Hit-test target tiles
        var foundCenterTarget: String? = nil
        if !isOverlayFolderActive && !activeNode.isFolder {
            for id in orderedTileIds where id != activeNode.id {
                guard let rect = tileFrames[id] else { continue }
                let centerZone = rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.22)
                if centerZone.contains(location) {
                    foundCenterTarget = id
                    break
                }
            }
        }

        if let candidate = foundCenterTarget {
            if pendingMergeCandidateId != candidate {
                pendingMergeCandidateId = candidate
                mergeTargetNodeId = nil
                folderHoverTask?.cancel()
                folderHoverTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(160))
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
            reorderTargetIndex = computeNearestInsertIndex(at: location, excluding: activeNode.id)
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
        var bestIdx: Int?
        var bestDist: CGFloat = .greatestFiniteMagnitude

        for (index, id) in orderedTileIds.enumerated() {
            guard let rect = tileFrames[id] else { continue }
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let dist = hypot(point.x - center.x, point.y - center.y)
            if dist < bestDist {
                bestDist = dist
                bestIdx = point.x > center.x && id != excludedId ? index + 1 : index
            }
        }

        // Allow dropping into trailing space after the last tile on the page
        if let lastId = orderedTileIds.last, let lastRect = tileFrames[lastId], point.y > lastRect.maxY - 24 || (point.x > lastRect.maxX && point.y > lastRect.minY) {
            return orderedTileIds.count
        }
        return bestIdx
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
