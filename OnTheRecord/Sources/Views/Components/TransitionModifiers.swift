import SwiftUI

// MARK: - Slide Up Entrance

/// Animates view sliding up from below with fade
struct SlideUpEntrance: ViewModifier {
    let isPresented: Bool
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(y: isPresented ? 0 : 20)
            .animation(
                AnimationPresets.entrance.delay(delay),
                value: isPresented
            )
    }
}

// MARK: - Fade Scale Entrance

/// Animates view scaling up from smaller size with fade
struct FadeScaleEntrance: ViewModifier {
    let isPresented: Bool
    var delay: Double = 0
    var scale: CGFloat = 0.9

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented ? 1 : scale)
            .animation(
                AnimationPresets.entrance.delay(delay),
                value: isPresented
            )
    }
}

// MARK: - Slide In From Edge

/// Animates view sliding in from specified edge
struct SlideInFromEdge: ViewModifier {
    let isPresented: Bool
    let edge: Edge
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(offset)
            .animation(
                AnimationPresets.entrance.delay(delay),
                value: isPresented
            )
    }

    private var offset: CGSize {
        guard !isPresented else { return .zero }
        switch edge {
        case .top: return CGSize(width: 0, height: -30)
        case .bottom: return CGSize(width: 0, height: 30)
        case .leading: return CGSize(width: -30, height: 0)
        case .trailing: return CGSize(width: 30, height: 0)
        }
    }
}

// MARK: - Bounce Entrance

/// Animates view with bouncy spring effect
struct BounceEntrance: ViewModifier {
    let isPresented: Bool
    var delay: Double = 0

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .scaleEffect(isPresented ? 1 : 0.5)
            .animation(
                AnimationPresets.bounce.delay(delay),
                value: isPresented
            )
    }
}

// MARK: - Staggered Entrance

/// Animates views in sequence with delay based on index
struct StaggeredEntrance: ViewModifier {
    let isPresented: Bool
    let index: Int
    var baseDelay: Double = 0.05

    func body(content: Content) -> some View {
        content
            .opacity(isPresented ? 1 : 0)
            .offset(y: isPresented ? 0 : 15)
            .animation(
                AnimationPresets.staggered(index: index, baseDelay: baseDelay),
                value: isPresented
            )
    }
}

// MARK: - Shake Effect

/// Shake animation for error feedback
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0
        ))
    }
}

struct ShakeModifier: ViewModifier {
    @Binding var trigger: Bool

    @State private var shakeAmount: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(animatableData: shakeAmount))
            .onChange(of: trigger) { _, newValue in
                if newValue {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.2)) {
                        shakeAmount = 1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        shakeAmount = 0
                        trigger = false
                    }
                }
            }
    }
}

// MARK: - Pulse Effect

/// Continuous pulsing scale animation
struct PulseEffect: ViewModifier {
    let isActive: Bool
    var minScale: CGFloat = 1.0
    var maxScale: CGFloat = 1.1
    var duration: Double = 1.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                guard !reduceMotion, isActive else { return }
                withAnimation(
                    .easeInOut(duration: duration)
                    .repeatForever(autoreverses: true)
                ) {
                    scale = maxScale
                }
            }
            .onChange(of: isActive) { _, newValue in
                guard !reduceMotion else { return }
                if newValue {
                    withAnimation(
                        .easeInOut(duration: duration)
                        .repeatForever(autoreverses: true)
                    ) {
                        scale = maxScale
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        scale = minScale
                    }
                }
            }
    }
}

// MARK: - Glow Pulse Effect

/// Pulsing glow shadow animation
struct GlowPulseEffect: ViewModifier {
    let color: Color
    let isActive: Bool
    var minRadius: CGFloat = 10
    var maxRadius: CGFloat = 25

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var radius: CGFloat = 10

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.5), radius: reduceMotion ? minRadius : radius)
            .onAppear {
                guard !reduceMotion, isActive else { return }
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    radius = maxRadius
                }
            }
    }
}

// MARK: - View Extensions

