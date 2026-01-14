import SwiftUI
import AVKit
import UIKit

/// Read-only view for browsing and playing back recordings from offsite backup
/// Deliberately has NO delete functionality - recordings cannot be destroyed from this app
struct RecordingsView: View {
    @StateObject private var browserService = NASBrowserService()
    @State private var selectedIncident: NASBrowserService.Incident?
    @State private var playbackURL: URL?
    @State private var isDecrypting = false
    @State private var showingPlayer = false

    var body: some View {
        NavigationStack {
            ZStack {
                if browserService.isLoading {
                    LoadingView()
                } else if browserService.incidents.isEmpty {
                    EmptyStateView(onRefresh: refresh)
                } else {
                    IncidentListView(
                        incidents: browserService.incidents,
                        selectedIncident: $selectedIncident,
                        onSelect: preparePlayback
                    )
                }

                // Decryption overlay
                if isDecrypting {
                    DecryptionOverlay(progress: browserService.decryptionProgress)
                }
            }
            .navigationTitle("Recordings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(browserService.isLoading)
                }
            }
            .alert("Error", isPresented: .constant(browserService.error != nil)) {
                Button("OK") {
                    browserService.error = nil
                }
            } message: {
                Text(browserService.error?.localizedDescription ?? "")
            }
            .fullScreenCover(isPresented: $showingPlayer) {
                if let url = playbackURL {
                    VideoPlayerView(url: url, onDismiss: {
                        showingPlayer = false
                        playbackURL = nil
                    })
                }
            }
            .onAppear {
                if browserService.incidents.isEmpty {
                    refresh()
                }
            }
        }
    }

    private func refresh() {
        Task {
            await browserService.loadIncidents()
        }
    }

    private func preparePlayback(_ incident: NASBrowserService.Incident) {
        selectedIncident = incident
        isDecrypting = true

        Task {
            do {
                let url = try await browserService.prepareForPlayback(incident)
                playbackURL = url
                showingPlayer = true
            } catch {
                browserService.error = error as? NASBrowserService.BrowserError
                    ?? .decryptionFailed(error.localizedDescription)
            }
            isDecrypting = false
        }
    }
}

// MARK: - Loading View

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading recordings...")
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Empty State

private struct EmptyStateView: View {
    let onRefresh: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "video.slash")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("No Recordings Found")
                    .font(.title2.bold())

                Text("Recordings from your backup server will appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onRefresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Incident List

private struct IncidentListView: View {
    let incidents: [NASBrowserService.Incident]
    @Binding var selectedIncident: NASBrowserService.Incident?
    let onSelect: (NASBrowserService.Incident) -> Void

    var body: some View {
        List {
            Section {
                ForEach(incidents) { incident in
                    IncidentRow(
                        incident: incident,
                        isSelected: selectedIncident?.id == incident.id,
                        onTap: { onSelect(incident) }
                    )
                }
            } header: {
                Text("Secure Backups")
            } footer: {
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))
                    Text("Recordings are encrypted and read-only")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Incident Row

private struct IncidentRow: View {
    let incident: NASBrowserService.Incident
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Thumbnail placeholder
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor.systemGray5))
                        .frame(width: 60, height: 60)

                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color(red: 0.9, green: 0.2, blue: 0.2))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedDate)
                        .font(.headline)

                    HStack(spacing: 12) {
                        Label("\(incident.chunkCount) segments", systemImage: "film.stack")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label(formattedDuration, systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Text(incident.id)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: incident.date)
    }

    private var formattedDuration: String {
        // Each chunk is ~2 seconds
        let totalSeconds = incident.chunkCount * 2
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Decryption Overlay

private struct DecryptionOverlay: View {
    let progress: Double

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.open.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))

                Text("DECRYPTING")
                    .font(.headline)
                    .foregroundColor(.white)
                    .tracking(2)

                VStack(spacing: 8) {
                    ProgressView(value: progress)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color(red: 0.2, green: 0.8, blue: 0.3)))
                        .frame(width: 200)

                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                Text("Preparing secure playback...")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
            }
        }
    }
}

// MARK: - Video Player

private struct VideoPlayerView: View {
    let url: URL
    let onDismiss: () -> Void

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player = player {
                VideoPlayer(player: player)
                    .ignoresSafeArea()
            } else {
                ProgressView()
                    .tint(.white)
            }

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        player?.pause()
                        onDismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.white.opacity(0.8))
                            .shadow(radius: 4)
                    }
                    .padding()
                }
                Spacer()
            }

            // Read-only badge
            VStack {
                Spacer()
                HStack {
                    Image(systemName: "lock.shield.fill")
                        .foregroundColor(Color(red: 0.2, green: 0.8, blue: 0.3))
                    Text("Read-Only Playback")
                        .font(.caption)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.6))
                .cornerRadius(16)
                .padding(.bottom, 100)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func setupPlayer() {
        let avPlayer = AVPlayer(url: url)
        self.player = avPlayer
        avPlayer.play()
    }
}

#Preview {
    RecordingsView()
}
