import SwiftUI

// MARK: - Status Badge

/// Configurable status indicator badge with optional animation
struct StatusBadge: View {
    let text: String
    let style: Style
    var showIcon: Bool = true
    var isPulsing: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Style {
        case success
        case warning
        case error
        case info
        case live
        case neutral

        var color: Color {
            switch self {
            case .success: return Colors.safeGreen
            case .warning: return Colors.warningOrange
            case .error: return Colors.errorRed
            case .info: return .blue
            case .live: return Colors.witnessRed
            case .neutral: return .secondary
            }
        }

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            case .info: return "info.circle.fill"
            case .live: return "circle.fill"
            case .neutral: return "circle.fill"
            }
        }
    }

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            if showIcon {
                Image(systemName: style.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .scaleEffect(pulseScale)
            }
            Text(text)
                .font(Typography.label)
        }
        .foregroundColor(style.color)
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xxs + 2)
        .background(
            Capsule()
                .fill(style.color.opacity(0.15))
        )
        .onAppear {
            guard !reduceMotion, isPulsing else { return }
            withAnimation(AnimationPresets.pulse) {
                pulseScale = 1.3
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("\(text) status"))
    }
}

// MARK: - Pulsing Indicator

/// Animated pulsing dot indicator (like recording light)
struct PulsingIndicator: View {
    let color: Color
    var size: CGFloat = 12
    var isActive: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            // Outer pulse ring (hidden if reduce motion)
            if !reduceMotion {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: size * 2, height: size * 2)
                    .scaleEffect(isPulsing ? 1.5 : 1.0)
                    .opacity(isPulsing ? 0 : 0.5)
            }

            // Inner solid dot
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.6), radius: 4)
                .shadow(color: color.opacity(0.25), radius: 10)
                .shadow(color: color.opacity(0.1), radius: 18)
        }
        .onAppear {
            guard !reduceMotion, isActive else { return }
            withAnimation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
        .onChange(of: isActive) { _, newValue in
            guard !reduceMotion else { return }
            if newValue {
                withAnimation(
                    Animation.easeInOut(duration: 1.0)
                        .repeatForever(autoreverses: false)
                ) {
                    isPulsing = true
                }
            } else {
                isPulsing = false
            }
        }
        .accessibilityLabel(isActive ? "Recording indicator active" : "Recording indicator inactive")
    }
}

// MARK: - Status Pill

/// Premium status pill with icon and label
struct StatusPill: View {
    let icon: String
    let label: String
    let isActive: Bool
    var activeColor: Color = Colors.safeGreen

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
            Text(label)
                .font(Typography.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(isActive ? activeColor : .secondary)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(isActive ? activeColor.opacity(0.15) : Color(.systemGray5))
        )
        .overlay(
            Capsule()
                .stroke(
                    isActive ? activeColor.opacity(0.3) : Color.clear,
                    lineWidth: 1
                )
        )
    }
}

// MARK: - Live Badge

/// Special badge for live streaming indicator
struct LiveBadge: View {
    var segmentCount: Int?
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Button(action: { onTap?() }) {
            HStack(spacing: Spacing.xs) {
                ZStack {
                    if !reduceMotion {
                        Circle()
                            .fill(Colors.witnessRed.opacity(0.3))
                            .frame(width: 16, height: 16)
                            .scaleEffect(isPulsing ? 1.4 : 1.0)
                            .opacity(isPulsing ? 0 : 0.6)
                    }

                    Circle()
                        .fill(Colors.witnessRed)
                        .frame(width: 10, height: 10)
                        .shadow(color: Colors.witnessRed.opacity(0.6), radius: 4)
                        .shadow(color: Colors.witnessRed.opacity(0.25), radius: 10)
                        .shadow(color: Colors.witnessRed.opacity(0.1), radius: 16)
                }

                Text("LIVE")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(Colors.witnessRed)

                if let count = segmentCount {
                    Text("•")
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(count) sent")
                        .font(Typography.caption)
                        .foregroundColor(.white)
                }

                if onTap != nil {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Colors.witnessRed.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
        .accessibilityLabel("Live streaming\(segmentCount != nil ? ", \(segmentCount!) segments sent" : "")")
    }
}

// MARK: - Connection Status Badge

/// Badge showing connection/signal status
struct ConnectionBadge: View {
    let isConnected: Bool
    var secondsDisconnected: Int?

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: isConnected ? "wifi" : "wifi.slash")
                .font(.system(size: 14, weight: .semibold))

            if isConnected {
                Text("Connected")
                    .font(Typography.caption)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Signal Lost")
                        .font(Typography.caption)
                        .fontWeight(.semibold)
                    if let seconds = secondsDisconnected {
                        Text("Offline \(seconds)s")
                            .font(.system(size: 10))
                            .opacity(0.8)
                    }
                }
            }
        }
        .foregroundColor(isConnected ? Colors.safeGreen : .white)
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.xs)
        .background(
            Capsule()
                .fill(isConnected ? Colors.safeGreen.opacity(0.15) : Colors.errorRed.opacity(0.9))
        )
    }
}

// MARK: - Previews

#Preview("Status Badges") {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack(spacing: 20) {
            HStack(spacing: 12) {
                StatusBadge(text: "Ready", style: .success)
                StatusBadge(text: "Warning", style: .warning)
                StatusBadge(text: "Error", style: .error)
            }

            HStack(spacing: 12) {
                StatusBadge(text: "Info", style: .info)
                StatusBadge(text: "LIVE", style: .live, isPulsing: true)
                StatusBadge(text: "Neutral", style: .neutral)
            }

            HStack(spacing: 16) {
                PulsingIndicator(color: Colors.witnessRed)
                PulsingIndicator(color: Colors.safeGreen, size: 8)
            }

            HStack(spacing: 12) {
                StatusPill(icon: "person.2.fill", label: "3 Contacts", isActive: true)
                StatusPill(icon: "externaldrive.fill", label: "No Storage", isActive: false)
            }

            LiveBadge(segmentCount: 12) {}

            HStack(spacing: 12) {
                ConnectionBadge(isConnected: true)
                ConnectionBadge(isConnected: false, secondsDisconnected: 45)
            }
        }
        .padding()
    }
}
