import SwiftUI

struct RecordingHUDOverlay: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingService: RecordingService
    
    // Aesthetic state for simulated telemetry
    @State private var shutterSpeed: String = "1/60"
    @State private var iso: String = "ISO 400"
    @State private var gridOpacity: Double = 0.6
    
    // Periodic update timer
    let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    
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
                    
                    // Top Right: Camera Stats
                    VStack(alignment: .trailing, spacing: 4) {
                        HUDText(label: "CAM", value: recordingService.isDualCameraSupported ? "DUAL" : "SGL")
                        HUDText(label: "RES", value: "4K")
                        HUDText(label: "FPS", value: "60")
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 60) // Safe area
                
                Spacer()
                
                // 4. Bottom Telemetry Bar
                HStack(alignment: .bottom) {
                    // Bottom Left: Exposure Info
                    VStack(alignment: .leading, spacing: 4) {
                        HUDText(label: "ISO", value: iso)
                        HUDText(label: "SHT", value: shutterSpeed)
                        HUDText(label: "EV", value: "+0.0")
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
                .padding(.horizontal, 20)
                .padding(.bottom, 120) // Leave space for controls
            }
        }
        .allowsHitTesting(false) // Pass touches through to camera/buttons
        .onReceive(timer) { _ in
            updateTelemetry()
        }
    }
    
    private func updateTelemetry() {
        // Subtle randomization to make it feel "live"
        if Bool.random() {
            let isos = ["200", "250", "320", "400", "500", "640"]
            iso = "ISO \(isos.randomElement()!)"
        }
    }
}

// MARK: - Subcomponents

struct HUDText: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.green.opacity(0.9))
        }
    }
}

// TacticalGrid is now defined in ContentView.swift to be shared across views

struct CenterReticle: View {
    var body: some View {
        ZStack {
            Circle() // Center dot
                .fill(Color.red.opacity(0.6))
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
        HStack(spacing: 8) {
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
                .foregroundColor(.red)
                .offset(y: -10)
        )
    }
}
