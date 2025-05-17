import SwiftUI

/// "<user> boosted" banner with clean styling
struct BoostBanner: View {
    let handle: String

    var body: some View {
        HStack {
            Image(systemName: "arrow.2.squarepath")
                .font(.footnote)
                .foregroundColor(.secondary)

            Text("\(handle) boosted")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}

#Preview {
    VStack {
        BoostBanner(handle: "Jerry Chen")
        BoostBanner(handle: "Another User")
    }
    .padding()
    .preferredColorScheme(.dark)
}
