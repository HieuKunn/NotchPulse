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
        VStack(alignment: .leading, spacing: isVerticalLayout ? 4 : 8) {
            // Header: App identity & window count (ONLY displayed for horizontal / bottom dock layout)
            if !isVerticalLayout {
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
            }

            // Body: Window cards
            if isVerticalLayout {
                // Vertical layout when Dock is Left/Right
                if viewModel.windows.count <= 3 {
                    VStack(spacing: 6) {
                        ForEach(viewModel.windows) { item in
                            windowThumbnailCard(for: item)
                        }
                    }
                    .padding(6)
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(spacing: 6) {
                            ForEach(viewModel.windows) { item in
                                windowThumbnailCard(for: item)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 520)
                    .padding(6)
                }
            } else {
                // Horizontal layout when Dock is Bottom
                if viewModel.windows.count <= 4 {
                    HStack(alignment: .top, spacing: 6) {
                        ForEach(viewModel.windows) { item in
                            windowThumbnailCard(for: item)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        HStack(alignment: .top, spacing: 6) {
                            ForEach(viewModel.windows) { item in
                                windowThumbnailCard(for: item)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .frame(maxWidth: 880)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }
            }
        }
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
            VStack(alignment: .leading, spacing: 6) {
                // Thumbnail preview box
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let thumb = item.thumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFit()
                        } else {
                            // Authentic macOS window mockup fallback
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))

                                VStack(spacing: 0) {
                                    // Window titlebar mockup with traffic lights
                                    HStack(spacing: 4) {
                                        Circle().fill(Color.red.opacity(0.75)).frame(width: 5, height: 5)
                                        Circle().fill(Color.yellow.opacity(0.75)).frame(width: 5, height: 5)
                                        Circle().fill(Color.green.opacity(0.75)).frame(width: 5, height: 5)
                                        Spacer()
                                        if item.isMinimized {
                                            Image(systemName: "arrow.up.forward.and.arrow.down.backward")
                                                .font(.system(size: 8))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 18)
                                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

                                    Divider()
                                        .opacity(0.3)

                                    // Window body mockup with app icon and content wireframe
                                    VStack(spacing: 6) {
                                        Spacer()
                                        if let icon = viewModel.appIcon {
                                            Image(nsImage: icon)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 28, height: 28)
                                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                                        } else {
                                            Image(systemName: "macwindow")
                                                .font(.system(size: 24))
                                                .foregroundStyle(.secondary)
                                        }

                                        // Subtle content wireframe lines
                                        VStack(spacing: 3) {
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(Color.secondary.opacity(0.2))
                                                .frame(width: 60, height: 3)
                                            RoundedRectangle(cornerRadius: 1.5)
                                                .fill(Color.secondary.opacity(0.12))
                                                .frame(width: 40, height: 3)
                                        }
                                        Spacer()
                                    }
                                }
                            }
                        }
                    }
                    .frame(width: cardWidth, height: cardWidth * 0.60)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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

                // Window Title (always shown in vertical layout, or according to user preference)
                if showTitles || isVerticalLayout {
                    Text(item.title.isEmpty ? viewModel.appName : item.title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(isHovered ? Color.effectiveAccent : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: cardWidth, alignment: .leading)
                        .padding(.horizontal, 2)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isHovered ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.10)) {
                hoveredCardId = inside ? item.id : nil
            }
        }
    }
}
