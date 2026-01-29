import SwiftUI

struct ContentView: View {
    @EnvironmentObject var watchState: WatchState
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color.black.ignoresSafeArea()

                if watchState.status == .recording {
                    RecordingView()
                } else {
                    IdleView()
                }
            }
        }
        .onAppear {
            setupCallbacks()
        }
    }

    private func setupCallbacks() {
        connectivity.onRecordingStarted = {
            watchState.status = .recording
            watchState.startDurationTimer()
            watchState.playActivationHaptic()
        }

        connectivity.onRecordingStopped = {
            watchState.status = .safe
            watchState.stopDurationTimer()
            watchState.playSuccessHaptic()

            // Reset after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                watchState.status = .idle
            }
        }

        connectivity.onStatusUpdate = { status in
            if let chunks = status["chunksUploaded"] as? Int {
                watchState.chunksUploaded = chunks
            }
            if let contacts = status["contactsNotified"] as? Int {
                watchState.contactsNotified = contacts
            }
        }

        // Command delivery confirmation handling
        connectivity.onCommandResult = { confirmed, queued in
            if confirmed {
                watchState.commandStatus = .confirmed
                watchState.playSuccessHaptic()
            } else if queued {
                watchState.commandStatus = .queued
                watchState.playWarningHaptic()
            } else {
                watchState.commandStatus = .failed("Command may not have been received")
                watchState.playErrorHaptic()
            }
            watchState.resetCommandStatusAfterDelay()
        }
    }
}

// MARK: - Idle View (Big Red Button)

struct IdleView: View {
    @EnvironmentObject var watchState: WatchState
    @EnvironmentObject var connectivity: WatchConnectivityManager

    var body: some View {
        VStack(spacing: 12) {
            // Connection status
            HStack {
                Circle()
                    .fill(connectivity.isReachable ? WatchColors.safeGreen : WatchColors.witnessRed)
                    .frame(width: 8, height: 8)

                Text(connectivity.isReachable ? "Connected" : "Disconnected")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Big activation button
            Button {
                activateWitness()
            } label: {
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                gradient: Gradient(colors: [WatchColors.witnessRed, WatchColors.witnessRed.opacity(0.7)]),
                                center: .center,
                                startRadius: 0,
                                endRadius: 60
                            )
                        )
                        .frame(width: 120, height: 120)

                    VStack(spacing: 4) {
                        Image(systemName: "video.fill")
                            .font(.title)
                        Text("WITNESS")
                            .font(.caption.bold())
                    }
                    .foregroundColor(.white)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!connectivity.isReachable && watchState.commandStatus != .sending)

            Spacer()

            // Command delivery status feedback
            CommandStatusBanner(commandStatus: watchState.commandStatus)

            if !connectivity.isReachable && watchState.commandStatus == .idle {
                Text("Open OnTheRecord on iPhone")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }

    private func activateWitness() {
        watchState.status = .activating
        watchState.commandStatus = .sending
        watchState.playUrgentHaptic()
        connectivity.sendActivateCommand()
    }
}

// MARK: - Recording View

struct RecordingView: View {
    @EnvironmentObject var watchState: WatchState
    @EnvironmentObject var connectivity: WatchConnectivityManager

    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 8) {
            // Recording indicator
            HStack {
                Circle()
                    .fill(WatchColors.witnessRed)
                    .frame(width: 10, height: 10)
                    .shadow(color: WatchColors.witnessRed.opacity(0.6), radius: 4)
                    .shadow(color: WatchColors.witnessRed.opacity(0.25), radius: 10)
                    .shadow(color: WatchColors.witnessRed.opacity(0.1), radius: 16)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                        value: isPulsing
                    )

                Text("REC")
                    .font(.caption.bold())
                    .foregroundColor(WatchColors.witnessRed)

                Spacer()

                Text(watchState.formattedDuration)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal)
            .onAppear { isPulsing = true }

            Spacer()

            // Status
            VStack(spacing: 4) {
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundColor(WatchColors.safeGreen)
                    Text("\(watchState.chunksUploaded)")
                        .font(.caption)
                }

                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundColor(.blue)
                    Text("\(watchState.contactsNotified) notified")
                        .font(.caption)
                }
            }
            .foregroundColor(.white)

            Spacer()

            // Command delivery status feedback
            CommandStatusBanner(commandStatus: watchState.commandStatus)

            // Action buttons
            HStack(spacing: 12) {
                // I'm Safe
                Button {
                    markSafe()
                } label: {
                    VStack {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.title3)
                        Text("SAFE")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(WatchColors.safeGreen)
                    .cornerRadius(8)
                }
                .disabled(watchState.commandStatus == .sending)

                // Need Help
                Button {
                    escalate()
                } label: {
                    VStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title3)
                        Text("HELP")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(WatchColors.warningOrange)
                    .cornerRadius(8)
                }
                .disabled(watchState.commandStatus == .sending)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding()
        .onAppear {
            // Request status updates periodically
            Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
                connectivity.requestStatus()
            }
        }
    }

    private func markSafe() {
        watchState.commandStatus = .sending
        watchState.playSuccessHaptic()
        connectivity.sendSafeCommand()
    }

    private func escalate() {
        watchState.commandStatus = .sending
        watchState.playUrgentHaptic()
        connectivity.sendEscalateCommand()
    }
}

// MARK: - Command Status Banner

struct CommandStatusBanner: View {
    let commandStatus: WatchState.CommandStatus

    var body: some View {
        Group {
            switch commandStatus {
            case .idle:
                EmptyView()

            case .sending:
                HStack(spacing: 6) {
                    ProgressView()
                        .tint(.white)
                    Text("Sending...")
                        .font(.caption2)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.5))
                .cornerRadius(8)

            case .confirmed:
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(WatchColors.safeGreen)
                    Text("Confirmed")
                        .font(.caption2)
                        .foregroundColor(WatchColors.safeGreen)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(WatchColors.safeGreen.opacity(0.2))
                .cornerRadius(8)

            case .queued:
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(WatchColors.warningOrange)
                    Text("Phone not connected")
                        .font(.caption2)
                        .foregroundColor(WatchColors.warningOrange)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(WatchColors.warningOrange.opacity(0.2))
                .cornerRadius(8)

            case .failed(let message):
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(WatchColors.witnessRed)
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(WatchColors.witnessRed)
                        .lineLimit(2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(WatchColors.witnessRed.opacity(0.2))
                .cornerRadius(8)
            }
        }
        .transition(.opacity.combined(with: .scale))
        .animation(.easeInOut(duration: 0.3), value: commandStatus)
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchState())
        .environmentObject(WatchConnectivityManager())
}
