import SwiftUI
import UIKit

// MARK: - True Liquid Glass Material System
/// Implementation of Apple's Liquid Glass with real-time light bending, lensing, and dynamic adaptation
/// Based on Apple's WWDC25 specifications and Human Interface Guidelines

// MARK: - Liquid Glass Environment Detection
struct LiquidGlassEnvironmentDetection {
    static var isAvailable: Bool {
        if #available(iOS 16.0, *) {
            return true
        }
        return false
    }

    static var supportsAdvancedEffects: Bool {
        // Check for device capabilities for advanced rendering
        return ProcessInfo.processInfo.processorCount >= 6
    }
}

// MARK: - Liquid Glass Material Variants
enum LiquidGlassVariant {
    case regular  // Adaptive, works everywhere
    case clear  // For media-rich content with dimming
    case floating  // For floating elements with enhanced depth
    case morphing  // For elements that change shape dynamically
}

// MARK: - Advanced Morphing States
enum MorphingState {
    case idle
    case pressed
    case expanded
    case floating
    case transitioning
}

// MARK: - Complex Liquid Glass Lensing Effect
struct AdvancedLiquidGlassLensing: ViewModifier {
    let variant: LiquidGlassVariant
    let intensity: Double
    let morphingState: MorphingState
    @State private var lightPosition: CGPoint = CGPoint(x: 0.5, y: 0.3)
    @State private var isPressed = false
    @State private var contentBrightness: Double = 0.5
    @State private var morphingScale: CGFloat = 1.0
    @State private var floatingOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(morphingScale)
            .offset(y: floatingOffset)
            .rotationEffect(.degrees(rotationAngle))
            .background(
                AdvancedLiquidGlassMaterial(
                    variant: variant,
                    lightPosition: lightPosition,
                    isPressed: isPressed,
                    contentBrightness: contentBrightness,
                    intensity: intensity,
                    morphingState: morphingState
                )
            )
            .onTapGesture { location in
                if !reduceMotion {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                        isPressed = true
                        morphingScale = 0.95
                        lightPosition = CGPoint(
                            x: location.x / UIScreen.main.bounds.width,
                            y: location.y / UIScreen.main.bounds.height
                        )
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            isPressed = false
                            morphingScale = 1.0
                        }
                    }
                }
            }
            .onAppear {
                if !reduceMotion {
                    // Use Task to defer state updates outside view rendering cycle
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                        startFloatingAnimation()
                    }
                }
            }
    }

    private func startFloatingAnimation() {
        // Only start floating animation if reduce motion is disabled
        guard !reduceMotion else { return }

        // Disable floating for tab bars to keep them stable
        // withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
        //     floatingOffset = -2
        // }

        // withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
        //     rotationAngle = 1
        // }
    }
}

// MARK: - Advanced Core Liquid Glass Material
struct AdvancedLiquidGlassMaterial: View {
    let variant: LiquidGlassVariant
    let lightPosition: CGPoint
    let isPressed: Bool
    let contentBrightness: Double
    let intensity: Double
    let morphingState: MorphingState

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    // Note: accessibilityIncreaseContrast is not available in iOS 16, using reduceTransparency as fallback

    var body: some View {
        ZStack {
            // Base material layer with morphing
            baseMaterialLayer

            // Advanced lensing and refraction layer
            if !reduceTransparency && LiquidGlassEnvironmentDetection.supportsAdvancedEffects {
                advancedLensingLayer
            }

            // Multi-layer specular highlights
            if !reduceTransparency {
                multiLayerSpecularHighlights
            }

            // Interactive glow layer with morphing
            if isPressed && !reduceTransparency {
                morphingInteractiveGlow
            }

            // Floating depth shadows
            if variant == .floating {
                floatingDepthShadows
            }

            // Adaptive shadow layer
            adaptiveShadowLayer
        }
    }

    // MARK: - Enhanced Material Layers

