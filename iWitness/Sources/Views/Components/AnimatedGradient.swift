import SwiftUI

// MARK: - Animated Gradient Background

/// Slowly shifting gradient background for premium feel
struct AnimatedGradientBackground: View {
    let colors: [Color]
    var animationDuration: Double = 8.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = UnitPoint(x: 0, y: 0)
    @State private var end = UnitPoint(x: 1, y: 1)

    var body: some View {
        LinearGradient(colors: colors, startPoint: start, endPoint: end)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .easeInOut(duration: animationDuration)
                    .repeatForever(autoreverses: true)
                ) {
                    start = UnitPoint(x: 1, y: 0)
                    end = UnitPoint(x: 0, y: 1)
                }
            }
            .ignoresSafeArea()
    }
}

// MARK: - Ambient Orbs Background

/// Floating colored blur orbs for ambient depth
struct AmbientOrbsBackground: View {
    let accentColor: Color
    var intensity: Double = 0.15
    var showSecondaryOrb: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var offset1: CGSize = .zero
    @State private var offset2: CGSize = .zero
    @State private var scale1: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base dark background
                Color(white: 0.02)

                // Primary accent orb
                Circle()
                    .fill(accentColor.opacity(intensity))
                    .blur(radius: 100)
                    .frame(width: geometry.size.width * 0.8, height: geometry.size.width * 0.8)
                    .offset(offset1)
                    .scaleEffect(scale1)

                // Secondary orb (optional)
                if showSecondaryOrb {
                    Circle()
                        .fill(accentColor.opacity(intensity * 0.6))
                        .blur(radius: 80)
                        .frame(width: geometry.size.width * 0.5, height: geometry.size.width * 0.5)
                        .offset(offset2)
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 8)
                .repeatForever(autoreverses: true)
            ) {
                offset1 = CGSize(width: 40, height: -30)
                scale1 = 1.1
            }

            withAnimation(
                .easeInOut(duration: 6)
                .repeatForever(autoreverses: true)
                .delay(0.5)
            ) {
                offset2 = CGSize(width: -50, height: 60)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Premium Mesh Background (iOS 18+)

/// Mesh gradient for ultra-premium effect
struct PremiumMeshBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    private var centerX: Float { Float(0.5 + cos(phase) * 0.1) }
    private var centerY: Float { Float(0.5 + sin(phase) * 0.1) }

    var body: some View {
        if #available(iOS 18.0, *) {
            meshContent
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                        phase = .pi * 2
                    }
                }
                .ignoresSafeArea()
        } else {
            AnimatedGradientBackground(colors: [
                Color(white: 0.05),
                Color(white: 0.1),
                Color(white: 0.05)
            ])
        }
    }

    @available(iOS 18.0, *)
    private var meshContent: some View {
        let pts: [SIMD2<Float>] = [
            SIMD2(0, 0), SIMD2(0.5, 0), SIMD2(1, 0),
            SIMD2(0, 0.5), SIMD2(centerX, centerY), SIMD2(1, 0.5),
            SIMD2(0, 1), SIMD2(0.5, 1), SIMD2(1, 1)
        ]
        let cols: [Color] = [
            Color(white: 0.05), Color(white: 0.08), Color(white: 0.05),
            Color(white: 0.08), Color(white: 0.12), Color(white: 0.08),
            Color(white: 0.05), Color(white: 0.08), Color(white: 0.05)
        ]
        return MeshGradient(width: 3, height: 3, points: pts, colors: cols)
    }
}

// MARK: - Subtle Vignette Overlay

/// Dark edges vignette for focus effect
struct VignetteOverlay: View {
    var intensity: Double = 0.6
    var radius: CGFloat = 0.5

    var body: some View {
        RadialGradient(
            colors: [
                Color.clear,
                Color.black.opacity(intensity)
            ],
            center: .center,
            startRadius: UIScreen.main.bounds.width * radius,
            endRadius: UIScreen.main.bounds.width
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Success Glow Background

/// Green ambient glow for success states
struct SuccessGlowBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowIntensity: Double = 0.15

    var body: some View {
        ZStack {
            Color(.systemBackground)

            RadialGradient(
                colors: [
                    Colors.safeGreen.opacity(glowIntensity),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: UIScreen.main.bounds.width * 0.8
            )
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 2)
                .repeatForever(autoreverses: true)
            ) {
                glowIntensity = 0.2
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Dark Gradient Overlay

/// Premium dark gradient for camera overlays
struct DarkGradientOverlay: View {
    var topOpacity: Double = 0.7
    var middleOpacity: Double = 0.2
    var bottomOpacity: Double = 0.8

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color.black.opacity(topOpacity), location: 0),
                .init(color: Color.black.opacity(middleOpacity), location: 0.3),
                .init(color: Color.black.opacity(middleOpacity), location: 0.7),
                .init(color: Color.black.opacity(bottomOpacity), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Shimmer Effect

/// Subtle shimmer animation for loading states
struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    if !reduceMotion {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0),
                                Color.white.opacity(0.3),
                                Color.white.opacity(0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: geometry.size.width * 0.5)
                        .offset(x: -geometry.size.width * 0.5 + phase * geometry.size.width * 1.5)
                        .onAppear {
                            withAnimation(
                                .linear(duration: 1.5)
                                .repeatForever(autoreverses: false)
                            ) {
                                phase = 1
                            }
                        }
                    }
                }
                .mask(content)
            )
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

// MARK: - Previews

#Preview("Ambient Backgrounds") {
    TabView {
        AmbientOrbsBackground(accentColor: Colors.witnessRed)
            .overlay(
                Text("Ambient Orbs")
                    .font(.title)
                    .foregroundColor(.white)
            )
            .tabItem { Text("Orbs") }

        AnimatedGradientBackground(colors: [
            Color(white: 0.05),
            Color(white: 0.15),
            Color(white: 0.05)
        ])
        .overlay(
            Text("Animated Gradient")
                .font(.title)
                .foregroundColor(.white)
        )
        .tabItem { Text("Gradient") }

        SuccessGlowBackground()
            .overlay(
                VStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(Colors.safeGreen)
                    Text("Success!")
                        .font(.title)
                }
            )
            .tabItem { Text("Success") }

        ZStack {
            Color.gray
            DarkGradientOverlay()
            Text("Dark Overlay")
                .font(.title)
                .foregroundColor(.white)
        }
        .tabItem { Text("Overlay") }
    }
}
