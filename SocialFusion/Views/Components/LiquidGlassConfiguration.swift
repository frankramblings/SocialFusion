import SwiftUI
import UIKit

// MARK: - Liquid Glass Configuration
/// Central configuration for Liquid Glass implementation in SocialFusion
/// Ensures consistent application of Liquid Glass principles across iOS 16+

struct LiquidGlassConfiguration {

    // MARK: - Feature Availability
    static var isLiquidGlassAvailable: Bool {
        if #available(iOS 16.0, *) {
            return true
        }
        return false
    }

    // MARK: - Material Hierarchy Configuration
    struct Materials {
        static let navigation: Material = .ultraThin
        static let tabBar: Material = .ultraThin
        static let cards: Material = .ultraThin
        static let overlays: Material = .ultraThin
        static let buttons: Material = .ultraThin
        static let badges: Material = .ultraThin
        static let mediaControls: Material = .ultraThin
    }

    // MARK: - Visual Properties
    struct VisualProperties {
        static let defaultCornerRadius: CGFloat = 12
        static let cardCornerRadius: CGFloat = 16
        static let buttonCornerRadius: CGFloat = 12
        static let badgeCornerRadius: CGFloat = 8

        static let defaultShadowRadius: CGFloat = 2
        static let cardShadowRadius: CGFloat = 1
        static let overlayShadowRadius: CGFloat = 4

        static let borderOpacity: Double = 0.08
        static let strokeOpacity: Double = 0.1
        static let shadowOpacity: Double = 0.05
    }

    // MARK: - Animation Configuration
    struct Animations {
        static let defaultSpring = Animation.spring(response: 0.3, dampingFraction: 0.7)
        static let buttonPress = Animation.spring(response: 0.25, dampingFraction: 0.7)
        static let cardTransition = Animation.easeInOut(duration: 0.3)
        static let overlayTransition = Animation.easeInOut(duration: 0.2)
    }

    // MARK: - Setup Methods
    static func configureAppearance() {
        guard isLiquidGlassAvailable else { return }

        // Configure navigation bar appearance
        configureNavigationBarAppearance()

        // Configure tab bar appearance
        configureTabBarAppearance()

        // Configure other UI elements
        configureUIElementAppearance()
    }

    private static func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()

        // Apply to all navigation bars
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()

        // Configure tab bar item appearance for Liquid Glass effect
        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = UIColor.secondaryLabel
        itemAppearance.normal.titleTextAttributes = [
            .foregroundColor: UIColor.secondaryLabel,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium),
        ]
        itemAppearance.selected.iconColor = UIColor.tintColor
        itemAppearance.selected.titleTextAttributes = [
            .foregroundColor: UIColor.tintColor,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold),
        ]

        appearance.stackedLayoutAppearance = itemAppearance
        appearance.inlineLayoutAppearance = itemAppearance
        appearance.compactInlineLayoutAppearance = itemAppearance

        // Apply to all tab bars
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }

        // Additional tab bar styling
        UITabBar.appearance().backgroundColor = UIColor.clear
        UITabBar.appearance().isTranslucent = true
    }

    private static func configureUIElementAppearance() {
        // Additional UI element configurations can be added here
        // For example, table view cells, collection view cells, etc.
    }
}

// MARK: - Liquid Glass Environment
struct LiquidGlassEnvironment: EnvironmentKey {
    static let defaultValue: Bool = LiquidGlassConfiguration.isLiquidGlassAvailable
}

extension EnvironmentValues {
    var isLiquidGlassEnabled: Bool {
        get { self[LiquidGlassEnvironment.self] }
        set { self[LiquidGlassEnvironment.self] = newValue }
    }
}

// MARK: - Conditional Liquid Glass Modifier
struct ConditionalLiquidGlassModifier: ViewModifier {
    let enabled: Bool
    let prominence: Material
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if enabled && LiquidGlassConfiguration.isLiquidGlassAvailable {
            content
                .advancedLiquidGlass(variant: .regular, intensity: 0.8, morphingState: .idle)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color(.systemBackground))
                        .shadow(color: .black.opacity(0.1), radius: 1, x: 0, y: 0.5)
                )
        }
    }
}

// MARK: - Liquid Glass App Modifier
struct LiquidGlassAppModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .environment(\.isLiquidGlassEnabled, LiquidGlassConfiguration.isLiquidGlassAvailable)
            .onAppear {
                LiquidGlassConfiguration.configureAppearance()
            }
    }
}

// MARK: - Liquid Glass Navigation Layout Modifier
/// Ensures proper edge-to-edge content experience with Liquid Glass navigation
struct LiquidGlassNavigationLayoutModifier: ViewModifier {
    let extendUnderNavigation: Bool
    let maintainReadability: Bool

