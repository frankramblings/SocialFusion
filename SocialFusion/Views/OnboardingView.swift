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
                    Button {
                        HapticEngine.tap.trigger()
                        showingAddAccount = true
                    } label: {
                        Text("Add Your First Account")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.accentColor.gradient)
                                    .shadow(color: Color.accentColor.opacity(0.35), radius: 12, x: 0, y: 4)
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 40)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                } else {
                    Button {
                        HapticEngine.tap.trigger()
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                            currentPage += 1
                        }
                    } label: {
                        Text("Next")
                            .font(.headline)
                            .foregroundColor(.accentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.12))
                            )
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 40)
                }

                Button {
                    HapticEngine.tap.trigger()
                    hasCompletedOnboarding = true
                } label: {
                    Text("Skip")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .opacity(currentPage == pages.count - 1 ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: currentPage)
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

    @State private var iconAppeared = false
    @State private var titleAppeared = false
    @State private var bodyAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Iconography — tinted halo behind the symbol gives it presence,
            // and the symbol pulses gently on iOS 17+
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                page.color.opacity(0.22),
                                page.color.opacity(0.0),
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 110
                        )
                    )
                    .frame(width: 220, height: 220)

                Image(systemName: page.imageName)
                    .font(.system(size: 96, weight: .light))
                    .foregroundStyle(page.color.gradient)
                    .apply { view in
                        if #available(iOS 17.0, *) {
                            view.symbolEffect(.pulse.byLayer, options: .repeating, value: iconAppeared)
                        } else {
                            view
                        }
                    }
            }
            .scaleEffect(iconAppeared ? 1.0 : 0.85)
            .opacity(iconAppeared ? 1 : 0)

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(.largeTitle, design: .default).weight(.bold))
                    .multilineTextAlignment(.center)
                    .opacity(titleAppeared ? 1 : 0)
                    .offset(y: titleAppeared ? 0 : 12)

                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.horizontal, 40)
                    .opacity(bodyAppeared ? 1 : 0)
                    .offset(y: bodyAppeared ? 0 : 10)
            }

            Spacer()
        }
        // The page is a single editorial unit — combine the icon,
        // title, and description so VoiceOver reads it as one
        // utterance ('<title>, <description>') rather than three
        // separate stops.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(page.title). \(page.description)")
        .onAppear {
            runEntrance()
        }
    }

    private func runEntrance() {
        if reduceMotion {
            iconAppeared = true
            titleAppeared = true
            bodyAppeared = true
            return
        }
        // Staggered choreography — feels alive without being showy
        withAnimation(.spring(response: 0.6, dampingFraction: 0.78)) {
            iconAppeared = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                titleAppeared = true
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                bodyAppeared = true
            }
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(SocialServiceManager())
    }
}

/// A subtle scale-down on press — the kind of tactile feedback Apple's own
/// system buttons provide. Used for primary onboarding CTAs.
struct PressableButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(
                .interactiveSpring(response: 0.25, dampingFraction: 0.8),
                value: configuration.isPressed
            )
    }
}
