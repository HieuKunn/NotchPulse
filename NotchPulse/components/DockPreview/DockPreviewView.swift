import AppKit
import Defaults
import SwiftUI

struct DockPreviewView: View {
    @ObservedObject var viewModel: DockPreviewViewModel
    @Default(.dockPreviewShowTitles) private var showTitles
    @Default(.dockPreviewShowCloseButton) private var showCloseButton
    @Default(.dockPreviewSize) private var previewSize

    @State private var hoveredCardId: CGWindowID? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: App identity & window count
            HStack(spacing: 8) {
                if let icon = viewModel.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                Text(viewModel.appName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()

                if !viewModel.windows.isEmpty {
                    Text(loc("%d windows", viewModel.windows.count))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(nsColor: .separatorColor).opacity(0.2))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            // Body: Window thumbnail cards
            if viewModel.isLoading && viewModel.windows.isEmpty && !viewModel.isRunningWithNoWindows {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(loc("Loading previews..."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
            } else if viewModel.isRunningWithNoWindows {
                Button {
                    viewModel.onActivateApp?()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow.badge.plus")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(loc("No open windows — Click to activate"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            } else {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(viewModel.windows) { item in
                        windowThumbnailCard(for: item)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thickMaterial)
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        )
        .frame(minWidth: 160)
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
                // Window thumbnail preview
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let thumb = item.thumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .scaledToFit()
                        } else {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                                .overlay {
                                    Image(systemName: "macwindow")
                                        .font(.title2)
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(width: cardWidth, height: cardWidth * 0.62)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isHovered ? Color.effectiveAccent : Color(nsColor: .separatorColor).opacity(0.3),
                                lineWidth: isHovered ? 2.0 : 0.5
                            )
                    )

                    // Close window button on hover
                    if showCloseButton && isHovered {
                        Button {
                            viewModel.onCloseWindow?(item)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.white, Color.red)
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(6)
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
            withAnimation(.easeInOut(duration: 0.12)) {
                hoveredCardId = inside ? item.id : nil
            }
        }
    }
}
