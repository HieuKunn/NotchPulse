import AppKit
import Combine
import Defaults
import Foundation
import SwiftUI

/// Thread-safe application icon cache backed by NSCache for 120Hz scrolling.
final class LaunchpadIconCache: @unchecked Sendable {
    static let shared = LaunchpadIconCache()

    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 400
        return c
    }()

    func cachedIcon(for bundlePath: String) -> NSImage? {
        cache.object(forKey: bundlePath as NSString)
    }

    func loadIcon(for bundlePath: String) -> NSImage {
        if let existing = cache.object(forKey: bundlePath as NSString) {
            return existing
        }
        let rawIcon = NSWorkspace.shared.icon(forFile: bundlePath)
        // Downsample multi-rep .icns to a crisp 2x Retina 320x320px bitmap so large external monitors stay sharp without decoding 1024px reps
        let pixelDim = 320
        let pointDim: CGFloat = 160
        let rasterized = Self.rasterizeIcon(rawIcon, pixelDimension: pixelDim, pointSize: NSSize(width: pointDim, height: pointDim))
        cache.setObject(rasterized, forKey: bundlePath as NSString)
        return rasterized
    }

    private static func rasterizeIcon(_ image: NSImage, pixelDimension: Int, pointSize: NSSize) -> NSImage {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelDimension,
            pixelsHigh: pixelDimension,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            image.size = pointSize
            return image
        }
        rep.size = pointSize

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high

            // Bake a subtle macOS drop shadow directly into the cached bitmap so grids
            // composite as flat GPU textures without per-tile runtime CoreAnimation shadow passes.
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.26)
            shadow.shadowBlurRadius = 5.0
            shadow.shadowOffset = NSSize(width: 0, height: -3.0)
            shadow.set()

            let drawInset: CGFloat = 6.0
            let drawRect = NSRect(
                x: drawInset,
                y: drawInset,
                width: pointSize.width - drawInset * 2,
                height: pointSize.height - drawInset * 2
            )
            image.draw(
                in: drawRect,
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )
        }
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: pointSize)
        result.addRepresentation(rep)
        return result
    }

    func prewarm(paths: [String]) {
        let missing = paths.filter { cache.object(forKey: $0 as NSString) == nil }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            for path in missing {
                _ = self.loadIcon(for: path)
            }
        }
    }
}

/// Manages discovered macOS applications, persisted Launchpad page/folder layout,
/// search filtering, drag-and-drop rearrangements, and app launching.
@MainActor
final class LaunchpadManager: ObservableObject {
    static let shared = LaunchpadManager()

    @Published private(set) var pages: [LaunchpadPage] = []
    @Published private(set) var isScanning: Bool = false
    @Published var currentPageIndex: Int = 0
    @Published var activeFolderId: UUID? = nil
    @Published var searchQuery: String = ""
    @Published var isEditingMode: Bool = false

    private var hasLoadedInitialSnapshot = false
    private var lastDirectorySnapshotStamp: String = ""
    private var scanTask: Task<Void, Never>?

    var columns: Int {
        max(4, min(10, Defaults[.launchpadColumns]))
    }

    var rows: Int {
        max(3, min(8, Defaults[.launchpadRows]))
    }

    var pageCapacity: Int {
        max(1, columns * rows)
    }

    var allApplications: [LaunchpadAppItem] {
        var result: [LaunchpadAppItem] = []
        for page in pages {
            for node in page.nodes {
                switch node {
                case .app(let app):
                    result.append(app)
                case .folder(let folder):
                    result.append(contentsOf: folder.items)
                }
            }
        }
        return result
    }

    var searchResults: [LaunchpadAppItem] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let normalized = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let all = allApplications
        var seenIds = Set<String>()
        let unique = all.filter { seenIds.insert($0.id).inserted }

        let matches = unique.filter { app in
            let normalizedName = app.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return normalizedName.contains(normalized)
        }

