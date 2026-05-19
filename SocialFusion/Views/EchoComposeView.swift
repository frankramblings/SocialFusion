import SwiftUI

public struct EchoComposeView: View {
    @StateObject var viewModel: EchoComposeViewModel
    @Environment(\.dismiss) private var dismiss
    var onSend: (String, Set<SocialPlatform>) async -> Void

    public init(
        viewModel: EchoComposeViewModel,
        onSend: @escaping (String, Set<SocialPlatform>) async -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSend = onSend
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                replyingToHeader
                targetRows
                editor
                Spacer()
                charCounts
            }
            .padding(16)
            .onAppear {
                // Pre-warm so the tap haptic on Send has no perceptible latency.
                HapticEngine.prepare(.tap)
                HapticEngine.prepare(.success)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text("Reply").font(.headline)
                }
                ToolbarItem(placement: .confirmationAction) {
                    sendButton
                }
            }
        }
    }

    private var replyingToHeader: some View {
        HStack(spacing: 8) {
            FusedGlyph(size: 16)
            Text("Replying in a Fused conversation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var targetRows: some View {
        VStack(spacing: 0) {
            targetRow(.mastodon)
            Divider()
            targetRow(.bluesky)
        }
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func targetRow(_ platform: SocialPlatform) -> some View {
        HStack(spacing: 12) {
            PlatformLogoBadge(platform: platform, size: 24)
            Text(platform == .mastodon ? "Mastodon" : "Bluesky")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.targets.contains(platform) },
                set: { isOn in
                    if isOn { viewModel.targets.insert(platform) }
                    else { viewModel.targets.remove(platform) }
                }
            ))
            .labelsHidden()
            .accessibilityLabel(platform == .mastodon ? "Reply on Mastodon" : "Reply on Bluesky")
        }
        .padding(12)
    }

    private var editor: some View {
        TextEditor(text: $viewModel.text)
            .frame(minHeight: 120)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
            .accessibilityLabel("Reply text")
    }

    private var charCounts: some View {
        HStack(spacing: 12) {
            Spacer()
            counterChip(label: "M", value: viewModel.mastodonRemaining,
                        dimmed: !viewModel.targets.contains(.mastodon),
                        color: Color(red: 0.54, green: 0.39, blue: 1.00))
            counterChip(label: "B", value: viewModel.blueskyRemaining,
                        dimmed: !viewModel.targets.contains(.bluesky),
                        color: Color(red: 0.00, green: 0.59, blue: 1.00))
        }
    }

    private func counterChip(label: String, value: Int, dimmed: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2.weight(.bold))
            Text("\(value)").font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(dimmed ? 0.05 : 0.15), in: Capsule())
        .foregroundStyle(value < 0 ? .red : color)
        .opacity(dimmed ? 0.4 : 1.0)
    }

    private var sendButton: some View {
        Button {
            HapticEngine.tap.trigger()
            let text = viewModel.text
            let targets = viewModel.targets
            Task {
                await onSend(text, targets)
                dismiss()
            }
        } label: {
            Text(viewModel.sendActionLabel)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(sendButtonBackground)
                )
                .foregroundStyle(.white)
        }
        .disabled(!viewModel.canSend)
        .opacity(viewModel.canSend ? 1.0 : 0.45)
    }

    private var sendButtonBackground: AnyShapeStyle {
        switch viewModel.sendStyle {
        case .dual:
            return AnyShapeStyle(LinearGradient(
                colors: [
                    Color(red: 0.54, green: 0.39, blue: 1.00),
                    Color(red: 0.11, green: 0.91, blue: 1.00),
                    Color(red: 0.00, green: 0.59, blue: 1.00)
                ],
                startPoint: .leading,
                endPoint: .trailing
            ))
        case .mastodonOnly:
            return AnyShapeStyle(Color(red: 0.54, green: 0.39, blue: 1.00))
        case .blueskyOnly:
            return AnyShapeStyle(Color(red: 0.00, green: 0.59, blue: 1.00))
        case .disabled:
            return AnyShapeStyle(Color.gray)
        }
    }
}
