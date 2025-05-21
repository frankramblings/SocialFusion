import SwiftUI

/// A lightweight launch-screen animation that echoes the SocialFusion app icon.
/// Place this view as the very first screen after the static LaunchScreen storyboard.
/// – Two circles begin slightly apart (±52 pt) and ease inward to ±4 pt.
/// – A cyan bloom sitting in the overlap fades from 0 → 1 opacity over the same 0.6 s.
/// The total animation is subtle enough to feel native but long enough to be perceived.

struct LaunchAnimationView: View {
    // Animation trigger
    @State private var fuse = false

    // MARK: – Geometry
    private let circleSize: CGFloat = 160
    private let startOffset: CGFloat = 52  // how far apart circles start
    private let endOffset: CGFloat = 4  // final offset so they still read as two bodies

    // MARK: – Colours (match the icon spec)
    private let mastodonPurple = Color(red: 0.54, green: 0.39, blue: 1.00)  // #8A63FF
    private let blueskyBlue = Color(red: 0.00, green: 0.59, blue: 1.00)  // #0096FF
    private let lensCyan = Color(red: 0.12, green: 0.91, blue: 1.00)  // #1EE7FF

    var body: some View {
        ZStack {
            // -- Background -----
            Color("LaunchBackground")  // Use a colour in Assets (e.g. #0A0C24 in dark / #D9F0FF in light)
                .ignoresSafeArea()

            // -- Circles -----
            Circle()
                .fill(mastodonPurple)
                .frame(width: circleSize, height: circleSize)
                .offset(x: fuse ? -endOffset : -startOffset)

            Circle()
                .fill(blueskyBlue)
                .frame(width: circleSize, height: circleSize)
                .offset(x: fuse ? endOffset : startOffset)

            // -- Lens bloom -----
            Circle()
                .fill(lensCyan)
                .frame(width: circleSize * 0.62)
                .opacity(fuse ? 1 : 0)
                .blur(radius: fuse ? 18 : 2)
                .animation(.easeOut(duration: 0.6), value: fuse)
        }
        .onAppear {
            // Delay a single frame so the view draws its initial state first
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.6)) {
                    fuse = true
                }
            }
        }
    }
}

// MARK: – Preview -------------------------------------------------------------
#if DEBUG
    struct LaunchAnimationView_Previews: PreviewProvider {
        static var previews: some View {
            LaunchAnimationView()
                .previewDisplayName("Launch animation – dark")
                .environment(\.colorScheme, .dark)
            LaunchAnimationView()
                .previewDisplayName("Launch animation – light")
                .environment(\.colorScheme, .light)
        }
    }
#endif
