import SwiftUI

struct YourFaceSettingsPage: View {
    @Bindable private var store = NotchPulseFaceEnrollmentStore.shared

    @State private var identityPendingDeletion: FaceIdentity?
    @State private var writeError: String?

    private var enrollmentFlowIsRunning: Bool {
        FaceIDOverlayController.shared.phase == .onboarding
    }

    private var availability: FaceEnrollmentActionAvailability {
        NotchPulseFaceEnrollmentStore.determineActionAvailability(
            loadFailure: store.loadFailure,
            identitiesCount: store.identities.count,
            isFlowRunning: enrollmentFlowIsRunning
        )
    }

    var body: some View {
        Group {
            if let failure = store.loadFailure {
                Section {
                    VStack(alignment: .center, spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)

                        Text(loc("Enrolled faces couldn't be read"))
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(failure.isEmpty ? loc("The stored enrollment data couldn't be decrypted.") : failure)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button(loc("Retry Decryption")) {
                            store.reloadIfUnlocked()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                } header: {
                    Text(loc("Enrolled Faces"))
                } footer: {
                    Text(loc("To protect existing data from being overwritten, enrollment changes and face deletion are disabled while stored faces cannot be decrypted."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    if store.identities.isEmpty {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.title3)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(loc("No Enrolled Faces"))
                                    .font(.headline)
                                Text(loc("Enroll your face to unlock your Mac with on-device face recognition."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button(loc("Set up Face Unlock")) {
                                if NotchPulsePOCController.shared.hasStoredPassword {
                                    FaceIDEnrollmentController.startEnrollmentOnly()
                                } else {
                                    FaceIDEnrollmentController.startFlow()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!availability.canSetup)
                        }
                        .padding(.vertical, 4)
                    } else {
                        let activeModelIdentifier = NotchPulseFaceRecognitionPipeline.activeModelIdentifier
                        ForEach(store.identities) { identity in
                            IdentityRowView(
                                identity: identity,
                                isStale: identity.isStale(comparedToModelIdentifier: activeModelIdentifier),
                                canStartFlow: availability.canRecapture,
                                canDelete: availability.canDelete,
                                isEnabled: enabledBinding(for: identity),
                                canToggle: availability.canToggleIdentity,
                                recapture: { FaceIDEnrollmentController.startRecapture(of: identity) },
                                delete: { identityPendingDeletion = identity }
                            )
                        }

                        if !store.identities.isEmpty && store.activeIdentities.isEmpty {
                            Text(loc("No identities are enabled — face unlock won't recognize anyone until you switch one back on."))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if let writeError {
                            Text(writeError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    HStack {
                        Text(loc("Enrolled Faces"))
                        Spacer()
                        if !store.identities.isEmpty {
                            Button {
                                FaceIDEnrollmentController.startAddIdentity()
                            } label: {
                                Label(loc("Add Face"), systemImage: "plus")
                            }
                            .buttonStyle(.borderless)
                            .disabled(!availability.canAddFace)
                        }
                    }
                } footer: {
                    Text(loc("Face embeddings are encrypted using AES-GCM and stored strictly locally in your Keychain. NotchPulse never transmits biometric data."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { store.reloadIfUnlocked() }
        .onChange(of: FaceIDOverlayController.shared.phase) { _, newPhase in
            guard newPhase == .closed else { return }
            store.reloadIfUnlocked()
        }
        .confirmationDialog(
            loc("Delete this enrolled face?"),
            isPresented: Binding(
                get: { identityPendingDeletion != nil },
                set: { if !$0 { identityPendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: identityPendingDeletion
        ) { identity in
            Button(loc("Delete"), role: .destructive) { delete(identity) }
            Button(loc("Cancel"), role: .cancel) { identityPendingDeletion = nil }
        } message: { identity in
            Text(loc("\"%@\" will stop being recognized until you enroll them again.", identity.name))
        }
    }

    private func enabledBinding(for identity: FaceIdentity) -> Binding<Bool> {
        Binding(
            get: { store.identities.first { $0.id == identity.id }?.isEnabled ?? true },
            set: { newValue in
                do {
                    try store.setEnabled(newValue, for: identity.id)
                    writeError = nil
                } catch {
                    writeError = error.localizedDescription
                }
            }
        )
    }

    private func delete(_ identity: FaceIdentity) {
        do {
            try store.delete(identity)
            writeError = nil
        } catch {
            writeError = error.localizedDescription
        }
        identityPendingDeletion = nil
    }
}

private struct IdentityRowView: View {
    let identity: FaceIdentity
    let isStale: Bool
    let canStartFlow: Bool
    let canDelete: Bool
    @Binding var isEnabled: Bool
    let canToggle: Bool
    let recapture: () -> Void
    let delete: () -> Void

    private var poorCount: Int {
        identity.samples.filter { $0.qualityTier == .poor }.count
    }

    private var ratedCount: Int {
        identity.samples.filter { $0.qualityTier != .unrated }.count
    }

    private var qualityCaption: String {
        if identity.samples.isEmpty { return loc("No samples captured") }
        if ratedCount == 0 { return loc("Capture quality • not recorded") }
        return "\(loc("Capture quality")) • \(poorCount)/\(identity.samples.count) \(loc("low"))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(identity.name, systemImage: "person.crop.circle")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(!canToggle)
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(qualityCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    QualityTickStrip(samples: identity.samples)
                }

                Spacer()

                Button(loc("Recapture")) {
                    recapture()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canStartFlow)

                Button(role: .destructive) {
                    delete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!canDelete)
            }

            if isStale {
                Text(loc("Captured with a different recognition model — recapture before this face can unlock your Mac."))
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
        .opacity(isEnabled ? 1 : 0.5)
    }
}

private struct QualityTickStrip: View {
    let samples: [FaceSample]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                Capsule()
                    .fill(color(for: sample.qualityTier))
                    .frame(width: 4, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Capture quality for \(samples.count) samples")
    }

    private func color(for tier: FaceSample.QualityTier) -> Color {
        switch tier {
        case .poor: return .red
        case .fair: return .orange
        case .good: return .green
        case .unrated: return .secondary.opacity(0.3)
        }
    }
}
