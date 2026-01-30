import SwiftUI

struct RecordingHUDOverlay: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    @StateObject private var transcriptionService = TranscriptionService.shared

    @State private var gridOpacity: Double = 0.6
    
    var body: some View {
        ZStack {
            // 1. Grid Lines & Brackets
            TacticalGrid()
                .opacity(gridOpacity)
            
            // 2. Center Reticle
            CenterReticle()
                .opacity(0.8)
            
            // 3. Top Telemetry Bar
            VStack {
                HStack(alignment: .top) {
                    // Top Left: System Status
                    VStack(alignment: .leading, spacing: 4) {
                        HUDText(label: "REC_MODE", value: "ACTV")
                        HUDText(label: "ENCR", value: "AES-256")
                        HUDText(label: "STOR", value: "SECURE")
                    }

                    Spacer()

                    // Top Center: Compass / Heading (Simulated)
                    CompassStrip()

                    Spacer()

                    // Top Right: Camera Stats (live from quality setting)
                    VStack(alignment: .trailing, spacing: 4) {
                        HUDText(label: "CAM", value: recordingService.isDualCameraSupported ? "DUAL" : "SGL")
                        HUDText(label: "RES", value: appState.currentQuality.rawValue)
                        HUDText(label: "BPS", value: formatBitrate(appState.currentQuality.bitrate))
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.top, 60) // Safe area
                
                Spacer()
                
                // 4. Bottom Telemetry Bar
                HStack(alignment: .bottom) {
                    // Bottom Left: Recording Metrics (live)
                    VStack(alignment: .leading, spacing: 4) {
                        HUDText(label: "SEG", value: "\(recordingService.currentChunkNumber)")
                        HUDText(label: "SIZE", value: appState.formattedEstimatedSize)
                        HUDText(label: "DUR", value: appState.formattedDuration)
                    }
                    
                    Spacer()
                    
                    // Bottom Right: GPS / Location
                    VStack(alignment: .trailing, spacing: 4) {
                        if let loc = appState.currentLocation {
                            HUDText(label: "LAT", value: String(format: "%.5f", loc.latitude))
                            HUDText(label: "LON", value: String(format: "%.5f", loc.longitude))
                            HUDText(label: "ALT", value: String(format: "%.1fm", loc.altitude ?? 0))
                        } else {
                            HUDText(label: "GPS", value: "NO FIX")
                            HUDText(label: "SAT", value: "SEARCH")
                        }
                    }
                }
                .padding(.horizontal, Spacing.screenPadding)
                .padding(.bottom, 120) // Leave space for controls
            }

            // 5. Live Transcript Overlay
            if transcriptionService.isTranscribing, !transcriptionService.currentTranscript.isEmpty {
                VStack {
                    Spacer()
                    LiveTranscriptBanner(transcript: transcriptionService.currentTranscript)
                        .padding(.horizontal, Spacing.screenPadding)
                        .padding(.bottom, 130) // Above bottom controls
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: transcriptionService.currentTranscript)
            }
        }
        .allowsHitTesting(false) // Pass touches through to camera/buttons
        .accessibilityHidden(true)
    }

    private func formatBitrate(_ bps: Int) -> String {
        if bps >= 1_000_000 {
            return String(format: "%.0fM", Double(bps) / 1_000_000)
        }
        return String(format: "%.0fK", Double(bps) / 1_000)
    }
}

// MARK: - Subcomponents

struct HUDText: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Typography.hudLabel)
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(Typography.hudValue)
                .foregroundColor(Colors.safeGreen.opacity(0.9))
        }
    }
}

// TacticalGrid is now defined in ContentView.swift to be shared across views

struct CenterReticle: View {
    var body: some View {
        ZStack {
            Circle() // Center dot
                .fill(Colors.witnessRed.opacity(0.6))
                .frame(width: 4, height: 4)
            
            Circle() // Outer ring
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 30, height: 30)
            
            Rectangle() // Horizontal cross
                .fill(Color.white.opacity(0.3))
                .frame(width: 50, height: 1)
            
            Rectangle() // Vertical cross
                .fill(Color.white.opacity(0.3))
                .frame(width: 1, height: 50)
        }
    }
}

struct CompassStrip: View {
    var body: some View {
        HStack(spacing: Spacing.xs) {
            ForEach(0..<15) { i in
                Rectangle()
                    .fill(Color.white.opacity(i % 5 == 0 ? 0.6 : 0.2))
                    .frame(width: 1, height: i % 5 == 0 ? 10 : 5)
            }
        }
        .frame(width: 120)
        .mask(LinearGradient(colors: [.clear, .white, .white, .clear], startPoint: .leading, endPoint: .trailing))
        .overlay(
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 8))
                .foregroundColor(Colors.witnessRed)
                .offset(y: -10)
        )
    }
}

// MARK: - Live Transcript Banner

struct LiveTranscriptBanner: View {
    let transcript: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                Text(transcript)
                    .font(Typography.hudValue)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("transcriptEnd")
            }
            .frame(maxHeight: 60)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Colors.safeGreen.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .overlay(
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 8))
                        .foregroundColor(Colors.safeGreen.opacity(0.7))
                    Text("LIVE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(Colors.safeGreen.opacity(0.7))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.6))
                .cornerRadius(4)
                .offset(x: 0, y: -4),
                alignment: .topTrailing
            )
            .onChange(of: transcript) { _ in
                withAnimation {
                    proxy.scrollTo("transcriptEnd", anchor: .bottom)
                }
            }
        }
    }
}