    private var baseMaterialLayer: some View {
        Rectangle()
            .fill(baseMaterialFill)
            .overlay(
                Rectangle()
                    .fill(adaptiveTintOverlay)
            )
            .overlay(
                // Morphing overlay based on state
                Rectangle()
                    .fill(morphingOverlay)
                    .opacity(morphingOpacity)
            )
    }

    private var advancedLensingLayer: some View {
        // Simplified lensing for better performance
        Rectangle()
            .fill(
                RadialGradient(
                    colors: primaryLensingColors,
                    center: UnitPoint(x: lightPosition.x, y: lightPosition.y),
                    startRadius: 0,
                    endRadius: 200
                )
            )
            .blendMode(.overlay)
            .opacity(lensingOpacity)
    }

    private var multiLayerSpecularHighlights: some View {
        // Simplified specular for better performance
        Rectangle()
            .fill(
                LinearGradient(
                    colors: primarySpecularColors,
                    startPoint: UnitPoint(x: lightPosition.x - 0.2, y: lightPosition.y - 0.2),
                    endPoint: UnitPoint(x: lightPosition.x + 0.2, y: lightPosition.y + 0.2)
                )
            )
            .blendMode(.softLight)
            .opacity(specularOpacity)
    }

    private var morphingInteractiveGlow: some View {
        Rectangle()
            .fill(
                RadialGradient(
                    colors: morphingGlowColors,
                    center: UnitPoint(x: lightPosition.x, y: lightPosition.y),
                    startRadius: 0,
                    endRadius: morphingGlowRadius
                )
            )
            .blendMode(.softLight)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
    }

    private var floatingDepthShadows: some View {
        Rectangle()
            .fill(Color.clear)
            .shadow(
                color: shadowColor.opacity(0.2),
                radius: shadowRadius * 1.5,
                x: 0,
                y: shadowOffset * 1.5
            )
            .shadow(
                color: shadowColor.opacity(0.1),
                radius: shadowRadius * 2,
                x: 2,
                y: shadowOffset * 2
            )
    }

    private var adaptiveShadowLayer: some View {
        Rectangle()
            .fill(Color.clear)
            .shadow(
                color: shadowColor,
                radius: shadowRadius,
                x: 0,
                y: shadowOffset
            )
    }

    // MARK: - Enhanced Adaptive Properties

    private var baseMaterialFill: Material {
        if reduceTransparency {
            return colorScheme == .dark ? .regularMaterial : .thickMaterial
        }

        switch variant {
        case .regular:
            return .ultraThinMaterial
        case .clear:
            return .thinMaterial
        case .floating:
            return .ultraThinMaterial
        case .morphing:
            return .thinMaterial
        }
    }

    private var adaptiveTintOverlay: some ShapeStyle {
        let baseOpacity = variant == .clear ? 0.02 : 0.05
        let morphingMultiplier = morphingState == .pressed ? 1.5 : 1.0
        let adaptiveOpacity =
            (contentBrightness > 0.7 ? baseOpacity * 2 : baseOpacity) * morphingMultiplier

        if colorScheme == .dark {
            return Color.white.opacity(adaptiveOpacity * intensity)
        } else {
            return Color.black.opacity(adaptiveOpacity * intensity * 0.5)
        }
    }

    private var morphingOverlay: some ShapeStyle {
        switch morphingState {
        case .pressed:
            return Color.white.opacity(0.1)
        case .expanded:
            return Color.blue.opacity(0.05)
        case .floating:
            return Color.white.opacity(0.03)
        default:
            return Color.clear
        }
    }

    private var morphingOpacity: Double {
        switch morphingState {
        case .pressed: return 1.0
        case .expanded: return 0.8
        case .floating: return 0.6
        default: return 0.0
        }
    }

    // MARK: - Enhanced Color Arrays

