import SwiftUI

public struct EchoComposeView: View {
    @StateObject var viewModel: EchoComposeViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editorFocused: Bool
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
                // Auto-focus the editor — matches Mail, Messages, and the
                // primary compose flow. Without it the user has to tap
                // twice (open sheet, then tap the text area) before they
                // can type, which is friction.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    editorFocused = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    if viewModel.isSending {
                        // Tiny inline progress signal while the dispatch
                        // is running — matches the iOS-native pattern
                        // (Mail toolbar shows a ProgressView while sending).
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Sending reply")
                    } else {
                        Text("Reply").font(.headline)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    sendButton
                }
            }
            .modifier(EchoComposeKeyboardShortcuts(
                canSend: viewModel.canSend,
                send: sendIfPossible,
                cancel: { dismiss() }
            ))
            // Block swipe-down dismissal while a send is in flight. The
            // toolbar still shows a ProgressView, the Send button is
            // already disabled, and a stray pull-to-dismiss would
            // orphan the in-flight reply behind a closed sheet —
            // confusing for the user even though the dispatch survives.
            // Cancel stays available in the toolbar as an explicit out.
            .interactiveDismissDisabled(viewModel.isSending)
        }
    }

    /// Cmd+Return entry point shared with the toolbar Send button.
    private func sendIfPossible() {
        guard viewModel.canSend else { return }
        HapticEngine.tap.trigger()
        let text = viewModel.text
        let targets = viewModel.targets
        viewModel.beginSending()
        Task {
            await onSend(text, targets)
            // Don't call finishSending() here. The sheet's dismiss is
            // animated (~250ms); if we cleared the gate before the
            // animation completes, a quick re-tap on Send during that
            // window would spawn a second dispatch. Leaving isSending
            // true means canSend stays false for the rest of the view
            // model's life — and the model is torn down once the sheet
            // disappears, so the state never leaks to a future open.
            dismiss()
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
        let isOn = viewModel.targets.contains(platform)
        // Toggle wrapping its own label makes the entire row tappable
        // — previously only the small switch on the right edge would
        // toggle, leaving a wide dead zone across the badge + label.
        // Native iOS Settings rows behave this way and users expect it.
        return Toggle(isOn: Binding(
            get: { isOn },
            set: { newOn in
                if newOn { viewModel.targets.insert(platform) }
                else { viewModel.targets.remove(platform) }
                // SwiftUI Toggle doesn't fire UISwitch's built-in
                // selection haptic — add it manually so target toggles
                // feel like every other iOS toggle.
                HapticEngine.selection.trigger()
            }
        )) {
            HStack(spacing: 12) {
                PlatformLogoBadge(platform: platform, size: 24)
                    .opacity(isOn ? 1.0 : 0.45)
                Text(platform.accessibilityLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? Color.primary : .secondary)
            }
        }
        .accessibilityLabel("Reply on \(platform.accessibilityLabel)")
        .padding(12)
        // Soft fade reinforces which side will receive the reply.
        // Mirrors the dim treatment already used by the per-network
        // character counters below so the whole composer reads as one
        // coherent active/inactive system. Decorative — the toggle
        // state is the signal — so reduce-motion users get the
        // opacity change without the ease.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: isOn)
    }

    private var editor: some View {
        // TextEditor still has no native placeholder API, so the overlay
        // mimics one — visible only when the buffer is empty, sits behind
        // the editor so it can't intercept taps, and dims as soon as
        // typing begins.
        ZStack(alignment: .topLeading) {
            if viewModel.text.isEmpty {
                Text(editorPlaceholder)
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $viewModel.text)
                .focused($editorFocused)
                .frame(minHeight: 120)
                .padding(8)
        }
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2)))
        .accessibilityLabel("Reply text")
    }

    /// Placeholder reflects the active send policy so the empty-state hint
    /// is coherent with what the Send button actually says it'll do.
    private var editorPlaceholder: String {
        switch viewModel.sendStyle {
        case .dual: return "Reply to both networks…"
        case .mastodonOnly: return "Reply on Mastodon…"
        case .blueskyOnly: return "Reply on Bluesky…"
        case .disabled: return "Pick a network and write your reply…"
        }
    }

    private var charCounts: some View {
        HStack(spacing: 12) {
            Spacer()
            counterChip(network: "Mastodon", label: "M", value: viewModel.mastodonRemaining,
                        dimmed: !viewModel.targets.contains(.mastodon),
                        color: Color(red: 0.54, green: 0.39, blue: 1.00))
            counterChip(network: "Bluesky", label: "B", value: viewModel.blueskyRemaining,
                        dimmed: !viewModel.targets.contains(.bluesky),
                        color: Color(red: 0.00, green: 0.59, blue: 1.00))
        }
    }

    private func counterChip(network: String, label: String, value: Int, dimmed: Bool, color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2.weight(.bold))
            Text("\(value)").font(.caption2.monospacedDigit())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(dimmed ? 0.05 : 0.15), in: Capsule())
        .foregroundStyle(value < 0 ? .red : color)
        .opacity(dimmed ? 0.4 : 1.0)
        // "M 47" alone is gibberish to VoiceOver — and the visual
        // dim/red state encodes meaning a screen reader can't see.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            value < 0
                ? "\(network): over by \(-value) characters"
                : "\(network): \(value) characters remaining"
        )
    }

    private var sendButton: some View {
        Button {
            sendIfPossible()
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
        // The button's label already names the action ("Reply on
        // Mastodon" / "Reply to both"). The hint is reserved for the
        // *disabled* state — VoiceOver users who tap a dimmed button
        // get a useful, specific reason instead of dead silence.
        .accessibilityHint(sendButtonDisabledReason)
    }

    /// Empty when the button is enabled (no hint needed — the label is
    /// self-explanatory). When disabled, returns the first applicable
    /// reason in priority order so the user hears the most actionable
    /// fix first ("Select a network" before "Add text", since picking a
    /// network is necessary even for an existing draft).
    private var sendButtonDisabledReason: String {
        guard !viewModel.canSend else { return "" }
        if viewModel.isSending { return "Sending in progress." }
        if viewModel.targets.isEmpty {
            return "Select at least one network to reply on."
        }
        if viewModel.trimmedText.isEmpty {
            return "Write a reply to enable Send."
        }
        if viewModel.targets.contains(.mastodon) && viewModel.mastodonRemaining < 0 {
            let over = -viewModel.mastodonRemaining
            return "Reply is over the Mastodon limit by \(over) character\(over == 1 ? "" : "s")."
        }
        if viewModel.targets.contains(.bluesky) && viewModel.blueskyRemaining < 0 {
            let over = -viewModel.blueskyRemaining
            return "Reply is over the Bluesky limit by \(over) character\(over == 1 ? "" : "s")."
        }
        return ""
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

/// Cmd+Return → Send, Escape → Cancel. Matches the primary
/// `ComposeView` keyboard shortcut for Send so iPad and external-
/// keyboard users have one consistent "ship it" gesture for both
/// composers. Escape gives a quick exit for users who realize the
/// reply isn't going anywhere — saves a reach to the toolbar Cancel
/// button. iOS 17+; on older OSes the modifier is a no-op (toolbar
/// buttons still work).
private struct EchoComposeKeyboardShortcuts: ViewModifier {
    let canSend: Bool
    let send: () -> Void
    let cancel: () -> Void

    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content.onKeyPress { keyPress in
                if keyPress.key == .return,
                   keyPress.modifiers.contains(.command),
                   canSend {
                    send()
                    return .handled
                }
                if keyPress.key == .escape {
                    cancel()
                    return .handled
                }
                return .ignored
            }
        } else {
            content
        }
    }
}
