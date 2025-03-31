import SwiftUI

struct ContentView: View {
    var body: some View {
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
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}