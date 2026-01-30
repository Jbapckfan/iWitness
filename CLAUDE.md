# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

The project builds via Xcode, not command-line tooling. Open `OnTheRecord.xcodeproj` in Xcode 15+ and build with Cmd+R. Terminal `xcodebuild` may fail due to signing/environment issues even when the project builds fine in Xcode.

```bash
# Build (may require adjusting scheme name / signing):
xcodebuild -project OnTheRecord.xcodeproj -scheme OnTheRecord -destination 'platform=iOS Simulator,name=iPhone 16' build

# List available simulators:
xcrun simctl list devices available
```

**Dual-camera recording requires a physical iPhone XS or newer** — the simulator cannot run `AVCaptureMultiCamSession`. Single-camera and non-AV features work in the simulator.

The project has zero external dependencies — everything uses Apple frameworks only.

### Tests

146 unit tests live in `Tests/OnTheRecordTests/` and run via the SPM test target:

```bash
# Run tests via Xcode (recommended — enables Keychain-dependent tests):
xcodebuild test -scheme OnTheRecord -destination 'id=<SIMULATOR_UUID>' -only-testing:OnTheRecordTests

# Or via SPM (33 Keychain-dependent tests will be skipped):
swift test
```

| Suite | Tests | Coverage |
|---|---|---|
| EncryptionServiceTests | 37 | AES-GCM, HKDF, RSA wrapping, signatures, thread safety |
| RecoveryKitTests | 27 | Code gen, create/import roundtrip, normalization |
| TimestampAnchorTests | 19 | Hash chaining, tamper detection, disk persistence |
| AppStateTests | 46 | State machine, ICE mode, computed properties |
| ChunkWriterTests | 17 | File I/O, numbering, orphan cleanup, thread safety |

## Architecture

**Service-oriented MVVM** with SwiftUI. The app entry point (`OnTheRecordApp.swift`) creates seven `@StateObject` services and injects them via `.environmentObject()`:

```
OnTheRecordApp (@main)
├── AppState              — single source of truth for UI/recording state
├── RecordingService      — AVFoundation dual-camera capture
├── UploadService         — background URLSession upload queue
├── AlertService          — emergency SMS/email via Twilio
├── LiveStreamService     — HLS adaptive streaming
├── ConnectivityGuardian  — NWPathMonitor + shake detection
└── WitnessBeaconService  — P2P offloading via MultipeerConnectivity
```

Additional services are accessed as singletons (`.shared`): `PhoneConnectivityManager`, `SiriShortcutManager`, `LiveActivityManager`, `VaultManager`, `StoreManager`.

### Core Data Pipeline

The critical path during recording is:

```
RecordingService (AVCaptureMultiCamSession)
  → ChunkWriter (0.5-second MP4 fragments, stored in ApplicationSupport/OnTheRecord/PendingUploads/{incidentID}/)
    → EncryptionService (HKDF per-chunk key derivation → AES-256-GCM seal → RSA-4096 key wrap → P256 ECDSA signature)
      → UploadService (background URLSession queue, persisted to UserDefaults, multi-destination: WebDAV/S3/R2/P2P)
```

`RecordingService.configure()` wires it to `UploadService` and `LiveStreamService`. `WitnessBeaconService.configure()` wires it to `UploadService` for "foreign chunk" (Mule mode) queueing.

### Activation Flow

`AppState.activateICEMode()` generates an incident ID (`IW-{timestamp}-{random}`) and sets `recordingMode = .recording`. The full activation sequence in `OnTheRecordApp.activateWitnessMode()` then: starts recording → sends emergency alerts → starts P2P browsing → notifies Watch → starts Live Activity.

### Service Wiring at Startup (`setupServices()`)

1. `ChunkWriter.wipeOrphanedChunks()` — cleans up cleartext from crashed sessions
2. `RecordingService.configure(uploadService:, liveStreamService:)` — connects chunk pipeline
3. `AlertService.configure()` + `loadTwilioConfig()`
4. `ConnectivityGuardian.configure(alertService:)` — for last-gasp alerts on signal loss
5. `WitnessBeaconService.configure(uploadService:)` — for P2P chunk relay
6. Background task: migrate secrets from UserDefaults to Keychain, load saved NAS/R2 destinations

## Key Patterns

- **Logging**: Use `debugLog()` (from `Logger.swift`) instead of `print()`. It compiles out in Release builds to prevent data leakage.
- **Secrets**: Credentials go in Keychain via `KeychainHelper`, never in UserDefaults. There is migration code in `OnTheRecordApp.migrateSecretsToKeychain()` for legacy values.
- **Concurrency**: Services are `@MainActor` or use explicit `@MainActor @Published` properties with `NSLock` for thread-safe internal state. Background work uses `Task.detached` or `DispatchQueue`.
- **File storage**: Chunks land in `ApplicationSupport/OnTheRecord/PendingUploads/{incidentID}/`. The Vault uses `Documents/Vault/` with `.completeUnlessOpen` file protection.
- **Design system**: UI follows a "Black Box" glassmorphism aesthetic. Use tokens from `DesignSystem.swift` (`DesignSystem.*`, `Typography.*`, `Spacing.*`, `GlassStyle.*`) rather than hardcoding colors/sizes. Key reusable components: `GlassCard`, `PremiumButton`, `StatusBadge`, `AnimatedGradient`.

## Targets

- **OnTheRecord** — main iOS app (iOS 17+)
- **OnTheRecordWatch** — watchOS 10+ companion (triggers recording, escalation from wrist)
- **OnTheRecordCore** — SPM library target wrapping `OnTheRecord/Sources` (defined in `Package.swift`)

## Important Context

- The app was formerly named "iWitness" — incident IDs still use the `IW-` prefix.
- `SettingsView.swift` is ~90KB and contains all settings screens in one file.
- `RecordingService.swift` also contains `VaultManager` at the top of the file.
- `NSAllowsArbitraryLoads` and `NSAllowsLocalNetworking` are enabled in Info.plist for local NAS WebDAV access.
- `ITSAppUsesNonExemptEncryption` is `true` (AES/RSA usage requires export compliance documentation for App Store).
- All `print()` calls have been replaced with `debugLog()` — only `Logger.swift` uses `print()` (it IS `debugLog()`).
- `EncryptionService` uses `NSLock` for thread safety on encrypt/decrypt operations.
- Encryption includes HMAC verification and ECDSA signature verification on decryption.
- Chunk chain integrity: `RecordingService` wires `previousChunkHash` between consecutive chunks.
- `PreflightCheckService` runs before activation — blocks on camera/mic denied, warns on missing Twilio/destinations.
- `KeyRecoveryService` exports public keys as QR codes (Settings → Key Recovery).
- `IncidentSummaryService` generates chain-of-custody PDF reports (shown after recording saved).
- `AppDelegate` is wired for background URLSession completion handler support.