        return matches.sorted { lhs, rhs in
            let lName = lhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let rName = rhs.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let lPrefix = lName.hasPrefix(normalized)
            let rPrefix = rName.hasPrefix(normalized)
            if lPrefix != rPrefix { return lPrefix }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var activeFolder: LaunchpadFolderItem? {
        guard let activeFolderId else { return nil }
        for page in pages {
            for node in page.nodes {
                if case .folder(let folder) = node, folder.id == activeFolderId {
                    return folder
                }
            }
        }
        return nil
    }

    private init() {}

    // MARK: - Loading & Discovery

    func prepareForPresentation() {
        if !hasLoadedInitialSnapshot {
            hasLoadedInitialSnapshot = true
            if let snapshot = Self.loadPersistedSnapshot(), !snapshot.pages.isEmpty {
                pages = snapshot.pages
                reflowOverflowIfNeeded(saveAfter: false)
                clampCurrentPageIndex()
                LaunchpadIconCache.shared.prewarm(paths: allApplications.map(\.bundlePath))
            }
        }

        refreshApps(force: pages.isEmpty)
    }

    func refreshApps(force: Bool = false) {
        scanTask?.cancel()
        let hadPages = !pages.isEmpty
        let previousStamp = lastDirectorySnapshotStamp
        isScanning = !hadPages

        scanTask = Task { [weak self] in
            let currentStamp = await Task.detached(priority: .utility) {
                Self.computeDirectoryStamp()
            }.value
            guard let self, !Task.isCancelled else { return }

            if !force, hadPages, currentStamp == previousStamp {
                self.isScanning = false
                return
            }

            let discovered = await Task.detached(priority: .userInitiated) {
                Self.scanInstalledApplications()
            }.value
            guard !Task.isCancelled else { return }
            self.lastDirectorySnapshotStamp = currentStamp
            self.applyDiscoveredApps(discovered)
            self.isScanning = false
            LaunchpadIconCache.shared.prewarm(paths: discovered.map(\.bundlePath))
        }
    }

    func resetLayout() {
        searchQuery = ""
        activeFolderId = nil
        isEditingMode = false
        try? FileManager.default.removeItem(at: Self.layoutFileURL())
        lastDirectorySnapshotStamp = ""
        pages = []
        currentPageIndex = 0
        refreshApps(force: true)
    }

    func reflowOverflowIfNeeded(saveAfter: Bool = true) {
        let cap = pageCapacity
        guard cap > 0, !pages.isEmpty else { return }

        var newPages = pages
        var index = 0
        while index < newPages.count {
            if newPages[index].nodes.count > cap {
                let overflow = Array(newPages[index].nodes.dropFirst(cap))
                newPages[index].nodes = Array(newPages[index].nodes.prefix(cap))
                if index + 1 < newPages.count {
                    newPages[index + 1].nodes.insert(contentsOf: overflow, at: 0)
                } else {
                    newPages.append(LaunchpadPage(id: UUID(), nodes: overflow))
                }
            }
            index += 1
        }
        newPages.removeAll { $0.nodes.isEmpty }
        if newPages != pages {
            pages = newPages
            clampCurrentPageIndex()
            if saveAfter { persistSnapshot() }
        }
    }

    // MARK: - App Launching & Actions

    func launchApp(_ app: LaunchpadAppItem) {
        LaunchpadWindowController.shared.dismiss(restorePreviousApp: false) {
            let url = app.bundleURL
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error {
                    NSLog("⚠️ Launchpad failed to open \(app.bundlePath): \(error.localizedDescription)")
                }
            }
        }
    }

    func revealInFinder(_ app: LaunchpadAppItem) {
        LaunchpadWindowController.shared.dismiss(restorePreviousApp: false) {
            NSWorkspace.shared.activateFileViewerSelecting([app.bundleURL])
        }
    }

    func canMoveToTrash(_ app: LaunchpadAppItem) -> Bool {
        guard !app.isSystemProtected else { return false }
        return app.bundlePath != Bundle.main.bundlePath
            && FileManager.default.isDeletableFile(atPath: app.bundlePath)
    }

