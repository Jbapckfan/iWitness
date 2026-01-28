import SwiftUI

// MARK: - Glass Card Component

/// A premium glass-morphism card with frosted material background
struct GlassCard<Content: View>: View {
    let content: Content
    var material: Material
    var cornerRadius: CGFloat
    var padding: CGFloat

    init(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = Spacing.Radius.lg,
        padding: CGFloat = Spacing.cardPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.material = material
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Colors.Gradients.glassBorder, lineWidth: 0.5)
            )
            .elevation(Elevation.low)
    }
}

// MARK: - Glass Card Modifier

/// ViewModifier for applying glass card styling to existing views
struct GlassCardModifier: ViewModifier {
    var material: Material
    var cornerRadius: CGFloat
    var padding: CGFloat
    var showBorder: Bool

    init(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = Spacing.Radius.lg,
        padding: CGFloat = Spacing.cardPadding,
        showBorder: Bool = true
    ) {
        self.material = material
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.showBorder = showBorder
    }

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        showBorder ? Colors.Gradients.glassBorder : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom),
                        lineWidth: 0.5
                    )
            )
            .elevation(Elevation.low)
    }
}

extension View {
    /// Apply glass card styling with material background and subtle border
    func glassCard(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = Spacing.Radius.lg,
        padding: CGFloat = Spacing.cardPadding,
        showBorder: Bool = true
    ) -> some View {
        modifier(GlassCardModifier(
            material: material,
            cornerRadius: cornerRadius,
            padding: padding,
            showBorder: showBorder
        ))
    }

    /// Apply minimal glass background without padding
    func glassBackground(
        material: Material = .ultraThinMaterial,
        cornerRadius: CGFloat = Spacing.Radius.lg
    ) -> some View {
        self
            .background(material, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Colors.Gradients.glassBorder, lineWidth: 0.5)
            )
    }
}

// MARK: - Glass Capsule

/// A glass-styled capsule for status indicators and tags
struct GlassCapsule<Content: View>: View {
    let content: Content
    var material: Material
    var horizontalPadding: CGFloat
    var verticalPadding: CGFloat

    init(
        material: Material = .ultraThinMaterial,
        horizontalPadding: CGFloat = Spacing.md,
        verticalPadding: CGFloat = Spacing.xs,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.material = material
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    var body: some View {
        content
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(material, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Colors.Gradients.glassBorder, lineWidth: 0.5)
            )
    }
}

// MARK: - Tinted Glass Card

/// A glass card with a subtle color tint
struct TintedGlassCard<Content: View>: View {
    let content: Content
    let tintColor: Color
    var tintOpacity: Double
    var cornerRadius: CGFloat
    var padding: CGFloat

    init(
        tintColor: Color,
        tintOpacity: Double = 0.1,
        cornerRadius: CGFloat = Spacing.Radius.lg,
        padding: CGFloat = Spacing.cardPadding,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.tintColor = tintColor
        self.tintOpacity = tintOpacity
        self.cornerRadius = cornerRadius
        self.padding = padding
    }

    var body: some View {
        content
            .padding(padding)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(tintColor.opacity(tintOpacity))
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [tintColor.opacity(0.3), tintColor.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .elevation(Elevation.low)
    }
}

// MARK: - Previews

#Preview("Glass Card") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Glass Card")
                        .font(Typography.headline2)
                    Text("Premium frosted glass effect")
                        .font(Typography.bodyMedium)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TintedGlassCard(tintColor: Colors.safeGreen) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Colors.safeGreen)
                    Text("Ready")
                        .font(Typography.bodyLarge)
                    Spacer()
                }
            }

            GlassCapsule {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Colors.witnessRed)
                        .frame(width: 8, height: 8)
                    Text("RECORDING")
                        .font(Typography.label)
                }
                .foregroundColor(.white)
            }
        }
        .padding()
    }
}
