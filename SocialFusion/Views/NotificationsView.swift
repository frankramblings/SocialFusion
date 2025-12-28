import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false
    @State private var selectedFilter: AppNotification.NotificationType? = nil
    
    var filteredNotifications: [AppNotification] {
        if let filter = selectedFilter {
            return notifications.filter { $0.type == filter }
        }
        return notifications
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter Bar
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    FilterButton(title: "All", isSelected: selectedFilter == nil) {
                        selectedFilter = nil
                    }
                    
                    ForEach([AppNotification.NotificationType.mention, .repost, .like, .follow], id: \.self) { type in
                        FilterButton(title: type.displayName, isSelected: selectedFilter == type) {
                            selectedFilter = type
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .background(Color(.systemBackground))
            .overlay(Divider(), alignment: .bottom)

            List {
                if isLoading && notifications.isEmpty {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                } else if filteredNotifications.isEmpty {
                    VStack(spacing: 20) {
                        Image(systemName: "bell.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray.opacity(0.3))
                        Text(selectedFilter == nil ? "No notifications yet" : "No \(selectedFilter!.displayName.lowercased()) notifications")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(filteredNotifications) { notification in
                        NotificationRow(notification: notification)
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle("Notifications")
        .refreshable {
            await fetchNotifications()
        }
        .onAppear {
            Task {
                await fetchNotifications()
            }
        }
    }
    
    private func fetchNotifications() async {
        isLoading = true
        do {
            notifications = try await serviceManager.fetchNotifications()
        } catch {
            print("Failed to fetch notifications: \(error)")
        }
        isLoading = false
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
                .foregroundColor(isSelected ? .blue : .primary)
                .cornerRadius(20)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
    }
}

extension AppNotification.NotificationType {
    var displayName: String {
        switch self {
        case .like: return "Likes"
        case .repost: return "Reposts"
        case .mention: return "Mentions"
        case .follow: return "Follows"
        case .poll: return "Polls"
        case .update: return "Updates"
        }
    }
}

struct NotificationRow: View {
    let notification: AppNotification
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                notificationIcon
                    .font(.system(size: 18))
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        if let avatarURL = notification.fromAccount.avatarURL, let url = URL(string: avatarURL) {
                            AsyncImage(url: url) { image in
                                image.resizable()
                            } placeholder: {
                                Circle().fill(Color.gray.opacity(0.3))
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        } else {
                            Circle().fill(Color.gray.opacity(0.3))
                                .frame(width: 32, height: 32)
                        }
                        
                        VStack(alignment: .leading) {
                            Text(notification.fromAccount.displayName ?? notification.fromAccount.username)
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text(notificationText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(notification.createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    if let post = notification.post {
                        Text(post.content)
                            .font(.system(size: 14))
                            .lineLimit(2)
                            .foregroundColor(.primary.opacity(0.8))
                            .padding(.leading, 4)
                            .overlay(
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .frame(width: 2)
                                    .padding(.leading, -4),
                                alignment: .leading
                            )
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var notificationIcon: some View {
        switch notification.type {
        case .like:
            Image(systemName: "heart.fill").foregroundColor(.red)
        case .repost:
            Image(systemName: "arrow.2.squarepath").foregroundColor(.green)
        case .mention:
            Image(systemName: "at").foregroundColor(.blue)
        case .follow:
            Image(systemName: "person.badge.plus.fill").foregroundColor(.purple)
        case .poll:
            Image(systemName: "chart.bar.fill").foregroundColor(.orange)
        case .update:
            Image(systemName: "pencil").foregroundColor(.gray)
        }
    }
    
    private var notificationText: String {
        switch notification.type {
        case .like: return "liked your post"
        case .repost: return "reposted your post"
        case .mention: return "mentioned you"
        case .follow: return "followed you"
        case .poll: return "a poll you voted in has ended"
        case .update: return "edited a post"
        }
    }
}

