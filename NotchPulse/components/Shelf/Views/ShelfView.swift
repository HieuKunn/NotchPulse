//
//  ShelfView.swift
//  NotchPulse
//
//  Created by Alexander on 2025-09-24.
//

import SwiftUI
import AppKit
import Defaults

struct ShelfView: View {
    @EnvironmentObject var vm: NotchPulseViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @State private var isShelfTargeted = false
    private let spacing: CGFloat = 8

    var body: some View {
        HStack(spacing: 12) {
            FileShareView()
                .frame(width: 130)
                .frame(maxHeight: .infinity)
                .environmentObject(vm)
            panel
                .frame(maxHeight: .infinity)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isShelfTargeted) { providers in
                    handleDrop(providers: providers)
                }
        }
        .padding(.horizontal, (Defaults[.notchStyle] == .dynamicIsland) ? 10 : 20)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isShelfTargeted) { _, targeted in
            vm.shelfDropTargeting = targeted
        }
        // Bind Quick Look to shelf selection
        .onChange(of: selection.selectedIDs) {
            updateQuickLookSelection()
        }
        .quickLookPresenter(using: quickLookService)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }
    
    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }
        
        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }
        
        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(Color.black.opacity(0.35))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isShelfTargeted
                            ? Color.accentColor.opacity(0.9)
                            : Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 6])
                    )
            )
            .overlay {
                content
                    .padding(12)
            }
            .overlay(alignment: .bottomTrailing) {
                pinButton
                    .padding(10)
            }
            .transaction { transaction in
                transaction.animation = vm.animation
            }
            .contentShape(Rectangle())
            .onTapGesture { selection.clear() }
    }

    var pinButton: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                tvm.isPinned.toggle()
            }
            if !tvm.isPinned && !vm.isMouseHovering() {
                vm.close()
            }
        } label: {
            Image(systemName: tvm.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tvm.isPinned ? Color.green : Color.white.opacity(0.65))
                .rotationEffect(.degrees(tvm.isPinned ? 0 : 45))
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tvm.isPinned ? Color.green.opacity(0.22) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(tvm.isPinned ? Color.green.opacity(0.7) : Color.white.opacity(0.12), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .help(tvm.isPinned ? loc("Unpin Shelf (Close on hover exit)") : loc("Pin Shelf (Keep open when hovering out)"))
    }

    var content: some View {
        Group {
            if tvm.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(
                            isShelfTargeted ? Color.accentColor : Color.white.opacity(0.75)
                        )
                        .scaleEffect(isShelfTargeted ? 1.1 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isShelfTargeted)
                    
                    Text(loc("Drop files here"))
                        .foregroundStyle(.white.opacity(0.85))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: spacing) {
                        ForEach(tvm.items) { item in
                            ShelfItemView(item: item)
                                .environmentObject(quickLookService)
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .scrollIndicators(.never)
                .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $isShelfTargeted) { providers in
                    handleDrop(providers: providers)
                }
            }
        }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
