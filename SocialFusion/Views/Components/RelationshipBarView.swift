import SwiftUI

/// Relationship Bar component for profile screens
/// Displays Follow/Mute/Block controls with state-aware UI
struct RelationshipBarView: View {
  @ObservedObject var viewModel: RelationshipViewModel
  @State private var showBlockConfirmation = false
  @State private var showFollowingActionSheet = false
  @State private var showRequestedActionSheet = false
  
  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 12) {
        // Secondary actions (left side)
        if !viewModel.state.isBlocking {
          // Mute toggle
          Button(action: {
            Task {
              if viewModel.state.isMuting {
                await viewModel.unmute()
              } else {
                await viewModel.mute()
              }
            }
          }) {
            Image(systemName: viewModel.state.isMuting ? "speaker.slash.fill" : "speaker.slash")
              .font(.system(size: 18))
              .foregroundColor(viewModel.state.isMuting ? .red : .primary)
              .frame(width: 44, height: 44)
              .background(Color(.secondarySystemBackground))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
          
          // Block button
          Button(action: {
            showBlockConfirmation = true
          }) {
            Image(systemName: "hand.raised")
              .font(.system(size: 18))
              .foregroundColor(.red)
              .frame(width: 44, height: 44)
              .background(Color(.secondarySystemBackground))
              .clipShape(Circle())
          }
          .buttonStyle(.plain)
        } else {
          // Blocked state: show "Blocked" pill
          HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
              .font(.system(size: 14))
            Text("Blocked")
              .font(.subheadline)
              .fontWeight(.medium)
          }
          .foregroundColor(.red)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color.red.opacity(0.1))
          .clipShape(Capsule())
        }
        
        Spacer()
        
        // Primary action (right side)
        if viewModel.state.isBlocking {
          // Unblock button
          Button(action: {
            Task {
              await viewModel.unblock()
            }
          }) {
            Text("Unblock")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundColor(.red)
              .padding(.horizontal, 20)
              .padding(.vertical, 10)
              .background(Color(.secondarySystemBackground))
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        } else if viewModel.state.followRequested {
          // Requested state
          Button(action: {
            showRequestedActionSheet = true
          }) {
            Text("Requested")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundColor(.primary)
              .padding(.horizontal, 20)
              .padding(.vertical, 10)
              .background(Color(.secondarySystemBackground))
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        } else if viewModel.state.isFollowing {
          // Following state
          Button(action: {
            showFollowingActionSheet = true
          }) {
            Text("Following")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundColor(.primary)
              .padding(.horizontal, 20)
              .padding(.vertical, 10)
              .background(Color(.secondarySystemBackground))
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        } else {
          // Not following - Follow button
          Button(action: {
            Task {
              await viewModel.follow()
            }
          }) {
            Text("Follow")
              .font(.subheadline)
              .fontWeight(.semibold)
              .foregroundColor(.white)
              .padding(.horizontal, 20)
              .padding(.vertical, 10)
              .background(Color.accentColor)
              .clipShape(Capsule())
          }
          .buttonStyle(.plain)
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(Color(.systemBackground))
      
      // Relationship indicators
      if viewModel.state.isFollowedBy || viewModel.state.isMutual {
        HStack(spacing: 8) {
          if viewModel.state.isMutual {
            Text("Mutuals")
              .font(.caption)
              .fontWeight(.medium)
              .foregroundColor(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color(.secondarySystemBackground))
              .clipShape(Capsule())
          } else if viewModel.state.isFollowedBy {
            Text("Follows you")
              .font(.caption)
              .fontWeight(.medium)
              .foregroundColor(.secondary)
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .background(Color(.secondarySystemBackground))
              .clipShape(Capsule())
          }
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
      }
    }
    .confirmationDialog(
      "Block this user?",
      isPresented: $showBlockConfirmation,
      titleVisibility: .visible
    ) {
      Button("Block", role: .destructive) {
        Task {
          await viewModel.block()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("They won't be able to follow you or see your posts.")
    }
    .confirmationDialog(
      "Unfollow",
      isPresented: $showFollowingActionSheet,
      titleVisibility: .visible
    ) {
      Button("Unfollow", role: .destructive) {
        Task {
          await viewModel.unfollow()
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("You will no longer see their posts in your timeline.")
    }
    .confirmationDialog(
      "Cancel Request",
      isPresented: $showRequestedActionSheet,
      titleVisibility: .visible
    ) {
      Button("Cancel Request", role: .destructive) {
        Task {
          await viewModel.unfollow()
        }
      }
      Button("Keep Request", role: .cancel) {}
    } message: {
      Text("Cancel your follow request?")
    }
  }
}
