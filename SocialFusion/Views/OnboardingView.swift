import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var currentPage = 0
    @State private var showingAddAccount = false
    @AppStorage("Onboarding.Completed") private var hasCompletedOnboarding = false
    
    let pages = [
        OnboardingPage(
            title: "Welcome to SocialFusion",
            description: "A streamlined, modern native social media aggregator for Mastodon and Bluesky.",
            imageName: "globe.americas.fill",
            color: .blue
        ),
        OnboardingPage(
            title: "Unified Timeline",
            description: "View all your social feeds in one place, or filter by platform and account.",
            imageName: "list.bullet.rectangle.portrait.fill",
            color: .purple
        ),
        OnboardingPage(
            title: "Ready to Start?",
            description: "Add your first account to begin your journey with SocialFusion.",
            imageName: "person.badge.plus.fill",
            color: .green
        )
    ]
    
    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<pages.count, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
            
            VStack(spacing: 20) {
                if currentPage == pages.count - 1 {
                    Button(action: {
                        showingAddAccount = true
                    }) {
                        Text("Add Your First Account")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                    .transition(.scale.combined(with: .opacity))
                } else {
                    Button(action: {
                        withAnimation {
                            currentPage += 1
                        }
                    }) {
                        Text("Next")
                            .font(.headline)
                            .foregroundColor(.blue)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal, 40)
                }
                
                Button(action: {
                    hasCompletedOnboarding = true
                }) {
                    Text("Skip")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .opacity(currentPage == pages.count - 1 ? 0 : 1)
            }
            .padding(.bottom, 50)
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
    }
}

struct OnboardingPage {
    let title: String
    let description: String
    let imageName: String
    let color: Color
}

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            Image(systemName: page.imageName)
                .font(.system(size: 120))
                .foregroundColor(page.color)
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Spacer()
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(SocialServiceManager())
    }
}
