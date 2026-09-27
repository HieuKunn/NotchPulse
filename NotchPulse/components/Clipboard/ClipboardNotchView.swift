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

    var body: some View {
        VStack(spacing: 8) {
            // Header
            HStack {
                Text("Clipboard History")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Text("\(clipboardManager.history.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Button(action: {
                    clipboardManager.clearHistory()
                }) {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(clipboardManager.history.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if clipboardManager.history.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("Clipboard is empty.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: 150)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 8) {
                        ForEach(clipboardManager.history, id: \.id) { item in
                            ClipboardRowView(item: item) {
                                clipboardManager.copyToPasteboard(item)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
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

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(item.isImage ? Color.purple.opacity(0.2) : Color.blue.opacity(0.2))
                    .frame(width: 32, height: 32)
                
                Image(systemName: item.isImage ? "photo" : "doc.text.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(item.isImage ? .purple : .blue)
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
                    Text("Copied")
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
    }
    
    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
