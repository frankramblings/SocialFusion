import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            // Subtle tap on page swipe — same feedback iOS gives for
            // pageable carousels in apps like Photos.
            .onChange(of: currentPage) { _, _ in
                HapticEngine.selection.trigger()
            }

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
                    // Reduce Motion drops the scale-in pop on the final
                    // CTA. The button still has an opacity transition
                    // so the swap from "Next" feels intentional.
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.95).combined(with: .opacity))
                    .accessibilityHint("Opens the add-account sheet to sign in to Mastodon or Bluesky")
                } else {
                    Button {
                        HapticEngine.tap.trigger()
                        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.82)) {
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
                    .accessibilityLabel("Next")
                    .accessibilityValue("Page \(currentPage + 1) of \(pages.count)")
                    .accessibilityHint("Advances to the next onboarding page")
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
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: currentPage)
                // When visually invisible, hide from VoiceOver too — otherwise
                // a swipe over an opacity-zero button still focuses it.
                .accessibilityHidden(currentPage == pages.count - 1)
                .accessibilityHint("Skips the rest of onboarding")
            }
        }
        .sheet(isPresented: $showingAddAccount) {
            AddAccountView()
                .environmentObject(serviceManager)
        }
    }

    private func advanceToNextPage() {
        // Selection haptic on Next/Continue so the page transition has
        // tactile feedback — paired with the visual page-dot advance.
        // Matches the haptic vocabulary already used on the Echo Policy
        // page's Continue button. Suppressed on the last page since the
        // call there is a no-op (the button there does the real action).
        if currentPage < totalPageCount - 1 {
            HapticEngine.selection.trigger()
        }
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
                .accessibilityAddTraits(.isHeader)
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
            // Hint reflects the toggle's current state so the
            // VoiceOver user knows exactly what choice they're
            // committing to — Continue with Echo on means mirror
            // replies; off means don't.
            .accessibilityHint(echoOn
                ? "Continues with replies mirrored to both networks by default."
                : "Continues with replies only on the original network by default.")

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
            .accessibilityHint("Continues without a default; the composer will ask each time.")
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
            .environmentObject(EchoPolicyStore())
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
