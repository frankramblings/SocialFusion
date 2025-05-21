import SocialFusionViewsComponents
import SwiftUI

struct ContentView: View {
    @State private var showLaunchAnimation = true
    var body: some View {
        ZStack {
            TabView {
                UnifiedTimelineView()
                    .tabItem {
                        Label("Timeline", systemImage: "list.bullet")
                    }

                ComposeView()
                    .tabItem {
                        Label("Post", systemImage: "square.and.pencil")
                    }

                AccountsView()
                    .tabItem {
                        Label("Accounts", systemImage: "person.circle")
                    }

                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
            }
            .accentColor(Color("PrimaryColor"))
            if showLaunchAnimation {
                LaunchAnimationView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .onAppear {
            if showLaunchAnimation {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    withAnimation {
                        showLaunchAnimation = false
                    }
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
