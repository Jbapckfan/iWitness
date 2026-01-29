import SwiftUI

// MARK: - Design System
// Premium design tokens for OnTheRecord - glassmorphism with subtle polish

struct DesignSystem {
    // Keep original emergency colors for backwards compatibility
    static let witnessRed = Color(red: 0.9, green: 0.2, blue: 0.2)
    static let safeGreen = Color(red: 0.2, green: 0.8, blue: 0.3)
    static let warningOrange = Color(red: 1.0, green: 0.6, blue: 0.0)
    static let errorRed = Color(red: 0.8, green: 0.1, blue: 0.1)
    static let backgroundDark = Color(red: 0.05, green: 0.05, blue: 0.05)

    // Legacy spacing (keep for compatibility)
    static let sectionSpacing: CGFloat = 40
    static let buttonPadding: CGFloat = 24
    static let cornerRadius: CGFloat = 20
    static let iconSize: CGFloat = 28
}

// MARK: - Typography

struct Typography {
    // Display - Hero elements
    static let displayLarge = Font.system(size: 64, weight: .heavy, design: .rounded)
    static let displayMedium = Font.system(size: 48, weight: .bold, design: .rounded)

    // Headlines
    static let headline1 = Font.system(size: 28, weight: .bold)
    static let headline2 = Font.system(size: 24, weight: .semibold)
    static let headline3 = Font.system(size: 20, weight: .semibold)

    // Body
    static let bodyLarge = Font.system(size: 17, weight: .regular)
    static let bodyMedium = Font.system(size: 15, weight: .regular)
    static let bodySmall = Font.system(size: 13, weight: .regular)

    // Captions & Labels
    static let caption = Font.system(size: 12, weight: .medium)
    static let label = Font.system(size: 11, weight: .semibold)
    static let overline = Font.system(size: 10, weight: .bold)

    // Monospaced (for timers)
    static let timerLarge = Font.system(size: 64, weight: .heavy, design: .monospaced)
    static let timerMedium = Font.system(size: 32, weight: .bold, design: .monospaced)

    // HUD (monospaced, for recording overlay)
    static let hudLabel = Font.system(size: 10, weight: .bold, design: .monospaced)
    static let hudValue = Font.system(size: 10, weight: .regular, design: .monospaced)

    // Terminal (monospaced, for home screen tactical display)
    static let terminalBody = Font.system(size: 14, weight: .medium, design: .monospaced)
    static let terminalBold = Font.system(size: 14, weight: .bold, design: .monospaced)
    static let terminalSmall = Font.system(size: 12, weight: .bold, design: .monospaced)
    static let terminalLog = Font.system(size: 10, design: .monospaced)
}

// MARK: - Spacing

struct Spacing {
    // Base unit: 4pt
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let xxxl: CGFloat = 64

    // Semantic spacing
    static let sectionGap: CGFloat = 32
    static let cardPadding: CGFloat = 20
    static let screenPadding: CGFloat = 20

    // Corner radii
    struct Radius {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
        static let full: CGFloat = 9999
    }
}

// MARK: - Elevation

struct Elevation {
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    // Level 1 - Subtle lift (cards, pills)
    static let low = Shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

    // Level 2 - Medium elevation (buttons, floating elements)
    static let medium = Shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)

    // Level 3 - High elevation (modals, overlays)
    static let high = Shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)

    // Level 4 - Glow effect (active buttons, alerts)
    static func glow(color: Color, intensity: Double = 0.4) -> Shadow {
        Shadow(color: color.opacity(intensity), radius: 20, x: 0, y: 0)
    }
}

extension View {
    func elevation(_ shadow: Elevation.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }

    func glowEffect(color: Color, intensity: Double = 0.4) -> some View {
        let glow = Elevation.glow(color: color, intensity: intensity)
        return self.shadow(color: glow.color, radius: glow.radius, x: glow.x, y: glow.y)
    }
}

// MARK: - Colors

struct Colors {
    // Primary brand colors (high-contrast for emergency)
    static let witnessRed = DesignSystem.witnessRed
    static let safeGreen = DesignSystem.safeGreen
    static let warningOrange = DesignSystem.warningOrange
    static let alertOrange = DesignSystem.warningOrange  // Alias for warnings/alerts
    static let errorRed = DesignSystem.errorRed

    // Glass-friendly backgrounds
    static let glassDark = Color.black.opacity(0.3)
    static let glassLight = Color.white.opacity(0.1)
    static let glassAccent = Color.white.opacity(0.15)
    static let glassBorder = Color.white.opacity(0.2)

    // Semantic colors
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textMuted = Color.secondary.opacity(0.7)

    // Gradient definitions
    struct Gradients {
        static let emergency = LinearGradient(
            colors: [witnessRed, witnessRed.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let safe = LinearGradient(
            colors: [safeGreen, safeGreen.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let warning = LinearGradient(
            colors: [warningOrange, warningOrange.opacity(0.8)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        static let ambientDark = LinearGradient(
            colors: [Color(white: 0.08), Color(white: 0.02)],
            startPoint: .top,
            endPoint: .bottom
        )

        static let glassBorder = LinearGradient(
            colors: [Color.white.opacity(0.25), Color.white.opacity(0.05)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Animation Presets

struct AnimationPresets {
    // Quick micro-interactions
    static let micro = Animation.easeOut(duration: 0.15)

    // Standard transitions
    static let standard = Animation.easeInOut(duration: 0.25)

    // Smooth entrance animations
    static let entrance = Animation.spring(response: 0.4, dampingFraction: 0.8)

    // Bouncy feedback
    static let bounce = Animation.spring(response: 0.35, dampingFraction: 0.6)

    // Snappy interactions
    static let snappy = Animation.spring(response: 0.3, dampingFraction: 0.7)

    // Slow, dramatic transitions
    static let dramatic = Animation.easeInOut(duration: 0.5)

    // Pulse/breathe effect
    static let pulse = Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)

    // Staggered delays for list animations
    static func staggered(index: Int, baseDelay: Double = 0.05) -> Animation {
        Animation.spring(response: 0.4, dampingFraction: 0.8)
            .delay(Double(index) * baseDelay)
    }
}

// MARK: - Glass Materials

struct GlassMaterials {
    // Primary glass - main cards, navigation
    static let primary: Material = .ultraThinMaterial

    // Secondary glass - overlays, secondary cards
    static let secondary: Material = .thinMaterial

    // Thick glass - important overlays, modals
    static let thick: Material = .regularMaterial

    // Blur intensities for custom effects
    enum BlurIntensity: CGFloat {
        case subtle = 8
        case standard = 16
        case heavy = 24
        case extreme = 40
    }
}