    private var primaryLensingColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.white.opacity(0.25),
                Color.white.opacity(0.15),
                Color.blue.opacity(0.1),
                Color.clear,
            ]
        } else {
            return [
                Color.white.opacity(0.4),
                Color.blue.opacity(0.1),
                Color.black.opacity(0.05),
                Color.clear,
            ]
        }
    }

    private var secondaryLensingColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.cyan.opacity(0.15),
                Color.blue.opacity(0.1),
                Color.clear,
            ]
        } else {
            return [
                Color.white.opacity(0.2),
                Color.blue.opacity(0.05),
                Color.clear,
            ]
        }
    }

    private var primarySpecularColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.white.opacity(0.4),
                Color.white.opacity(0.2),
                Color.clear,
                Color.black.opacity(0.1),
            ]
        } else {
            return [
                Color.white.opacity(0.6),
                Color.white.opacity(0.3),
                Color.clear,
                Color.black.opacity(0.08),
            ]
        }
    }

    private var secondarySpecularColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.white.opacity(0.2),
                Color.clear,
                Color.black.opacity(0.15),
            ]
        } else {
            return [
                Color.white.opacity(0.3),
                Color.clear,
                Color.black.opacity(0.1),
            ]
        }
    }

    private var morphingGlowColors: [Color] {
        switch morphingState {
        case .pressed:
            return [
                Color.white.opacity(0.6),
                Color.white.opacity(0.3),
                Color.blue.opacity(0.1),
                Color.clear,
            ]
        case .expanded:
            return [
                Color.blue.opacity(0.4),
                Color.blue.opacity(0.2),
                Color.white.opacity(0.1),
                Color.clear,
            ]
        default:
            return [
                Color.white.opacity(0.4),
                Color.white.opacity(0.1),
                Color.clear,
            ]
        }
    }

    // MARK: - Dynamic Properties

    private var lensingOpacity: Double {
        let baseOpacity = variant == .floating ? 0.8 : 0.6
        return baseOpacity * intensity
    }

    private var specularOpacity: Double {
        let baseOpacity = variant == .floating ? 0.9 : 0.7
        return baseOpacity * intensity
    }

    private var morphingGlowRadius: CGFloat {
        switch morphingState {
        case .pressed: return 80
        case .expanded: return 120
        case .floating: return 100
        default: return 100
        }
    }

    private var shadowColor: Color {
        if colorScheme == .dark {
            return Color.black.opacity(0.6)
        } else {
            return Color.black.opacity(0.3)
        }
    }

    private var shadowRadius: CGFloat {
        switch variant {
        case .floating: return 20
        case .morphing: return 15
        default: return 10
        }
    }

    private var shadowOffset: CGFloat {
        switch variant {
        case .floating: return 8
        case .morphing: return 6
        default: return 4
        }
    }
}

// MARK: - Floating Liquid Glass Tab Bar
struct FloatingLiquidGlassTabBar: ViewModifier {
    @State private var isPressed = false
    @State private var selectedTabScale: CGFloat = 1.0
    @State private var tabBarOffset: CGFloat = 0
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                Spacer()
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Multi-layer lensing effect
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.15),
                                        Color.blue.opacity(0.08),
                                        Color.clear,
                                    ],
                                    center: .topLeading,
                                    startRadius: 0,
                                    endRadius: 180
                                )
                            )
                            .blendMode(.overlay)
                    )
                    .overlay(
                        // Secondary lensing for depth
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color.cyan.opacity(0.12),
                                        Color.blue.opacity(0.06),
                                        Color.clear,
                                    ],
                                    center: .bottomTrailing,
                                    startRadius: 50,
                                    endRadius: 150
                                )
                            )
                            .blendMode(.softLight)
                    )
                    .overlay(
                        // Enhanced specular highlights
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.5),
                                        Color.white.opacity(0.2),
                                        Color.clear,
                                        Color.black.opacity(0.1),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.softLight)
                    )
                    .overlay(
                        // Adaptive border with gradient
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.4),
                                        Color.white.opacity(0.1),
                                        Color.clear,
                                        Color.black.opacity(0.15),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.8
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(0.2),
                        radius: 20,
                        x: 0,
                        y: 8
                    )
                    .shadow(
                        color: Color.black.opacity(0.1),
                        radius: 35,
                        x: 0,
                        y: 15
                    )
                    .frame(height: 88)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .offset(y: tabBarOffset)
                    .scaleEffect(isPressed ? 0.98 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
                    .onAppear {
                        if !reduceMotion {
                            startFloatingAnimation()
                        }
                    }
            }
        }
    }

    private func startFloatingAnimation() {
        // Only start floating animation if reduce motion is disabled
        guard !reduceMotion else { return }

        // Disable floating for tab bars to keep them stable
        // withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
        //     tabBarOffset = -3
        // }
    }
}

