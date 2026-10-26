import SwiftUI

struct ClipboardNotchView: View {
    @ObservedObject var clipboardManager = ClipboardManager.shared
    @EnvironmentObject var vm: NotchPulseViewModel

    /// Open height that fits 3 full clipboard rows comfortably before scrolling.
    static let preferredHeight: CGFloat = 285

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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if vm.customOpenHeight != Self.preferredHeight {
                vm.customOpenHeight = Self.preferredHeight
            }
            clipboardManager.checkImmediately()
        }
        .onDisappear {
            clipboardThumbnailCache.removeAllObjects()
        }
    }
}

private let relativeDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .abbreviated
    return formatter
}()

private let clipboardThumbnailCache: NSCache<NSUUID, NSImage> = {
    let cache = NSCache<NSUUID, NSImage>()
    cache.countLimit = 30
    cache.totalCostLimit = 2 * 1024 * 1024
    return cache
}()

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
            if item.isImage && cachedImage == nil {
                let uuid = item.id as NSUUID
                if let cached = clipboardThumbnailCache.object(forKey: uuid) {
                    cachedImage = cached
                } else if let thumb = item.thumbnailData, let img = NSImage(data: thumb) {
                    clipboardThumbnailCache.setObject(img, forKey: uuid, cost: thumb.count)
                    cachedImage = img
                } else if let data = item.imageData, let img = NSImage(data: data) {
                    clipboardThumbnailCache.setObject(img, forKey: uuid, cost: data.count)
                    cachedImage = img
                }
            }
        }
        .onDisappear {
            // Immediately purge preview image from RAM when view disappears
            cachedImage = nil
        }
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }
}