    func moveAppToTrash(_ app: LaunchpadAppItem) {
        guard canMoveToTrash(app) else { return }
        let url = app.bundleURL
        Task.detached(priority: .userInitiated) {
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    NSWorkspace.shared.recycle([url]) { _, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
                await MainActor.run {
                    LaunchpadManager.shared.removeAppFromLayout(appId: app.id)
                }
            } catch {
                NSLog("⚠️ Failed to move app to Trash: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Page & Node Mutations

    @discardableResult
    func ensurePage(at index: Int) -> Int {
        if index < 0 {
            pages.insert(LaunchpadPage(id: UUID(), nodes: []), at: 0)
            return 0
        }
        while pages.count <= index {
            pages.append(LaunchpadPage(id: UUID(), nodes: []))
        }
        return index
    }

    func pruneEmptyPages(keepingPageIndex: Int? = nil) {
        var cleaned: [LaunchpadPage] = []
        for (idx, page) in pages.enumerated() {
            if !page.nodes.isEmpty || idx == keepingPageIndex {
                cleaned.append(page)
            }
        }
        if cleaned.isEmpty {
            cleaned = [LaunchpadPage(id: UUID(), nodes: [])]
        }
        if cleaned != pages {
            pages = cleaned
        }
        clampCurrentPageIndex()
        persistSnapshot()
    }

    func moveNode(nodeId: String, toPage targetPageIndex: Int, index targetIndex: Int?) {
        guard let source = locateNode(nodeId: nodeId) else { return }

        // Ensure target page exists before mutating indices
        let normalizedTargetPage = ensurePage(at: targetPageIndex)

        var workingPages = pages
        let node = workingPages[source.pageIndex].nodes.remove(at: source.nodeIndex)

        var destinationIndex: Int
        if let targetIndex {
            destinationIndex = targetIndex
            if source.pageIndex == normalizedTargetPage && source.nodeIndex < targetIndex {
                destinationIndex -= 1
            }
            destinationIndex = max(0, min(destinationIndex, workingPages[normalizedTargetPage].nodes.count))
        } else {
            destinationIndex = workingPages[normalizedTargetPage].nodes.count
        }

        workingPages[normalizedTargetPage].nodes.insert(node, at: destinationIndex)
        pages = workingPages
        reflowOverflowIfNeeded(saveAfter: false)
        pruneEmptyPages()
    }

    func dropNode(_ draggedNodeId: String, onto targetNodeId: String) {
        guard draggedNodeId != targetNodeId,
              let source = locateNode(nodeId: draggedNodeId),
              let target = locateNode(nodeId: targetNodeId)
        else { return }

        let draggedNode = pages[source.pageIndex].nodes[source.nodeIndex]
        let targetNode = pages[target.pageIndex].nodes[target.nodeIndex]

        switch (draggedNode, targetNode) {
        case (.app(let draggedApp), .app(let targetApp)):
            var workingPages = pages
            let folder = LaunchpadFolderItem(
                id: UUID(),
                name: Self.suggestedFolderName(for: targetApp, and: draggedApp),
                items: [targetApp, draggedApp]
            )
            workingPages[target.pageIndex].nodes[target.nodeIndex] = .folder(folder)

            let removeIdx: Int
            if source.pageIndex == target.pageIndex && source.nodeIndex == target.nodeIndex {
                return
            } else {
                removeIdx = source.nodeIndex
            }
            workingPages[source.pageIndex].nodes.remove(at: removeIdx)
            pages = workingPages
            pruneEmptyPages()

        case (.app(let draggedApp), .folder(var targetFolder)):
            var workingPages = pages
            if !targetFolder.items.contains(where: { $0.id == draggedApp.id }) {
                targetFolder.items.append(draggedApp)
            }
            workingPages[target.pageIndex].nodes[target.nodeIndex] = .folder(targetFolder)
            workingPages[source.pageIndex].nodes.remove(at: source.nodeIndex)
            pages = workingPages
            pruneEmptyPages()

        case (.folder, _):
            moveNode(nodeId: draggedNodeId, toPage: target.pageIndex, index: target.nodeIndex)
        }
    }

    func createFolderFromContextMenu(app: LaunchpadAppItem) {
        guard let loc = locateNode(nodeId: "app:\(app.id)") else { return }
        var workingPages = pages
        let folder = LaunchpadFolderItem(
            id: UUID(),
            name: Self.suggestedFolderName(for: app, and: nil),
            items: [app]
        )
        workingPages[loc.pageIndex].nodes[loc.nodeIndex] = .folder(folder)
        pages = workingPages
        activeFolderId = folder.id
        persistSnapshot()
    }

    func moveAppOutOfFolder(appId: String, fromFolder folderId: UUID, toPage targetPageIndex: Int, index targetIndex: Int?) {
        guard let folderLoc = locateNode(nodeId: "folder:\(folderId.uuidString)"),
              case .folder(var folder) = pages[folderLoc.pageIndex].nodes[folderLoc.nodeIndex],
              let appIdx = folder.items.firstIndex(where: { $0.id == appId })
        else { return }

        let extractedApp = folder.items.remove(at: appIdx)
        let normalizedTargetPage = ensurePage(at: targetPageIndex)

        var workingPages = pages
        if folder.items.isEmpty {
            workingPages[folderLoc.pageIndex].nodes.remove(at: folderLoc.nodeIndex)
        } else if folder.items.count == 1 {
            // Classic Launchpad behavior: unwrap 1-item folder back to standalone app
            workingPages[folderLoc.pageIndex].nodes[folderLoc.nodeIndex] = .app(folder.items[0])
        } else {
            workingPages[folderLoc.pageIndex].nodes[folderLoc.nodeIndex] = .folder(folder)
        }

        let safeTargetPage = min(normalizedTargetPage, workingPages.count - 1)
        let insertIdx = max(0, min(targetIndex ?? workingPages[safeTargetPage].nodes.count, workingPages[safeTargetPage].nodes.count))
        workingPages[safeTargetPage].nodes.insert(.app(extractedApp), at: insertIdx)

        pages = workingPages
        if folder.items.count <= 1 && activeFolderId == folderId {
            activeFolderId = nil
        }
        reflowOverflowIfNeeded(saveAfter: false)
        pruneEmptyPages()
    }

    func reorderApp(_ appId: String, insideFolder folderId: UUID, toIndex targetIndex: Int) {
        guard let folderLoc = locateNode(nodeId: "folder:\(folderId.uuidString)"),
              case .folder(var folder) = pages[folderLoc.pageIndex].nodes[folderLoc.nodeIndex],
              let sourceIdx = folder.items.firstIndex(where: { $0.id == appId })
        else { return }

        let item = folder.items.remove(at: sourceIdx)
        var destinationIndex = targetIndex
        if sourceIdx < targetIndex {
            destinationIndex -= 1
        }
        let clampedIndex = max(0, min(destinationIndex, folder.items.count))
        folder.items.insert(item, at: clampedIndex)

        var workingPages = pages
        workingPages[folderLoc.pageIndex].nodes[folderLoc.nodeIndex] = .folder(folder)
        pages = workingPages
        persistSnapshot()
    }

    func renameFolder(folderId: UUID, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let folderLoc = locateNode(nodeId: "folder:\(folderId.uuidString)"),
              case .folder(var folder) = pages[folderLoc.pageIndex].nodes[folderLoc.nodeIndex]
        else { return }

        guard folder.name != trimmed else { return }
        folder.name = trimmed
        var workingPages = pages
        workingPages[folderLoc.pageIndex].nodes[folderLoc.nodeIndex] = .folder(folder)
        pages = workingPages
        persistSnapshot()
    }

    func removeAppFromLayout(appId: String) {
        var workingPages = pages
        for pageIdx in workingPages.indices {
            workingPages[pageIdx].nodes.removeAll { node in
                if case .app(let app) = node, app.id == appId { return true }
                return false
            }
            for nodeIdx in workingPages[pageIdx].nodes.indices {
                if case .folder(var folder) = workingPages[pageIdx].nodes[nodeIdx] {
                    folder.items.removeAll { $0.id == appId }
                    if folder.items.isEmpty {
                        workingPages[pageIdx].nodes[nodeIdx] = .folder(folder)
                    } else if folder.items.count == 1 {
                        workingPages[pageIdx].nodes[nodeIdx] = .app(folder.items[0])
                    } else {
                        workingPages[pageIdx].nodes[nodeIdx] = .folder(folder)
                    }
                }
            }
            workingPages[pageIdx].nodes.removeAll { node in
                if case .folder(let folder) = node { return folder.items.isEmpty }
                return false
            }
        }
        pages = workingPages
        pruneEmptyPages()
    }

    // MARK: - Helpers

    private func locateNode(nodeId: String) -> (pageIndex: Int, nodeIndex: Int)? {
        for (pIdx, page) in pages.enumerated() {
            if let nIdx = page.nodes.firstIndex(where: { $0.id == nodeId }) {
                return (pIdx, nIdx)
            }
        }
        return nil
    }

    private func clampCurrentPageIndex() {
        if pages.isEmpty {
            currentPageIndex = 0
        } else {
            currentPageIndex = max(0, min(currentPageIndex, pages.count - 1))
        }
    }

    private func applyDiscoveredApps(_ discovered: [LaunchpadAppItem]) {
        if pages.isEmpty {
            pages = buildInitialPages(from: discovered)
            persistSnapshot()
            return
        }

        let byId = Dictionary(discovered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let byPath = Dictionary(discovered.map { ($0.bundlePath, $0) }, uniquingKeysWith: { first, _ in first })

        var retainedIds = Set<String>()
        var updatedPages: [LaunchpadPage] = []

        for page in pages {
            var updatedNodes: [LaunchpadNode] = []
            for node in page.nodes {
                switch node {
                case .app(let oldApp):
                    if let fresh = byId[oldApp.id] ?? byPath[oldApp.bundlePath] {
                        updatedNodes.append(.app(fresh))
                        retainedIds.insert(fresh.id)
                    }
                case .folder(var folder):
                    var freshItems: [LaunchpadAppItem] = []
                    for oldApp in folder.items {
                        if let fresh = byId[oldApp.id] ?? byPath[oldApp.bundlePath], !retainedIds.contains(fresh.id) {
                            freshItems.append(fresh)
                            retainedIds.insert(fresh.id)
                        }
                    }
                    if freshItems.count >= 2 {
                        folder.items = freshItems
                        updatedNodes.append(.folder(folder))
                    } else if freshItems.count == 1 {
                        updatedNodes.append(.app(freshItems[0]))
                    }
                }
            }
            if !updatedNodes.isEmpty {
                updatedPages.append(LaunchpadPage(id: page.id, nodes: updatedNodes))
            }
        }

        let newlyInstalled = discovered.filter { !retainedIds.contains($0.id) }
        if !newlyInstalled.isEmpty {
            let cap = pageCapacity
            for app in newlyInstalled {
                if let lastIdx = updatedPages.indices.last, updatedPages[lastIdx].nodes.count < cap {
                    updatedPages[lastIdx].nodes.append(.app(app))
                } else {
                    updatedPages.append(LaunchpadPage(id: UUID(), nodes: [.app(app)]))
                }
            }
        }

        if updatedPages.isEmpty {
            updatedPages = buildInitialPages(from: discovered)
        }

        if updatedPages != pages {
            pages = updatedPages
            clampCurrentPageIndex()
            persistSnapshot()
        }
    }

    private func buildInitialPages(from apps: [LaunchpadAppItem]) -> [LaunchpadPage] {
        var utilitiesApps: [LaunchpadAppItem] = []
        var systemApps: [LaunchpadAppItem] = []
        var userApps: [LaunchpadAppItem] = []

        for app in apps {
            if app.bundlePath.contains("/Utilities/") {
                utilitiesApps.append(app)
            } else if app.isSystemProtected {
                systemApps.append(app)
            } else {
                userApps.append(app)
            }
        }

        systemApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        userApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        utilitiesApps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        var allNodes: [LaunchpadNode] = systemApps.map { .app($0) }
        if utilitiesApps.count >= 2 {
            let folder = LaunchpadFolderItem(id: UUID(), name: loc("Utilities"), items: utilitiesApps)
            allNodes.append(.folder(folder))
        } else {
            allNodes.append(contentsOf: utilitiesApps.map { .app($0) })
        }
        allNodes.append(contentsOf: userApps.map { .app($0) })

        let cap = pageCapacity
        guard !allNodes.isEmpty else {
            return [LaunchpadPage(id: UUID(), nodes: [])]
        }

        var builtPages: [LaunchpadPage] = []
        var start = 0
        while start < allNodes.count {
            let end = min(start + cap, allNodes.count)
            builtPages.append(LaunchpadPage(id: UUID(), nodes: Array(allNodes[start..<end])))
            start = end
        }
        return builtPages
    }

    private func persistSnapshot() {
        let snapshot = LaunchpadLayoutSnapshot(pages: pages)
        let url = Self.layoutFileURL()
        Task.detached(priority: .utility) {
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("⚠️ Launchpad failed to save layout: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Non-isolated Filesystem Discovery & Persistence Helpers

    private nonisolated static func layoutFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("NotchPulse", isDirectory: true)
            .appendingPathComponent("launchpad_layout.json")
    }

    private nonisolated static func loadPersistedSnapshot() -> LaunchpadLayoutSnapshot? {
        let url = layoutFileURL()
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(LaunchpadLayoutSnapshot.self, from: data)
    }

    private nonisolated static func appSearchRoots() -> [URL] {
        var roots: [URL] = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        // Deduplicate paths that exist
        roots = roots.filter { FileManager.default.fileExists(atPath: $0.path) }
        return roots
    }

    private nonisolated static func computeDirectoryStamp() -> String {
        let fm = FileManager.default
        var parts: [String] = []
        let candidatePaths = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        ]
        for path in candidatePaths {
            if let attrs = try? fm.attributesOfItem(atPath: path),
               let modDate = attrs[.modificationDate] as? Date {
                parts.append("\(path):\(modDate.timeIntervalSince1970)")
            }
        }
        return parts.joined(separator: "|")
    }

    private nonisolated static func scanInstalledApplications() -> [LaunchpadAppItem] {
        let fm = FileManager.default
        var discovered: [LaunchpadAppItem] = []
        var seenResolvedPaths = Set<String>()
        var seenIds = Set<String>()

        for root in appSearchRoots() {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            while let next = enumerator.nextObject() as? URL {
                if next.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()

                    let resolvedPath = next.resolvingSymlinksInPath().path
                    guard seenResolvedPaths.insert(resolvedPath).inserted else { continue }

                    let bundle = Bundle(url: next)
                    let info = bundle?.infoDictionary
                    if let bgOnly = info?["LSBackgroundOnly"] as? Bool, bgOnly { continue }
                    if let bgString = info?["LSBackgroundOnly"] as? String, bgString == "1" { continue }

                    let bundleId = bundle?.bundleIdentifier
                    if bundleId == "com.apple.finder" || bundleId == "com.apple.apps.launcher" { continue }

                    let displayName = resolveDisplayName(at: next, bundle: bundle)
                    let category = info?["LSApplicationCategoryType"] as? String

                    var itemId = bundleId ?? next.path
                    if seenIds.contains(itemId) {
                        itemId = next.path
                    }
                    seenIds.insert(itemId)

                    discovered.append(
                        LaunchpadAppItem(
                            id: itemId,
                            name: displayName,
                            bundlePath: next.path,
                            bundleIdentifier: bundleId,
                            categoryType: category
                        )
                    )
                } else if enumerator.level >= 2 {
                    enumerator.skipDescendants()
                }
            }
        }

        return discovered
    }

    private nonisolated static func resolveDisplayName(at url: URL, bundle: Bundle?) -> String {
        let rawDisplay = FileManager.default.displayName(atPath: url.path)
        let stripped = rawDisplay.hasSuffix(".app") ? String(rawDisplay.dropLast(4)) : rawDisplay
        if !stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stripped
        }
        if let cfDisplay = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.infoDictionary?["CFBundleDisplayName"] as? String
            ?? bundle?.localizedInfoDictionary?["CFBundleName"] as? String
            ?? bundle?.infoDictionary?["CFBundleName"] as? String {
            return cfDisplay
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private static func suggestedFolderName(for first: LaunchpadAppItem, and second: LaunchpadAppItem?) -> String {
        let categories = [first.categoryType, second?.categoryType].compactMap { $0 }
        for cat in categories {
            if cat.contains("utilities") { return loc("Utilities") }
            if cat.contains("productivity") || cat.contains("business") { return loc("Productivity") }
            if cat.contains("developer-tools") { return loc("Developer") }
            if cat.contains("games") { return loc("Games") }
            if cat.contains("social-networking") { return loc("Social") }
            if cat.contains("entertainment") || cat.contains("music") || cat.contains("video") { return loc("Entertainment") }
            if cat.contains("graphics-design") || cat.contains("photography") { return loc("Creativity") }
            if cat.contains("education") { return loc("Education") }
        }
        return loc("New Folder")
    }
}