// MARK: - Morphing Liquid Glass Card
struct MorphingLiquidGlassCard: ViewModifier {
    @State private var isPressed = false
    @State private var isDragging = false
    @State private var dragOffset = CGSize.zero
    @State private var cardScale: CGFloat = 1.0
    @State private var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(cardScale)
            .offset(dragOffset)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Dynamic lensing based on interaction
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                RadialGradient(
                                    colors: dynamicLensingColors,
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 200
                                )
                            )
                            .blendMode(.overlay)
                            .opacity(isDragging ? 0.8 : 0.6)
                    )
                    .overlay(
                        // Morphing specular highlights
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: morphingSpecularColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .blendMode(.softLight)
                            .opacity(isDragging ? 1.0 : 0.7)
                    )
                    .overlay(
                        // Adaptive border
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(isDragging ? 0.4 : 0.2),
                                        Color.clear,
                                        Color.black.opacity(isDragging ? 0.2 : 0.1),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: isDragging ? 1.0 : 0.5
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(isDragging ? 0.25 : 0.15),
                        radius: isDragging ? 25 : 15,
                        x: dragOffset.width * 0.1,
                        y: isDragging ? 12 : 6
                    )
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)  // Require significant movement to avoid interfering with scrolling
                    .onChanged { value in
                        if !reduceMotion {
                            // Only respond to horizontal drags or very deliberate vertical drags
                            let horizontalDrag =
                                abs(value.translation.width) > abs(value.translation.height)
                            let significantDrag =
                                sqrt(
                                    pow(value.translation.width, 2)
                                        + pow(value.translation.height, 2)) > 25

                            if horizontalDrag || significantDrag {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isDragging = true
                                    dragOffset = CGSize(
                                        width: value.translation.width * 0.05,  // Reduced sensitivity
                                        height: value.translation.height * 0.02
                                    )
                                    cardScale = 1.01  // Reduced scale effect
                                    cornerRadius = 18  // Less dramatic corner change
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            isDragging = false
                            dragOffset = .zero
                            cardScale = 1.0
                            cornerRadius = 16
                        }
                    }
            )
            .onTapGesture {
                if !reduceMotion {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                        isPressed = true
                        cardScale = 0.98
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            isPressed = false
                            cardScale = 1.0
                        }
                    }
                }
            }
    }

    private var dynamicLensingColors: [Color] {
        if isDragging {
            return [
                Color.white.opacity(0.3),
                Color.blue.opacity(0.15),
                Color.cyan.opacity(0.1),
                Color.clear,
            ]
        } else {
            return [
                Color.white.opacity(0.2),
                Color.white.opacity(0.1),
                Color.clear,
            ]
        }
    }

    private var morphingSpecularColors: [Color] {
        if isDragging {
            return [
                Color.white.opacity(0.6),
                Color.white.opacity(0.3),
                Color.clear,
                Color.black.opacity(0.15),
            ]
        } else {
            return [
                Color.white.opacity(0.4),
                Color.white.opacity(0.2),
                Color.clear,
                Color.black.opacity(0.1),
            ]
        }
    }
}