extension View {
    /// Animate entrance by sliding up from below
    func slideUpEntrance(isPresented: Bool, delay: Double = 0) -> some View {
        modifier(SlideUpEntrance(isPresented: isPresented, delay: delay))
    }

    /// Animate entrance by scaling up with fade
    func fadeScaleEntrance(isPresented: Bool, delay: Double = 0, scale: CGFloat = 0.9) -> some View {
        modifier(FadeScaleEntrance(isPresented: isPresented, delay: delay, scale: scale))
    }

    /// Animate entrance from edge
    func slideInFromEdge(isPresented: Bool, edge: Edge, delay: Double = 0) -> some View {
        modifier(SlideInFromEdge(isPresented: isPresented, edge: edge, delay: delay))
    }

    /// Animate with bouncy spring
    func bounceEntrance(isPresented: Bool, delay: Double = 0) -> some View {
        modifier(BounceEntrance(isPresented: isPresented, delay: delay))
    }

    /// Animate in sequence based on index
    func staggeredEntrance(isPresented: Bool, index: Int, baseDelay: Double = 0.05) -> some View {
        modifier(StaggeredEntrance(isPresented: isPresented, index: index, baseDelay: baseDelay))
    }

    /// Luxury entrance - slower, more premium-feeling spring
    func luxuryEntrance(isPresented: Bool, delay: Double = 0) -> some View {
        self
            .opacity(isPresented ? 1 : 0)
            .offset(y: isPresented ? 0 : 15)
            .animation(
                AnimationPresets.luxuryEntrance.delay(delay),
                value: isPresented
            )
    }

    /// Shake for error feedback
    func shake(trigger: Binding<Bool>) -> some View {
        modifier(ShakeModifier(trigger: trigger))
    }

    /// Continuous pulse animation
    func pulseEffect(isActive: Bool, minScale: CGFloat = 1.0, maxScale: CGFloat = 1.1) -> some View {
        modifier(PulseEffect(isActive: isActive, minScale: minScale, maxScale: maxScale))
    }

    /// Pulsing glow shadow
    func glowPulse(color: Color, isActive: Bool) -> some View {
        modifier(GlowPulseEffect(color: color, isActive: isActive))
    }
}

// MARK: - Reduce Motion Support

extension View {
    /// Apply animation only if reduce motion is not enabled
    @ViewBuilder
    func animationIfAllowed<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self
        } else {
            self.animation(animation, value: value)
        }
    }

    /// Apply transition effect only if reduce motion is not enabled
    @ViewBuilder
    func transitionIfAllowed(_ isPresented: Bool, delay: Double = 0) -> some View {
        if UIAccessibility.isReduceMotionEnabled {
            self.opacity(isPresented ? 1 : 0)
        } else {
            self.slideUpEntrance(isPresented: isPresented, delay: delay)
        }
    }
}

// MARK: - Previews

#Preview("Transition Effects") {
    struct PreviewContainer: View {
        @State private var isShowing = false
        @State private var shouldShake = false

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    Button("Toggle") {
                        isShowing.toggle()
                    }
                    .foregroundColor(.white)

                    Button("Shake") {
                        shouldShake = true
                    }
                    .foregroundColor(.white)

                    VStack(spacing: 12) {
                        Text("Slide Up")
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(8)
                            .slideUpEntrance(isPresented: isShowing)

                        Text("Fade Scale")
                            .padding()
                            .background(Color.green)
                            .cornerRadius(8)
                            .fadeScaleEntrance(isPresented: isShowing, delay: 0.1)

                        Text("Bounce")
                            .padding()
                            .background(Color.orange)
                            .cornerRadius(8)
                            .bounceEntrance(isPresented: isShowing, delay: 0.2)

                        Text("Shake Me")
                            .padding()
                            .background(Color.red)
                            .cornerRadius(8)
                            .shake(trigger: $shouldShake)

                        Circle()
                            .fill(Colors.witnessRed)
                            .frame(width: 50, height: 50)
                            .pulseEffect(isActive: isShowing)
                            .glowPulse(color: Colors.witnessRed, isActive: isShowing)
                    }
                    .foregroundColor(.white)
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isShowing = true
                }
            }
        }
    }

    return PreviewContainer()
}
