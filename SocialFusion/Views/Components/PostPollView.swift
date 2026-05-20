import SwiftUI

/// A view that displays a poll in a post
struct PostPollView: View {
    let poll: Post.Poll
    let allowsVoting: Bool
    let onVote: ([Int]) -> Void

    @State private var selectedOptions: Set<Int>
    @State private var hasVoted: Bool
    @State private var showsResultsOverride: Bool = false

    init(poll: Post.Poll, allowsVoting: Bool = false, onVote: @escaping ([Int]) -> Void) {
        self.poll = poll
        self.allowsVoting = allowsVoting
        self.onVote = onVote
        let ownVotes = poll.ownVotes ?? []
        self._hasVoted = State(initialValue: poll.voted ?? false)
        self._selectedOptions = State(initialValue: Set(ownVotes))
    }

    var body: some View {
        let showsResults = hasVoted || poll.expired || showsResultsOverride
        let isInteractive = allowsVoting && !hasVoted && !poll.expired
        VStack(alignment: .leading, spacing: 12) {
            if poll.multiple && isInteractive {
                Text(selectedOptions.isEmpty ? "Select one or more options" : "\(selectedOptions.count) selected")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .accessibilityLabel("Multiple choice poll")
                    .accessibilityValue(selectedOptions.isEmpty ? "No options selected" : "\(selectedOptions.count) selected")
            }

            // Poll options
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                PollOptionView(
                    option: option,
                    totalVotes: poll.votesCount,
                    isSelected: selectedOptions.contains(index),
                    isVoted: hasVoted,
                    showsResults: showsResults,
                    isInteractive: isInteractive,
                    allowsMultiple: poll.multiple,
                    onTap: {
                        guard isInteractive else { return }
                        if poll.multiple {
                            if selectedOptions.contains(index) {
                                selectedOptions.remove(index)
                            } else {
                                selectedOptions.insert(index)
                            }
                        } else {
                            selectedOptions = [index]
                            onVote([index])
                            hasVoted = true
                        }
                    }
                )
            }

            if poll.multiple && isInteractive {
                Button {
                    HapticEngine.success.trigger()
                    let choices = Array(selectedOptions).sorted()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        onVote(choices)
                        hasVoted = true
                    }
                } label: {
                    Text("Vote")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    selectedOptions.isEmpty
                                        ? AnyShapeStyle(Color(.systemGray4))
                                        : AnyShapeStyle(Color.accentColor.gradient)
                                )
                                .shadow(
                                    color: selectedOptions.isEmpty ? .clear : Color.accentColor.opacity(0.28),
                                    radius: 8,
                                    x: 0,
                                    y: 3
                                )
                        )
                }
                .buttonStyle(PollOptionPressStyle())
                .disabled(selectedOptions.isEmpty)
                .accessibilityLabel("Vote")
                .accessibilityHint(selectedOptions.isEmpty ? "Select one or more options to enable voting" : "Submits your vote")
            }

            if !hasVoted && !poll.expired {
                Button {
                    HapticEngine.tap.trigger()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        showsResultsOverride.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showsResultsOverride ? "eye.slash" : "eye")
                            .font(.caption.weight(.semibold))
                            .contentTransition(.symbolEffect(.replace))
                        Text(showsResultsOverride ? "Hide results" : "Show results")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show results")
                .accessibilityValue(showsResultsOverride ? "On" : "Off")
            }

            // Poll metadata
            HStack {
                Text("\(poll.votesCount) votes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if poll.expired {
                    Text("• Poll ended")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let expiresAt = poll.expiresAt {
                    Text("• Ends \(formatExpirationDate(expiresAt))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: 0.5)
        )
        .onChange(of: poll) { _, updatedPoll in
            hasVoted = updatedPoll.voted ?? false
            selectedOptions = Set(updatedPoll.ownVotes ?? [])
            if updatedPoll.voted ?? false {
                showsResultsOverride = true
            }
        }
    }

    private func formatExpirationDate(_ date: Date) -> String {
        SharedFormatters.relativeFull.localizedString(for: date, relativeTo: Date())
    }
}

/// A view that displays a single poll option
private struct PollOptionView: View {
    let option: Post.Poll.PollOption
    let totalVotes: Int
    let isSelected: Bool
    let isVoted: Bool
    let showsResults: Bool
    let isInteractive: Bool
    let allowsMultiple: Bool
    let onTap: () -> Void

    private var percentage: Double {
        guard let votesCount = option.votesCount, totalVotes > 0 else { return 0 }
        return Double(votesCount) / Double(totalVotes)
    }
    
    private var displayedPercentage: Double {
        showsResults ? percentage : 0
    }

    var body: some View {
        Button {
            HapticEngine.selection.trigger()
            onTap()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                PollSelectionIndicator(
                    isSelected: isSelected,
                    isInteractive: isInteractive,
                    allowsMultiple: allowsMultiple
                )
                VStack(alignment: .leading, spacing: 6) {
                    // Option text and percentage
                    HStack {
                        Text(option.title)
                            .font(.body)
                            .foregroundColor(.primary)

                        Spacer()

                        if showsResults {
                            Text("\(Int(percentage * 100))%")
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                                .contentTransition(.numericText(value: percentage))
                                .animation(.easeOut(duration: 0.5), value: percentage)
                                .transition(.opacity)
                        }
                    }

                    // Progress bar — animates from 0 to the actual percentage
                    // when results become visible, giving a satisfying "reveal"
                    // moment after voting.
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule(style: .continuous)
                                .fill(Color(.systemGray5))
                                .frame(height: 8)

                            Capsule(style: .continuous)
                                .fill(
                                    isSelected
                                        ? AnyShapeStyle(Color.accentColor.gradient)
                                        : AnyShapeStyle(Color(.systemGray3))
                                )
                                .frame(
                                    width: max(0, geometry.size.width * CGFloat(displayedPercentage)),
                                    height: 8
                                )
                                .animation(.spring(response: 0.6, dampingFraction: 0.82), value: displayedPercentage)
                        }
                    }
                    .frame(height: 8)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selectionBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selectionBorder, lineWidth: isVoted && isSelected ? 1.5 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isSelected)
        }
        .buttonStyle(PollOptionPressStyle())
        .disabled(isVoted || !isInteractive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityValueText: String {
        if showsResults {
            let percent = Int(percentage * 100)
            return isSelected ? "Selected, \(percent) percent" : "\(percent) percent"
        }
        return isSelected ? "Selected" : "Not selected"
    }

    private var accessibilityHintText: String {
        guard isInteractive else { return "Voting has closed" }
        if allowsMultiple {
            return isSelected ? "Removes from your selection" : "Adds to your selection"
        }
        return "Casts your vote"
    }

    private var selectionBackground: Color {
        guard isVoted && isSelected else { return Color.clear }
        return Color.accentColor.opacity(0.12)
    }

    private var selectionBorder: Color {
        guard isVoted && isSelected else { return Color(.systemGray5) }
        return Color.accentColor.opacity(0.6)
    }
}

/// Subtle press feedback for poll options — they're large tappable rows, so
/// a small scale-down + dim reads as a tap acknowledgement without
/// overpowering the result-reveal animation.
private struct PollOptionPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

private struct PollSelectionIndicator: View {
    let isSelected: Bool
    let isInteractive: Bool
    let allowsMultiple: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(borderColor, lineWidth: 2)
                .background(Circle().fill(fillColor))
                .frame(width: 20, height: 20)

            if isSelected {
                Image(systemName: allowsMultiple ? "checkmark" : "circle.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .accessibilityHidden(true)
    }

    private var fillColor: Color {
        isSelected ? Color.accentColor : Color.clear
    }

    private var borderColor: Color {
        guard isInteractive || isSelected else { return Color(.systemGray4) }
        return isSelected ? Color.accentColor : Color(.systemGray3)
    }
}

// MARK: - Preview
struct PostPollView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Active poll
            PostPollView(
                poll: Post.Poll(
                    id: "1",
                    expiresAt: Date().addingTimeInterval(86400),
                    expired: false,
                    multiple: false,
                    votesCount: 100,
                    votersCount: 50,
                    voted: false,
                    ownVotes: nil,
                    options: [
                        Post.Poll.PollOption(title: "Option 1", votesCount: 40),
                        Post.Poll.PollOption(title: "Option 2", votesCount: 60),
                    ]
                ),
                allowsVoting: false,
                onVote: { _ in }
            )

            // Expired poll
            PostPollView(
                poll: Post.Poll(
                    id: "2",
                    expiresAt: Date().addingTimeInterval(-86400),
                    expired: true,
                    multiple: false,
                    votesCount: 200,
                    votersCount: 100,
                    voted: true,
                    ownVotes: [0],
                    options: [
                        Post.Poll.PollOption(title: "Option 1", votesCount: 80),
                        Post.Poll.PollOption(title: "Option 2", votesCount: 120),
                    ]
                ),
                allowsVoting: false,
                onVote: { _ in }
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
