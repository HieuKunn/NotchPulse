//
//  ClipboardNotchView.swift
//  NotchPulse
//
//  Created by Alexander on 2026-09-26.
//

import SwiftUI
import Defaults

struct ClipboardNotchView: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @EnvironmentObject var vm: NotchPulseViewModel

    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack {
                Text(loc("Clipboard History"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(clipboardManager.history.count) \(loc("items"))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button(action: {
                    clipboardManager.clearHistory()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(clipboardManager.history.isEmpty)
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)

            if clipboardManager.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text(loc("Clipboard is empty."))
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: 150)
                .onAppear {
                    vm.clipboardScrolledToBottom = true
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(clipboardManager.history, id: \.id) { item in
                            ClipboardRowView(item: item) {
                                clipboardManager.copyToPasteboard(item)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                    .background(
                        ClipboardScrollWheelHelper { isAtBottom in
                            if vm.clipboardScrolledToBottom != isAtBottom {
                                vm.clipboardScrolledToBottom = isAtBottom
                            }
                        }
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    let atBottom = clipboardManager.history.count <= 3
                    if vm.clipboardScrolledToBottom != atBottom {
                        vm.clipboardScrolledToBottom = atBottom
                    }
                }
                .onChange(of: clipboardManager.history.count) { _, newCount in
                    let atBottom = newCount <= 3
                    if vm.clipboardScrolledToBottom != atBottom {
                        vm.clipboardScrolledToBottom = atBottom
                    }
                }
            }
        }
        .padding(.horizontal, (Defaults[.notchStyle] == .dynamicIsland) ? 10 : 20)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onHover { isHovering in
            vm.isHoveringClipboard = isHovering
        }
        .onAppear {
            clipboardManager.checkImmediately()
        }
    }
}

// MARK: - AppKit Scroll Helper for Clipboard
private struct ClipboardScrollWheelHelper: NSViewRepresentable {
    var onScrollStateChanged: ((Bool) -> Void)? = nil

    func makeNSView(context: Context) -> HelperView {
        let view = HelperView()
        view.onScrollStateChanged = onScrollStateChanged
        return view
    }

    func updateNSView(_ nsView: HelperView, context: Context) {
        nsView.onScrollStateChanged = onScrollStateChanged
        nsView.checkSetup()
    }

    class HelperView: NSView {
        private var boundsObserver: NSObjectProtocol?
        var onScrollStateChanged: ((Bool) -> Void)?
        private var lastState: Bool? = nil

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window != nil {
                checkSetup()
            } else {
                cleanup()
            }
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            if superview != nil {
                checkSetup()
            }
        }

        deinit {
            cleanup()
        }

        private func cleanup() {
            if let b = boundsObserver {
                NotificationCenter.default.removeObserver(b)
                boundsObserver = nil
            }
        }

        func evaluateBottom() {
            guard let sv = self.enclosingScrollView else { return }
            let clip = sv.contentView
            let doc = sv.documentView
            let docHeight = doc?.bounds.height ?? 0
            let clipHeight = clip.bounds.height
            let originY = clip.bounds.origin.y

            let isAtBottom: Bool
            if docHeight <= clipHeight + 4 {
                isAtBottom = true
            } else {
                isAtBottom = (originY + clipHeight >= docHeight - 8)
            }

            guard lastState != isAtBottom else { return }
            lastState = isAtBottom

            DispatchQueue.main.async { [weak self] in
                self?.onScrollStateChanged?(isAtBottom)
            }
        }

        func checkSetup() {
            guard window != nil else { return }

            if let scrollView = enclosingScrollView, boundsObserver == nil {
                let clipView = scrollView.contentView
                clipView.postsBoundsChangedNotifications = true

                boundsObserver = NotificationCenter.default.addObserver(
                    forName: NSView.boundsDidChangeNotification,
                    object: clipView,
                    queue: .main
                ) { [weak self] _ in
                    self?.evaluateBottom()
                }
            }
        }
    }
}

struct ClipboardRowView: View {
    let item: ClipboardItem
    var onCopy: (() -> Void)? = nil
    @State private var isHovered = false
    @State private var isCopied = false
    @State private var cachedImage: NSImage? = nil

    private var itemColor: Color {
        if item.isImage { return .purple }
        switch item.type {
        case .url: return .cyan
        case .file: return .orange
        case .image: return .purple
        case .text: return .blue
        }
    }

    private var itemIconName: String {
        if item.isImage { return "photo" }
        switch item.type {
        case .url: return "link"
        case .file: return "doc.fill"
        case .image: return "photo"
        case .text: return "doc.text.fill"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(itemColor.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                if item.isImage {
                    if let img = cachedImage {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .foregroundStyle(itemColor)
                    }
                } else {
                    Image(systemName: itemIconName)
                        .font(.system(size: 14))
                        .foregroundStyle(itemColor)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Text(formatTimestamp(item.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
            
            if isCopied {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                    Text(loc("Copied"))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(Color.green)
                .transition(.opacity)
            } else if isHovered {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.08 : 0.04))
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onTapGesture {
            onCopy?()
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCopied = false
                }
            }
        }
        .onAppear {
            if item.isImage && cachedImage == nil, let data = item.imageData {
                cachedImage = NSImage(data: data)
            }
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
