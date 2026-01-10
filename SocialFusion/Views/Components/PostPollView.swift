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
                Button(action: {
                    let choices = Array(selectedOptions).sorted()
                    onVote(choices)
                    hasVoted = true
                }) {
                    Text("Vote")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                }
                .disabled(selectedOptions.isEmpty)
                .accessibilityLabel("Vote")
                .accessibilityHint(selectedOptions.isEmpty ? "Select one or more options to enable voting" : "Submits your vote")
            }

            if !hasVoted && !poll.expired {
                Button(action: {
                    showsResultsOverride.toggle()
                }) {
                    Text(showsResultsOverride ? "Hide results" : "Show results")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 1)
        )
        .onChange(of: poll) { updatedPoll in
            hasVoted = updatedPoll.voted ?? false
            selectedOptions = Set(updatedPoll.ownVotes ?? [])
            if updatedPoll.voted ?? false {
                showsResultsOverride = true
            }
        }
    }

    private func formatExpirationDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
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
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                // Option text and percentage
                HStack {
                    Text(option.title)
                        .font(.body)
                        .foregroundColor(.primary)

                    Spacer()

                    if showsResults {
                        Text("\(Int(percentage * 100))%")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 8)
                            .cornerRadius(4)

                        // Progress
                        Rectangle()
                            .fill(isSelected ? Color.blue : Color(.systemGray3))
                            .frame(width: geometry.size.width * CGFloat(displayedPercentage), height: 8)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isVoted || !isInteractive)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.title)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(accessibilityHintText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var accessibilityValueText: String {
        if showsResults {
            return "\(Int(percentage * 100)) percent"
        }
        return isSelected ? "Selected" : "Not selected"
    }

    private var accessibilityHintText: String {
        guard isInteractive else { return "Voting closed" }
        if allowsMultiple {
            return isSelected ? "Double tap to deselect" : "Double tap to select"
        }
        return "Double tap to vote"
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
