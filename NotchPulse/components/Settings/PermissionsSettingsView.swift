import SwiftUI
import AVFoundation

struct PermissionsSettingsView: View {
    @ObservedObject private var permissions = PermissionsManager.shared
    @Environment(\.settingsHighlightedId) private var highlightedId

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "lock.shield.fill")
                            .font(.title2)
                            .foregroundStyle(Color.effectiveAccent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(loc("Privacy & System Permissions"))
                                .font(.headline)
                            Text(loc("NotchPulse runs locally on your Mac. All permissions are used strictly on-device to power your notch features."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .id("permissions_overview")
            .searchHighlight(highlightedId == "permissions_overview")

            Section {
                permissionRow(for: .camera)
                permissionRow(for: .accessibility)
                permissionRow(for: .calendar)
                permissionRow(for: .reminders)
                permissionRow(for: .musicAutomation)
            } header: {
                Text(loc("Feature Permissions"))
            } footer: {
                Text(loc("Granting permissions enables NotchPulse to interact with hardware sensors, your calendar agenda, and media players."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("permissions_features")
            .searchHighlight(highlightedId == "permissions_features")

            Section {
                permissionRow(for: .screenRecording)
                permissionRow(for: .fullDiskAccess)
            } header: {
                Text(loc("Unneeded Permissions"))
            } footer: {
                Text(loc("NotchPulse respects your privacy and deliberately does not ask for or access your screen contents or entire file system."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .id("permissions_unneeded")
            .searchHighlight(highlightedId == "permissions_unneeded")
        }
        .formStyle(.grouped)
        .tint(.effectiveAccent)
        .onAppear {
            permissions.refreshAll()
        }
    }

    @ViewBuilder
    private func permissionRow(for kind: AppPermissionKind) -> some View {
        let status = permissions.status(for: kind)

        HStack(alignment: .center, spacing: 12) {
            Image(systemName: kind.systemIcon)
                .font(.headline)
                .foregroundStyle(statusColor(for: status))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(loc(kind.displayName))
                        .font(.body.weight(.medium))

                    statusBadge(for: status)
                }

                Text(loc(kind.featureDescription))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if kind.isRequiredForCoreFeatures {
                actionButton(for: kind, status: status)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusBadge(for status: PermissionStatus) -> some View {
        Label(loc(status.title), systemImage: status.systemIcon)
            .font(.caption)
            .foregroundStyle(statusColor(for: status))
    }

    @ViewBuilder
    private func actionButton(for kind: AppPermissionKind, status: PermissionStatus) -> some View {
        switch status {
        case .granted, .partiallyAuthorized:
            Button(loc("Settings")) {
                permissions.openSystemSettings(for: kind)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .notDetermined:
            Button(loc("Grant")) {
                permissions.request(permission: kind)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .denied, .restricted:
            Button(loc("Open Settings")) {
                permissions.openSystemSettings(for: kind)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.small)

        case .notNeeded:
            EmptyView()
        }
    }

    private func statusColor(for status: PermissionStatus) -> Color {
        switch status {
        case .granted: return .green
        case .partiallyAuthorized: return .orange
        case .notDetermined: return .secondary
        case .denied, .restricted: return .red
        case .notNeeded: return .secondary
        }
    }
}

