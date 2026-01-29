# OnTheRecord

**Evidence survivability software for civil liberties documentation.**

> "20 seconds off-device beats 20 minutes on a seized phone."

## Quick Start

1. Open `OnTheRecord.xcodeproj` in Xcode 15+
2. Select your Apple Developer Team in Signing & Capabilities
3. Connect your iPhone
4. Build and run (Cmd+R)

## Project Structure

```
OnTheRecord/
├── Sources/
│   ├── App/
│   │   └── OnTheRecordApp.swift       # App entry point
│   ├── Models/
│   │   └── AppState.swift          # Global state management
│   ├── Services/
│   │   ├── RecordingService.swift  # Dual-camera AVFoundation capture
│   │   ├── ChunkWriter.swift       # Fragmented MP4 writer
│   │   ├── EncryptionService.swift # AES-256-GCM + RSA key wrapping
│   │   ├── UploadService.swift     # Multi-destination upload (WebDAV, S3)
│   │   ├── LocationService.swift   # GPS tracking
│   │   └── AlertService.swift      # SMS/email emergency alerts
│   └── Views/
│       ├── ContentView.swift       # Main navigation
│       ├── RecordingView.swift     # Minimal recording UI
│       ├── SettingsView.swift      # Configuration screens
│       └── OnboardingView.swift    # First-launch setup
└── Resources/
    ├── Info.plist                  # App permissions
    ├── OnTheRecord.entitlements       # Capabilities
    └── Assets.xcassets/            # App icons & colors
```

## Core Features (MVP)

- **One-Tap Activation**: Instantly start recording + upload + alert
- **Dual Camera**: Simultaneous front + back recording
- **Chunked Upload**: 0.5-second encrypted fragments survive seizure
- **Enveloped Encryption**: AES-256-GCM data, RSA-4096 key wrapping
- **Multi-Destination**: NAS (WebDAV) + Cloud (Cloudflare R2)
- **Emergency Alerts**: SMS with GPS to trusted contacts
- **Guided Access Training**: OS-level lockdown assistance

## Setup Your NAS

1. Enable WebDAV on your Ugreen NAS (UGOS Pro Settings)
2. Create a folder for OnTheRecord footage
3. Note the WebDAV URL (e.g., `https://192.168.1.100:5006/webdav/ontherecord`)
4. In the app, go to Settings > NAS Storage and enter credentials

## Security Architecture

```
Video Capture → 0.5-sec Chunk → AES-256-GCM Encrypt → SHA-256 Hash → Upload
                                      ↑
                              HKDF-derived key per chunk
                              (from incident master key)
                                      ↑
                              Master key wrapped with RSA-4096
                              (user's public key)
```

**Zero-Knowledge**: Server never sees plaintext or private keys.

## Permissions Required

- **Camera**: Front + back video capture
- **Microphone**: Audio evidence
- **Location**: GPS coordinates for alerts
- **Background Modes**: Audio, location, processing, fetch

## Development Notes

### Testing Dual Camera

Dual-camera (AVCaptureMultiCamSession) requires:
- iPhone XS or newer
- iOS 17+
- Physical device (not simulator)

### NAS Testing

For local development, ensure your Mac and iPhone are on the same network.
WebDAV uploads require valid SSL or NSAllowsLocalNetworking = true.

### Encryption

Keys are stored in iOS Secure Enclave via Keychain.
Never export or log private keys.

## Roadmap

- [ ] Apple Watch trigger app
- [ ] Cloudflare R2 integration
- [ ] Witness Beacon (community alerts)
- [ ] Case packet export
- [ ] Twilio SMS integration (background send)

## Legal

This app is designed for legal documentation of public encounters.
Recording law enforcement in public is constitutionally protected.
Consult local laws for private property rules.

## License

TBD - Considering open source with nonprofit structure.

---

*Built in response to the need for evidence survivability in civil liberties contexts.*
