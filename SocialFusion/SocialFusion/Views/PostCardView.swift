import SwiftUI

struct PostCardView: View {
    static var customCardBackground: Color {
        Color("CardBackground")
    }

    var body: some View {
        // ... existing code ...
        .fill(Color.customCardBackground)
        // ... existing code ...
    }
}

struct PostCardView_Previews: PreviewProvider {
    static var previews: some View {
        PostCardView()
    }
}
