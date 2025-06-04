import SwiftUI

/// A view that displays a poll in a post
struct PostPollView: View {
    let poll: Post.Poll
    let onVote: (Int) -> Void

    @State private var selectedOption: Int?
    @State private var hasVoted: Bool

    init(poll: Post.Poll, onVote: @escaping (Int) -> Void) {
        self.poll = poll
        self.onVote = onVote
        self._hasVoted = State(initialValue: poll.voted ?? false)
        if let ownVotes = poll.ownVotes, !ownVotes.isEmpty {
            self._selectedOption = State(initialValue: ownVotes[0])
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Poll options
            ForEach(Array(poll.options.enumerated()), id: \.offset) { index, option in
                PollOptionView(
                    option: option,
                    totalVotes: poll.votesCount,
                    isSelected: selectedOption == index,
                    isVoted: hasVoted,
                    onTap: {
                        if !hasVoted && !poll.expired {
                            selectedOption = index
                            onVote(index)
                            hasVoted = true
                        }
                    }
                )
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
    let onTap: () -> Void

    private var percentage: Double {
        guard let votesCount = option.votesCount, totalVotes > 0 else { return 0 }
        return Double(votesCount) / Double(totalVotes)
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

                    if isVoted {
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
                            .frame(width: geometry.size.width * CGFloat(percentage), height: 8)
                            .cornerRadius(4)
                    }
                }
                .frame(height: 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isVoted)
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
                onVote: { _ in }
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
