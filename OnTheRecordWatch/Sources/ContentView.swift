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
                    .fill(connectivity.isReachable ? Color.green : Color.red)
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
                                gradient: Gradient(colors: [.red, .red.opacity(0.7)]),
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
            .disabled(!connectivity.isReachable)

            Spacer()

            if !connectivity.isReachable {
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
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .animation(
                        Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true),
                        value: isPulsing
                    )

                Text("REC")
                    .font(.caption.bold())
                    .foregroundColor(.red)

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
                        .foregroundColor(.green)
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
                    .background(Color.green)
                    .cornerRadius(8)
                }

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
                    .background(Color.orange)
                    .cornerRadius(8)
                }
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
        watchState.playSuccessHaptic()
        connectivity.sendSafeCommand()
    }

    private func escalate() {
        watchState.playUrgentHaptic()
        connectivity.sendEscalateCommand()
    }
}

#Preview {
    ContentView()
        .environmentObject(WatchState())
        .environmentObject(WatchConnectivityManager())
}
