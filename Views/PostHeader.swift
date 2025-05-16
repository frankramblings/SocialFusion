HStack(alignment: .firstTextBaseline, spacing: 6) {
    avatarView()
    VStack(alignment: .leading, spacing: 2) {
        Text(post.displayName)
            .font(.subheadline.weight(.semibold))
        Text(post.username)
            .font(.caption)
            .foregroundColor(.secondary)
    }
    Spacer()
    Text(post.timestamp.relativeString)
        .font(.caption2)
        .foregroundColor(.secondary)
    PlatformDot()
}
