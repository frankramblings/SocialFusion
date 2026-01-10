import SwiftUI

struct IntegrationExampleView: View {
    let post: Post

    var body: some View {
        HStack {
            Button("Open") { post.openInBrowser() }
            Button("Copy") { post.copyLink() }
            Button("Share") { post.presentShareSheet() }
        }
    }
}