    func body(content: Content) -> some View {
        if LiquidGlassConfiguration.isLiquidGlassAvailable {
            content
                .toolbarBackground(.clear, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .background(
                    // Background extension effect for edge-to-edge experience
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea(edges: extendUnderNavigation ? .top : [])
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    if #available(iOS 26.0, *) {
                        // Native clear glass overlay behind the nav bar area
                        Rectangle()
                            .fill(.clear)
                            .glassEffect(.clear)
                            .background(Color.black.opacity(0.12))
                            .frame(height: 52)
                            .ignoresSafeArea(edges: .top)
                    } else if maintainReadability && extendUnderNavigation {
                        // Ensure content readability with subtle gradient overlay
                        LinearGradient(
                            colors: [
                                Color(.systemGroupedBackground).opacity(0.8),
                                Color(.systemGroupedBackground).opacity(0.4),
                                Color.clear,
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 20)
                        .allowsHitTesting(false)
                    } else {
                        Color.clear.frame(height: 0)
                    }
                }
        } else {
            // Fallback for non-Liquid Glass devices
            content
                .navigationBarTitleDisplayMode(.inline)
                .background(Color(.systemGroupedBackground))
        }
    }
}

// MARK: - Floating Liquid Glass Navigation Modifier
/// Creates floating navigation elements with proper Liquid Glass effects
struct FloatingLiquidGlassNavigationModifier: ViewModifier {
    let allowContentUnderNavigation: Bool

    func body(content: Content) -> some View {
        if LiquidGlassConfiguration.isLiquidGlassAvailable {
            content
                .background(
                    // Edge-to-edge background for content to flow under navigation
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea(.all)
                )
                .toolbarBackground(.clear, for: .navigationBar)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Custom floating navigation elements
                    ToolbarItem(placement: .principal) {
                        // Floating title with Liquid Glass effect
                        Text("Post")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(.ultraThinMaterial)
                                    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                            )
                            .advancedLiquidGlass(
                                variant: .floating,
                                intensity: 0.9,
                                morphingState: .floating
                            )
                    }
                }
        } else {
            // Fallback for non-Liquid Glass devices
            content
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .background(Color(.systemGroupedBackground))
        }
    }
}

extension View {
    func conditionalLiquidGlass(
        enabled: Bool = true,
        prominence: Material = .ultraThin,
        cornerRadius: CGFloat = 12
    ) -> some View {
        self.modifier(
            ConditionalLiquidGlassModifier(
                enabled: enabled,
                prominence: prominence,
                cornerRadius: cornerRadius
            )
        )
    }

    /// Applies proper Liquid Glass navigation layout with edge-to-edge content experience
    func liquidGlassNavigationLayout(
        extendUnderNavigation: Bool = false,
        maintainReadability: Bool = true
    ) -> some View {
        self.modifier(
            LiquidGlassNavigationLayoutModifier(
                extendUnderNavigation: extendUnderNavigation,
                maintainReadability: maintainReadability
            )
        )
    }

    /// Creates floating Liquid Glass navigation elements for modern iOS design
    func floatingLiquidGlassNavigation(
        allowContentUnderNavigation: Bool = true
    ) -> some View {
        self.modifier(
            FloatingLiquidGlassNavigationModifier(
                allowContentUnderNavigation: allowContentUnderNavigation
            )
        )
    }

    func enableLiquidGlass() -> some View {
        self.modifier(LiquidGlassAppModifier())
    }

    /// Applies a clear glass tab bar background on iOS 26+, with graceful fallback.
    func clearGlassTabBar() -> some View {
        self.modifier(ClearGlassTabBarModifier())
    }
}

// MARK: - Debug Information
#if DEBUG
    struct LiquidGlassDebugInfo: View {
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("Liquid Glass Debug Info")
                    .font(.headline)

                Text("Available: \(LiquidGlassConfiguration.isLiquidGlassAvailable ? "Yes" : "No")")
                Text("iOS Version: \(UIDevice.current.systemVersion)")
                Text("Deployment Target: iOS 16.0+")

                if LiquidGlassConfiguration.isLiquidGlassAvailable {
                    Text("✅ Liquid Glass is enabled")
                        .foregroundColor(.green)
                } else {
                    Text("❌ Liquid Glass is not available")
                        .foregroundColor(.red)
                }
            }
            .padding()
            .advancedLiquidGlass(variant: .regular, intensity: 0.8, morphingState: .idle)
        }
    }

    struct LiquidGlassDebugInfo_Previews: PreviewProvider {
        static var previews: some View {
            LiquidGlassDebugInfo()
                .padding()
        }
    }
#endif

// MARK: - Clear Glass Tab Bar Modifier
private struct ClearGlassTabBarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbarBackground(.clear, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}
