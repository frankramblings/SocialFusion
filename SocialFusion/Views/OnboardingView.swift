import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var currentPage = 0
    @State private var showingAddAccount = false
    @AppStorage("Onboarding.Completed") private var hasCompletedOnboarding = false

    // Index of the Echo Policy step in the carousel sequence.
    // Inserted between the "Unified Timeline" introduction and the
    // final "Ready to Start?" call-to-action, so the user picks an
    // echo policy before their first account / timeline reveal.
    private let echoPolicyIndex = 2

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

    /// Total page count including the inserted Echo Policy step.
    private var totalPageCount: Int { pages.count + 1 }

    /// Map a carousel index to the underlying `pages` array, accounting
    /// for the Echo Policy step inserted at `echoPolicyIndex`.
    private func pageIndex(for carouselIndex: Int) -> Int {
        carouselIndex < echoPolicyIndex ? carouselIndex : carouselIndex - 1
    }

    private var isOnEchoPolicyPage: Bool { currentPage == echoPolicyIndex }
    private var isOnLastPage: Bool { currentPage == totalPageCount - 1 }

    var body: some View {
        VStack {
            TabView(selection: $currentPage) {
                ForEach(0..<totalPageCount, id: \.self) { index in
                    Group {
                        if index == echoPolicyIndex {
                            EchoPolicyOnboardingPage(
                                onContinue: advanceToNextPage,
                                onAskEachTime: advanceToNextPage
                            )
                        } else {
                            OnboardingPageView(page: pages[pageIndex(for: index)])
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))

            // The Echo Policy page renders its own primary actions, so we
            // suppress the shared Next/Skip footer for that step.
            if !isOnEchoPolicyPage {
                VStack(spacing: 20) {
                    if isOnLastPage {
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
                        Button(action: advanceToNextPage) {
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
                    .opacity(isOnLastPage ? 0 : 1)
                }
                .padding(.bottom, 50)
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
    }

    private func advanceToNextPage() {
        withAnimation {
            if currentPage < totalPageCount - 1 {
                currentPage += 1
            }
        }
    }
}

struct EchoPolicyOnboardingPage: View {
    @EnvironmentObject var echoPolicyStore: EchoPolicyStore
    @State private var echoOn: Bool = true
    var onContinue: () -> Void
    var onAskEachTime: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            // Bloom on appear: this is the user's first encounter with the
            // signature Fused mark in onboarding. Honors reduce-motion via
            // the glyph's own internal check.
            FusedGlyph(size: 64, bloomOnAppear: true)
                .padding(.top, 40)
            Text("Echo your replies?")
                .font(.title.weight(.bold))
                .multilineTextAlignment(.center)
            Text("When you reply to a post that exists on both networks, SocialFusion can mirror your reply by default — so the conversation stays together.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            VStack {
                Toggle(isOn: Binding(
                    get: { echoOn },
                    set: { newValue in
                        echoOn = newValue
                        HapticEngine.selection.trigger()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Echo replies by default")
                            .font(.subheadline.weight(.semibold))
                        Text("Mirror to both networks when you reply to a Fused post")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                HapticEngine.success.trigger()
                echoPolicyStore.policy = echoOn ? .echoOn : .echoOff
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
                    .font(.headline)
            }
            .padding(.horizontal, 24)

            Button {
                HapticEngine.tap.trigger()
                echoPolicyStore.policy = .askEachTime
                onAskEachTime()
            } label: {
                Text("Not now — I'll choose each time")
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
            }
            .padding(.bottom, 24)
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
                // Decorative — the title text below carries the
                // semantic content. VoiceOver would otherwise announce
                // a long SF Symbol name (e.g. "list bullet rectangle
                // portrait fill") before the title that actually
                // matters.
                .accessibilityHidden(true)

            VStack(spacing: 16) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(page.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            // Combine title + description into one element so VoiceOver
            // hears the whole page intro in one swipe.
            .accessibilityElement(children: .combine)

            Spacer()
        }
    }
}

struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView()
            .environmentObject(SocialServiceManager())
            .environmentObject(EchoPolicyStore())
    }
}
