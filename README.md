# OnTheRecord

**Your right to record. Encrypted, private, always by your side.**

> When in doubt, put it on the record. Your phone becomes your most trusted witness — encrypted, private, always ready.

## Quick Start

1. Open `OnTheRecord.xcodeproj` in Xcode 15+
2. Select your Apple Developer Team in Signing & Capabilities
3. Connect your iPhone (XS or newer for dual-camera)
4. Build and run (Cmd+R)

## Features

- **One-Tap Activation** — Button, Lock Screen, Apple Watch, or "Hey Siri, put this on the record"
- **Dual Camera** — Simultaneous front + back recording captures both sides
- **Real-Time Encrypted Backup** — 0.5-second AES-256-GCM encrypted chunks uploaded as they're captured
- **Evidence Survives Seizure** — Phone taken? Evidence is already safe on your NAS/cloud
- **Hash-Chained Timestamps** — Tamper-evident chain of custody with P256 ECDSA signatures
- **Recovery Kit** — Encrypted key backup so you (or a trusted contact) can always access your evidence
- **Live Transcription** — On-device speech-to-text overlay during recording
- **Emergency Alerts** — SMS/email to trusted contacts with GPS coordinates
- **Apple Watch Companion** — Start, stop, and escalate from your wrist
- **Stealth Mode** — Blackout screen, calculator camouflage
- **Witness Mesh** — P2P backup to nearby devices via MultipeerConnectivity
- **Evidence Export** — Chain-of-custody PDF with digital signature verification
- **Geofence Auto-Record** — Automatic activation when entering monitored zones
- **App Lock** — Biometric authentication to protect the app
- **Open Source** — Transparent code anyone can audit

## Project Structure

```
OnTheRecord/
├── Sources/
│   ├── App/
│   │   └── OnTheRecordApp.swift          # Entry point, service wiring
│   ├── Models/
│   │   └── AppState.swift                # Global state machine
│   ├── Services/
│   │   ├── RecordingService.swift        # Dual-camera AVFoundation capture
│   │   ├── ChunkWriter.swift             # 0.5s fragmented MP4 writer
│   │   ├── EncryptionService.swift       # AES-256-GCM + RSA-4096 + HKDF + ECDSA
│   │   ├── UploadService.swift           # Background upload queue (WebDAV, S3/R2)
│   │   ├── AlertService.swift            # SMS/email emergency alerts (Twilio)
│   │   ├── RecoveryKitService.swift      # Encrypted key recovery with PBKDF2
│   │   ├── TimestampAnchorService.swift  # Hash-chained tamper-evident timestamps
│   │   ├── TranscriptionService.swift    # On-device speech recognition
│   │   ├── LiveStreamService.swift       # HLS adaptive streaming
│   │   ├── WitnessBeaconService.swift    # P2P mesh backup
│   │   ├── DepthCaptureService.swift     # LiDAR 3D scene capture
│   │   ├── GeofenceService.swift         # Location-triggered auto-record
│   │   ├── AudioEnhancementService.swift # Audio noise reduction
│   │   └── AppLockService.swift          # Biometric authentication
│   └── Views/
│       ├── ContentView.swift             # Main navigation
│       ├── RecordingView.swift           # Minimal recording UI
│       ├── SettingsView.swift            # Configuration screens
│       └── OnboardingView.swift          # First-launch setup
├── Tests/
│   └── OnTheRecordTests/                 # 146 unit tests
└── Resources/
    ├── Info.plist
    ├── OnTheRecord.entitlements
    └── Assets.xcassets/
```

## Security Architecture

```
Video Capture → 0.5s Chunk → AES-256-GCM Encrypt → P256 ECDSA Sign → SHA-256 Hash Chain → Upload
                                    ↑
                            HKDF-derived key per chunk
                            (from incident master key + random salt)
                                    ↑
                            Master key wrapped with RSA-4096 OAEP
                            (embedded in every chunk)
                                    ↑
                            Signing key in Secure Enclave
                            (non-extractable, hardware-bound)
```

**Zero-Knowledge**: Your private keys never leave your device. Videos are sealed before upload. We couldn't access them if we wanted to.

**Recovery**: The Recovery Kit exports an encrypted backup of your private keys, protected by a PBKDF2-derived key (600K iterations) from a human-readable recovery code. Neither the file nor the code alone can decrypt your evidence.

## Setup

### NAS (WebDAV)

1. Enable WebDAV on your NAS (e.g., Ugreen UGOS Pro Settings)
2. Create a folder for OnTheRecord footage
3. In the app: Settings → Storage → NAS and enter your WebDAV URL + credentials
4. Use "Test Connection" to verify

### Cloud (Cloudflare R2)

1. Create an R2 bucket in your Cloudflare dashboard
2. Generate an API token with read/write access
3. In the app: Settings → Storage → Cloud and enter Account ID, Bucket, Access Key, Secret Key

## Testing

```bash
# Run tests via Xcode (recommended):
xcodebuild test -scheme OnTheRecord -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:OnTheRecordTests

# 146 tests, 0 failures
# 33 Keychain-dependent tests auto-skip in SPM/simulator environments
```

### Device Testing

Dual-camera (`AVCaptureMultiCamSession`) requires iPhone XS+ on iOS 17+ with a physical device. Secure Enclave signing requires a physical device. LiDAR depth capture requires iPhone 12 Pro+.

## Permissions Required

- **Camera**: Front + back video capture
- **Microphone**: Audio evidence
- **Location**: GPS coordinates for alerts and geofencing
- **Speech Recognition**: Live transcription
- **Contacts**: Emergency contact selection
- **Background Modes**: Audio, location, processing, fetch

## Export Compliance

The app uses non-exempt encryption (AES-256, RSA-4096, P256 ECDSA). See `ExportCompliance.md` for BIS self-classification requirements and Apple's export compliance questionnaire answers.

## Legal

This app is designed for legal documentation of encounters. Recording law enforcement in public is constitutionally protected in the United States. Consult local laws regarding recording in private settings and one-party/two-party consent requirements.

## License

Open source. See LICENSE file.

---

*Your evidence. Your privacy. Your rights.*