// MARK: - Floating Compose Button
struct FloatingLiquidGlassComposeButton: ViewModifier {
    @State private var isPressed = false
    @State private var isHovered = false
    @State private var floatingOffset: CGFloat = 0
    @State private var rotationAngle: Double = 0
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? 0.92 : (isHovered ? 1.08 : 1.0))
            .offset(y: floatingOffset)
            .rotationEffect(.degrees(rotationAngle))
            .background(
                Group {
                    if #available(iOS 26.0, *) {
                        // SDK on CI doesn't expose glassEffect yet; use thin material as a clear-ish stand-in
                        Circle()
                            .fill(.ultraThinMaterial)
                            .background(Circle().fill(Color.black.opacity(0.18)))
                    } else {
                        Circle()
                            .fill(.ultraThinMaterial)
                            .overlay(
                                // Multi-layer lensing
                                Circle()
                                    .fill(
                                        RadialGradient(
                                            colors: [
                                                Color.white.opacity(0.4),
                                                Color.blue.opacity(0.2),
                                                Color.cyan.opacity(0.1),
                                                Color.clear,
                                            ],
                                            center: .topLeading,
                                            startRadius: 0,
                                            endRadius: 60
                                        )
                                    )
                                    .blendMode(.overlay)
                            )
                            .overlay(
                                // Enhanced specular highlights
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.7),
                                                Color.white.opacity(0.3),
                                                Color.clear,
                                                Color.black.opacity(0.1),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .blendMode(.softLight)
                            )
                            .overlay(
                                // Adaptive border
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.5),
                                                Color.clear,
                                                Color.black.opacity(0.2),
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1.0
                                    )
                            )
                            .shadow(
                                color: Color.black.opacity(0.3),
                                radius: isPressed ? 15 : 25,
                                x: 0,
                                y: isPressed ? 6 : 12
                            )
                            .shadow(
                                color: Color.black.opacity(0.15),
                                radius: isPressed ? 25 : 40,
                                x: 0,
                                y: isPressed ? 10 : 20
                            )
                    }
                }
            )
            .onTapGesture {
                if !reduceMotion {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
                        isPressed = true
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                            isPressed = false
                        }
                    }
                }
            }
            .onHover { hovering in
                if !reduceMotion {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        isHovered = hovering
                    }
                }
            }
            .onAppear {
                if !reduceMotion {
                    // Use Task to defer state updates outside view rendering cycle
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                        startFloatingAnimation()
                    }
                }
            }
    }

    private func startFloatingAnimation() {
        // Only start floating animation if reduce motion is disabled
        guard !reduceMotion else { return }

        // Disable floating for compose buttons to keep them stable
        // withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
        //     floatingOffset = -4
        // }

        // withAnimation(.easeInOut(duration: 5.0).repeatForever(autoreverses: true)) {
        //     rotationAngle = 2
        // }
    }
}

// MARK: - View Extensions for Easy Application
extension View {
    func advancedLiquidGlass(
        variant: LiquidGlassVariant = .regular,
        intensity: Double = 1.0,
        morphingState: MorphingState = .idle
    ) -> some View {
        self.modifier(
            AdvancedLiquidGlassLensing(
                variant: variant,
                intensity: intensity,
                morphingState: morphingState
            )
        )
    }

    func floatingLiquidGlassTabBar() -> some View {
        self.modifier(FloatingLiquidGlassTabBar())
    }

    func morphingLiquidGlassCard() -> some View {
        self.modifier(MorphingLiquidGlassCard())
    }

    func floatingLiquidGlassComposeButton() -> some View {
        self.modifier(FloatingLiquidGlassComposeButton())
    }
}

// MARK: - Notification Extensions
extension Notification.Name {
    static let scrollDidChange = Notification.Name("scrollDidChange")
}
