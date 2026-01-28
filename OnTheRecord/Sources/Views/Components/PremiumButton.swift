import SwiftUI

// MARK: - Premium Press Style

/// Button style that tracks press state for visual feedback
struct PremiumPressStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, newValue in
                withAnimation(AnimationPresets.micro) {
                    isPressed = newValue
                }
            }
    }
}

// MARK: - Premium Primary Button

/// Primary action button with glow effect - for main CTAs
struct PremiumPrimaryButton: View {
    let title: String
    var subtitle: String?
    var icon: String?
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            action()
        }) {
            HStack(spacing: Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Typography.headline3)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Typography.caption)
                            .opacity(0.9)
                    }
                }

                Spacer()

                if subtitle != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .bold))
                        .opacity(0.6)
                }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, subtitle != nil ? Spacing.md : Spacing.md + 2)
            .background(
                RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                    .fill(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .shadow(
                color: color.opacity(isPressed ? 0.5 : 0.35),
                radius: isPressed ? 16 : 12,
                y: isPressed ? 2 : 4
            )
        }
        .buttonStyle(PremiumPressStyle(isPressed: $isPressed))
    }
}

// MARK: - Premium Secondary Button

/// Secondary/outline button - for alternative actions
struct PremiumSecondaryButton: View {
    let title: String
    var subtitle: String?
    var icon: String?
    let color: Color
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            HStack(spacing: Spacing.sm) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold))

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Typography.caption)
                            .opacity(0.8)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .opacity(0.6)
            }
            .foregroundColor(color)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                    .fill(color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Spacing.Radius.lg)
                    .stroke(color.opacity(0.5), lineWidth: 2)
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
        }
        .buttonStyle(PremiumPressStyle(isPressed: $isPressed))
    }
}

// MARK: - Glass Button

/// Small glass-style button for overlays and toolbars
struct GlassButton: View {
    let title: String
    var icon: String?
    var iconOnly: Bool = false
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            HStack(spacing: Spacing.xxs) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: iconOnly ? 16 : 14, weight: .semibold))
                }
                if !iconOnly {
                    Text(title)
                        .font(Typography.label)
                }
            }
            .foregroundColor(.white)
            .padding(.horizontal, iconOnly ? Spacing.sm : Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            )
            .scaleEffect(isPressed ? 0.95 : 1.0)
        }
        .buttonStyle(PremiumPressStyle(isPressed: $isPressed))
    }
}

// MARK: - Icon Button

/// Circular icon button with glass or solid background
struct PremiumIconButton: View {
    let icon: String
    var size: CGFloat = 44
    var style: Style = .glass
    let action: () -> Void

    enum Style {
        case glass
        case solid(Color)
        case outline(Color)
    }

    @State private var isPressed = false

    var body: some View {
        Button(action: {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            action()
        }) {
            Image(systemName: icon)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundColor(foregroundColor)
                .frame(width: size, height: size)
                .background(background)
                .clipShape(Circle())
                .overlay(borderOverlay)
                .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(PremiumPressStyle(isPressed: $isPressed))
    }

    @ViewBuilder
    private var background: some View {
        switch style {
        case .glass:
            Circle().fill(.ultraThinMaterial)
        case .solid(let color):
            Circle().fill(color)
        case .outline:
            Circle().fill(Color.clear)
        }
    }

    @ViewBuilder
    private var borderOverlay: some View {
        switch style {
        case .glass:
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        case .solid:
            Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
        case .outline(let color):
            Circle().stroke(color.opacity(0.5), lineWidth: 2)
        }
    }

    private var foregroundColor: Color {
        switch style {
        case .glass:
            return .white
        case .solid:
            return .white
        case .outline(let color):
            return color
        }
    }
}

// MARK: - Loading Button State

/// Wrapper that shows loading state for any button content
struct LoadingButtonContent: View {
    let isLoading: Bool
    let title: String
    var loadingTitle: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            if isLoading {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(0.9)
            }
            Text(isLoading ? (loadingTitle ?? title) : title)
        }
    }
}

// MARK: - Previews

#Preview("Premium Buttons") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            PremiumPrimaryButton(
                title: "I'M SAFE",
                subtitle: "Hold & enter PIN to confirm",
                icon: "checkmark.shield.fill",
                color: Colors.safeGreen
            ) {}

            PremiumSecondaryButton(
                title: "NEED HELP",
                subtitle: "Send escalation alert",
                icon: "exclamationmark.triangle.fill",
                color: Colors.warningOrange
            ) {}

            HStack(spacing: 16) {
                GlassButton(title: "SECURE", icon: "lock.shield") {}
                GlassButton(title: "", icon: "camera.rotate.fill", iconOnly: true) {}
            }

            HStack(spacing: 16) {
                PremiumIconButton(icon: "gearshape.fill", style: .glass) {}
                PremiumIconButton(icon: "play.fill", style: .solid(Colors.witnessRed)) {}
                PremiumIconButton(icon: "xmark", style: .outline(Color.white)) {}
            }
        }
        .padding()
    }
}
