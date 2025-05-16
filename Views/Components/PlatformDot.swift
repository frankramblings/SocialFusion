import SwiftUI

/// Small purple indicator dot in headers.
struct PlatformDot: View {
    var body: some View {
        Circle()
            .fill(Color.accentPurple)
            .frame(width: 6, height: 6)
    }
}
