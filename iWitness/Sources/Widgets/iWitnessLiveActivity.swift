import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

// MARK: - Live Activity Widget

@available(iOS 16.1, *)
struct iWitnessLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IWitnessAttributes.self) { context in
            // Lock screen / banner view
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded region
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        PulsingDot()
                        Text("REC")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(.red)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .monospacedDigit()
                }

                DynamicIslandExpandedRegion(.center) {
                    Text("iWitness Recording")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        StatusIndicator(icon: "video.fill", label: "Dual Cam", isActive: true)
                        StatusIndicator(icon: "arrow.up.circle.fill", label: "Uploading", isActive: true)
                        StatusIndicator(icon: "antenna.radiowaves.left.and.right", label: "Live", isActive: true)
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text("REC")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(.red)
                }
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .monospacedDigit()
            } minimal: {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                }
            }
        }
    }
}

// MARK: - Lock Screen View

@available(iOS 16.1, *)
struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<IWitnessAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            HStack(spacing: 8) {
                PulsingDot()

                VStack(alignment: .leading, spacing: 2) {
                    Text("iWitness Recording")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)

                    Text("Evidence being saved")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()

            // Timer
            VStack(alignment: .trailing, spacing: 2) {
                Text(context.state.startedAt, style: .timer)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                    .monospacedDigit()

                Text("Duration")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(white: 0.15), Color(white: 0.1)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .activityBackgroundTint(Color.black)
    }
}

// MARK: - Supporting Views

@available(iOS 16.1, *)
struct PulsingDot: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 24, height: 24)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .opacity(isPulsing ? 0 : 0.6)

            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
        }
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 1.0)
                    .repeatForever(autoreverses: false)
            ) {
                isPulsing = true
            }
        }
    }
}

@available(iOS 16.1, *)
struct StatusIndicator: View {
    let icon: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(isActive ? .green : .gray)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill((isActive ? Color.green : Color.gray).opacity(0.2))
        )
    }
}

#endif
