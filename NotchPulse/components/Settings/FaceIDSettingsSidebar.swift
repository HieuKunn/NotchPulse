//
//  FaceIDSettingsSidebar.swift
//  NotchPulse
//
//  CRITICAL DESIGN REQUIREMENT (MANDATORY):
//  ========================================================================================
//  GIỮ NGUYÊN GIAO DIỆN SIDEBAR NÀY Ở PHÍA BÊN TRÁI. TUYỆT ĐỐI KHÔNG TỰ Ý THAY ĐỔI
//  SANG DẠNG SEGMENTED BAR HOẶC DẠNG NÀO KHÁC NẾU NGƯỜI DÙNG KHÔNG YÊU CẦU!
//  KEEP THIS LEFT SIDEBAR LAYOUT AS-IS. DO NOT CHANGE TO SEGMENTED CONTROL OR ANYTHING ELSE
//  UNLESS EXPLICITLY INSTRUCTED BY THE USER!
//  ========================================================================================
//

import SwiftUI

struct FaceIDSettingsSidebar: View {
    @Binding var selection: SettingsTab
    @Bindable var pocController: NotchPulsePOCController

    @State private var isUnlocking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: SettingsMetrics.sidebarSectionSpacing) {
                sidebarRow(.general)

                Text("Authentication")
                    .font(SettingsMetrics.sectionHeaderFont)
                    .foregroundStyle(SettingsMetrics.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 14)
                    .padding(.bottom, 4)

                sidebarRow(.yourFace)
                sidebarRow(.password)
                sidebarRow(.camera)
                sidebarRow(.recognition)
            }
            .padding(.leading, SettingsMetrics.sidebarContentLeadingInset)
            .padding(.trailing, SettingsMetrics.sidebarContentTrailingInset)
            .padding(.top, 16)

            Spacer(minLength: 0)

            sessionLockIndicator
                .padding(.leading, SettingsMetrics.sidebarContentLeadingInset)
                .padding(.trailing, SettingsMetrics.sidebarContentTrailingInset)
                .padding(.bottom, 16)
        }
        .frame(width: SettingsMetrics.sidebarWidth)
        .onAppear { pocController.refreshCredentialStatus() }
        .onChange(of: FaceIDOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            pocController.refreshCredentialStatus()
        }
    }

    /// Docked to the sidebar's bottom edge, always visible. Doubles as the
    /// session's on/off switch: unlocks while locked, locks while unlocked.
    private var sessionLockIndicator: some View {
        Button(action: toggleSession) {
            HStack(spacing: 8) {
                Image(systemName: pocController.isSessionUnlocked ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(SettingsMetrics.textPrimary)
                    .frame(width: 16)
                    .contentTransition(.symbolEffect(.replace))

                Text(sessionLockLabel)
                    .font(SettingsMetrics.sidebarItemFont)
                    .foregroundStyle(SettingsMetrics.textPrimary)
                    .contentTransition(.opacity)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.sidebarItemHeight, alignment: .leading)
            .background(SettingsMetrics.rowColor)
            .overlay(
                RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius)
                    .strokeBorder(SettingsMetrics.rowBorder, lineWidth: SettingsMetrics.rowBorderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius))
            .contentShape(RoundedRectangle(cornerRadius: SettingsMetrics.rowRadius))
        }
        .buttonStyle(.plain)
        .disabled(isUnlocking)
        .animation(SettingsMetrics.stateTransitionAnimation, value: pocController.isSessionUnlocked)
        .animation(SettingsMetrics.stateTransitionAnimation, value: isUnlocking)
    }

    private var sessionLockLabel: String {
        if pocController.isSessionUnlocked { return "Session unlocked" }
        return isUnlocking ? "Authenticating…" : "Session locked"
    }

    private func toggleSession() {
        if pocController.isSessionUnlocked {
            pocController.lockSession()
            return
        }
        isUnlocking = true
        Task {
            await pocController.unlockSession()
            isUnlocking = false
        }
    }

    private func sidebarRow(_ tab: SettingsTab) -> some View {
        Button {
            selection = tab
        } label: {
            HStack(spacing: 8) {
                SettingsTabIconBadge(
                    icon: tab.icon,
                    gradientColors: tab.badgeGradientColors,
                    size: SettingsMetrics.sidebarIconBadgeSize,
                    cornerRadius: SettingsMetrics.sidebarIconBadgeCornerRadius,
                    iconSize: SettingsMetrics.sidebarIconBadgeGlyphSize
                )
                Text(tab.title)
                    .font(SettingsMetrics.sidebarItemFont)
                    .foregroundStyle(SettingsMetrics.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: SettingsMetrics.sidebarItemHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: SettingsMetrics.selectedPillRadius)
                    .fill(selection == tab ? SettingsMetrics.selectedPillColor : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
