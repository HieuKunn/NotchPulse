import AppKit
import Defaults
import SwiftUI

struct DockPreviewView: View {
    @ObservedObject var viewModel: DockPreviewViewModel
    @Default(.dockPreviewShowTitles) private var showTitles
    @Default(.dockPreviewShowCloseButton) private var showCloseButton
    @Default(.dockPreviewSize) private var previewSize

    @State private var hoveredCardId: CGWindowID? = nil

    private var isVerticalLayout: Bool {
        viewModel.dockPosition == .left || viewModel.dockPosition == .right
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: App identity & window count
            HStack(spacing: 8) {
                if let icon = viewModel.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Text(viewModel.appName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                if viewModel.windows.count > 1 {
                    Text("\(viewModel.windows.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Color(nsColor: .separatorColor).opacity(0.25))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            // Body: Window cards
            if isVerticalLayout {
                // Vertical layout when Dock is Left/Right
                ScrollView(.vertical, showsIndicators: viewModel.windows.count > 3) {
                    VStack(spacing: 8) {
                        ForEach(viewModel.windows) { item in
                            windowThumbnailCard(for: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: min(480, CGFloat(viewModel.windows.count) * 155 + 10))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            } else {
                // Horizontal layout when Dock is Bottom
                ScrollView(.horizontal, showsIndicators: viewModel.windows.count > 3) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(viewModel.windows) { item in
                            windowThumbnailCard(for: item)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .frame(maxWidth: min(720, CGFloat(viewModel.windows.count) * (previewSize.thumbnailWidth + 10) + 16))
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: Color.black.opacity(0.20), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        )
        .fixedSize()
    }

    @ViewBuilder
    private func windowThumbnailCard(for item: DockWindowItem) -> some View {
        let isHovered = (hoveredCardId == item.id)
        let cardWidth = previewSize.thumbnailWidth

        Button {
            viewModel.onSelectWindow?(item)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                // Thumbnail preview box
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let thumb = item.thumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
                                .overlay {
                                    VStack(spacing: 4) {
                                        Image(systemName: item.isMinimized ? "arrow.down.right.and.arrow.up.left" : "macwindow")
                                            .font(.title3)
                                            .foregroundStyle(.secondary)
                                        if item.isMinimized {
                                            Text(loc("Minimized"))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                        }
                    }
                    .frame(width: cardWidth, height: cardWidth * 0.60)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                isHovered ? Color.effectiveAccent : Color(nsColor: .separatorColor).opacity(0.25),
                                lineWidth: isHovered ? 1.5 : 0.5
                            )
                    )

                    // Quick-close button
                    if showCloseButton && isHovered {
                        Button {
                            viewModel.onCloseWindow?(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 15))
                                .foregroundStyle(.white, Color.red)
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(5)
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                    }
                }

                // Window Title
                if showTitles {
                    Text(item.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isHovered ? Color.effectiveAccent : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: cardWidth, alignment: .leading)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.10)) {
                hoveredCardId = inside ? item.id : nil
            }
        }
    }
}
