import XCTest
@testable import OnTheRecordCore

@MainActor
final class AppStateTests: XCTestCase {

    private var appState: AppState!

    override func setUp() {
        super.setUp()
        appState = AppState()
    }

    override func tearDown() {
        appState.reset()
        appState = nil
        super.tearDown()
    }

    // MARK: - Initial State

    func testInitialRecordingModeIsIdle() {
        XCTAssertEqual(appState.recordingMode, .idle)
    }

    func testInitialICEModeIsInactive() {
        XCTAssertFalse(appState.isICEModeActive)
    }

    func testInitialIncidentIDIsNil() {
        XCTAssertNil(appState.currentIncidentID)
    }

    func testInitialRecordingStartTimeIsNil() {
        XCTAssertNil(appState.recordingStartTime)
    }

    func testInitialRecordingDurationIsZero() {
        XCTAssertEqual(appState.recordingDuration, 0)
    }

    func testInitialChunkCountsAreZero() {
        XCTAssertEqual(appState.chunksRecorded, 0)
        XCTAssertEqual(appState.chunksUploaded, 0)
        XCTAssertEqual(appState.uploadQueueDepth, 0)
    }

    func testInitialContactCountsAreZero() {
        XCTAssertEqual(appState.contactsNotified, 0)
        XCTAssertEqual(appState.contactsConfirmed, 0)
    }

    func testInitialBlackoutIsOff() {
        XCTAssertFalse(appState.isBlackoutOn)
    }

    func testInitialIsRecordingIsFalse() {
        XCTAssertFalse(appState.isRecording)
    }

    func testInitialUploadProgressIsZero() {
        XCTAssertEqual(appState.uploadProgress, 0)
    }

    func testInitialFormattedDurationIsZeroZero() {
        XCTAssertEqual(appState.formattedDuration, "00:00")
    }

    func testInitialQualityIsHigh() {
        XCTAssertEqual(appState.currentQuality, .high)
    }

    func testInitialAdaptiveQualityIsEnabled() {
        XCTAssertTrue(appState.adaptiveQualityEnabled)
    }

    // MARK: - ICE Mode Activation

    func testActivateICEModeSetsICEModeActive() {
        appState.activateICEMode()
        XCTAssertTrue(appState.isICEModeActive, "ICE mode should be active after activation")
    }

    func testActivateICEModeSetsRecordingMode() {
        appState.activateICEMode()
        XCTAssertEqual(appState.recordingMode, .recording, "Recording mode should be .recording")
    }

    func testActivateICEModeGeneratesIncidentID() {
        appState.activateICEMode()
        XCTAssertNotNil(appState.currentIncidentID, "Should generate an incident ID")
    }

    func testIncidentIDHasCorrectPrefix() {
        appState.activateICEMode()
        guard let id = appState.currentIncidentID else {
            XCTFail("Incident ID should not be nil")
            return
        }
        XCTAssertTrue(id.hasPrefix("IW-"), "Incident ID should start with IW- prefix")
    }

    func testIncidentIDContainsTimestampAndRandom() {
        appState.activateICEMode()
        guard let id = appState.currentIncidentID else {
            XCTFail("Incident ID should not be nil")
            return
        }

        // Format: IW-{timestamp}-{4-char hex}
        let parts = id.split(separator: "-")
        // "IW" + timestamp part + hex random (but timestamp also had dashes removed,
        // so the format is IW-<ISO8601WithoutDashesOrColons>-<4HEX>)
        XCTAssertGreaterThanOrEqual(parts.count, 3, "Incident ID should have at least 3 dash-separated parts")

        // The last part should be a 4-character hex string
        let lastPart = String(parts.last!)
        XCTAssertEqual(lastPart.count, 4, "Random suffix should be 4 hex characters")
        let hexChars = CharacterSet(charactersIn: "0123456789ABCDEF")
        for scalar in lastPart.unicodeScalars {
            XCTAssertTrue(hexChars.contains(scalar), "Random suffix should be hex: '\(scalar)'")
        }
    }

    func testActivateICEModeSetsRecordingStartTime() {
        let before = Date()
        appState.activateICEMode()
        let after = Date()

        guard let startTime = appState.recordingStartTime else {
            XCTFail("Recording start time should be set")
            return
        }

        XCTAssertGreaterThanOrEqual(startTime, before, "Start time should be >= test start")
        XCTAssertLessThanOrEqual(startTime, after, "Start time should be <= test end")
    }

    func testActivateICEModeResetsDuration() {
        appState.recordingDuration = 42
        appState.activateICEMode()
        XCTAssertEqual(appState.recordingDuration, 0, "Duration should be reset to 0 on activation")
    }

    func testActivateICEModeSetsIsRecordingTrue() {
        appState.activateICEMode()
        XCTAssertTrue(appState.isRecording, "isRecording computed property should be true")
    }

    func testMultipleActivationsGenerateUniqueIDs() {
        var ids = Set<String>()
        for _ in 0..<5 {
            appState.reset()
            appState.activateICEMode()
            if let id = appState.currentIncidentID {
                ids.insert(id)
            }
        }
        XCTAssertEqual(ids.count, 5, "Each activation should generate a unique incident ID")
    }

    // MARK: - Mark Safe Transition

    func testMarkSafeSetsUploadingMode() {
        appState.activateICEMode()
        appState.markSafe()
        XCTAssertEqual(appState.recordingMode, .uploading, "markSafe should set mode to .uploading")
    }

    func testMarkSafePreservesIncidentData() {
        appState.activateICEMode()
        let incidentID = appState.currentIncidentID
        let startTime = appState.recordingStartTime

        appState.markSafe()

        XCTAssertEqual(appState.currentIncidentID, incidentID, "Incident ID should be preserved after markSafe")
        XCTAssertEqual(appState.recordingStartTime, startTime, "Start time should be preserved after markSafe")
    }

    func testMarkSafeChangesIsRecordingToFalse() {
        appState.activateICEMode()
        XCTAssertTrue(appState.isRecording)
        appState.markSafe()
        XCTAssertFalse(appState.isRecording, "isRecording should be false after markSafe (mode is .uploading)")
    }

    // MARK: - Deactivate ICE Mode

    func testDeactivateICEModeSetsIdleMode() {
        appState.activateICEMode()
        appState.deactivateICEMode()
        XCTAssertEqual(appState.recordingMode, .idle)
    }

    func testDeactivateICEModeSetsICEModeInactive() {
        appState.activateICEMode()
        appState.deactivateICEMode()
        XCTAssertFalse(appState.isICEModeActive)
    }

    // MARK: - Reset

    func testResetClearsAllState() {
        // Set up lots of state
        appState.activateICEMode()
        appState.chunksRecorded = 42
        appState.chunksUploaded = 20
        appState.contactsNotified = 3
        appState.contactsConfirmed = 1
        appState.isBlackoutOn = true
        appState.locationHistory = [
            Location(latitude: 37.7749, longitude: -122.4194, accuracy: 10, timestamp: Date(), altitude: nil, speed: nil)
        ]

        appState.reset()

        XCTAssertEqual(appState.recordingMode, .idle)
        XCTAssertFalse(appState.isICEModeActive)
        XCTAssertNil(appState.currentIncidentID)
        XCTAssertNil(appState.recordingStartTime)
        XCTAssertEqual(appState.recordingDuration, 0)
        XCTAssertEqual(appState.chunksRecorded, 0)
        XCTAssertEqual(appState.chunksUploaded, 0)
        XCTAssertEqual(appState.contactsNotified, 0)
        XCTAssertEqual(appState.contactsConfirmed, 0)
        XCTAssertTrue(appState.locationHistory.isEmpty)
        XCTAssertFalse(appState.isBlackoutOn)
    }

    func testResetFromIdleIsIdempotent() {
        appState.reset()
        XCTAssertEqual(appState.recordingMode, .idle)
        XCTAssertNil(appState.currentIncidentID)
    }

    func testResetAfterMarkSafe() {
        appState.activateICEMode()
        appState.markSafe()
        appState.reset()

        XCTAssertEqual(appState.recordingMode, .idle)
        XCTAssertFalse(appState.isICEModeActive)
        XCTAssertNil(appState.currentIncidentID)
    }

    // MARK: - Blackout Toggle

    func testBlackoutToggle() {
        XCTAssertFalse(appState.isBlackoutOn, "Blackout should be off initially")

        appState.isBlackoutOn = true
        XCTAssertTrue(appState.isBlackoutOn, "Blackout should be on after toggle")

        appState.isBlackoutOn = false
        XCTAssertFalse(appState.isBlackoutOn, "Blackout should be off after second toggle")
    }

    func testBlackoutSurvivesMarkSafe() {
        appState.activateICEMode()
        appState.isBlackoutOn = true
        appState.markSafe()
        XCTAssertTrue(appState.isBlackoutOn, "Blackout state should survive markSafe")
    }

    func testBlackoutClearedOnReset() {
        appState.isBlackoutOn = true
        appState.reset()
        XCTAssertFalse(appState.isBlackoutOn, "Blackout should be cleared on reset")
    }

    // MARK: - Computed Properties

    func testUploadProgressCalculation() {
        appState.chunksRecorded = 10
        appState.chunksUploaded = 7
        XCTAssertEqual(appState.uploadProgress, 0.7, accuracy: 0.001)
    }

    func testUploadProgressZeroWhenNoChunksRecorded() {
        appState.chunksRecorded = 0
        appState.chunksUploaded = 0
        XCTAssertEqual(appState.uploadProgress, 0)
    }

    func testUploadProgressFullWhenAllUploaded() {
        appState.chunksRecorded = 50
        appState.chunksUploaded = 50
        XCTAssertEqual(appState.uploadProgress, 1.0, accuracy: 0.001)
    }

    func testFormattedDurationFormat() {
        appState.recordingDuration = 125 // 2 minutes 5 seconds
        XCTAssertEqual(appState.formattedDuration, "02:05")

        appState.recordingDuration = 0
        XCTAssertEqual(appState.formattedDuration, "00:00")

        appState.recordingDuration = 3599 // 59:59
        XCTAssertEqual(appState.formattedDuration, "59:59")
    }

    // MARK: - VideoQuality

    func testVideoQualityResolutions() {
        XCTAssertEqual(AppState.VideoQuality.high.resolution, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(AppState.VideoQuality.medium.resolution, CGSize(width: 1280, height: 720))
        XCTAssertEqual(AppState.VideoQuality.low.resolution, CGSize(width: 854, height: 480))
        XCTAssertEqual(AppState.VideoQuality.audioOnly.resolution, CGSize(width: 426, height: 240))
    }

    func testVideoQualityBitrates() {
        XCTAssertEqual(AppState.VideoQuality.high.bitrate, 8_000_000)
        XCTAssertEqual(AppState.VideoQuality.medium.bitrate, 4_000_000)
        XCTAssertEqual(AppState.VideoQuality.low.bitrate, 2_000_000)
        XCTAssertEqual(AppState.VideoQuality.audioOnly.bitrate, 128_000)
    }

    func testVideoQualityRawValues() {
        XCTAssertEqual(AppState.VideoQuality.high.rawValue, "1080p")
        XCTAssertEqual(AppState.VideoQuality.medium.rawValue, "720p")
        XCTAssertEqual(AppState.VideoQuality.low.rawValue, "480p")
        XCTAssertEqual(AppState.VideoQuality.audioOnly.rawValue, "Audio + 1fps")
    }

    func testVideoQualityCaseIterable() {
        let allCases = AppState.VideoQuality.allCases
        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.high))
        XCTAssertTrue(allCases.contains(.medium))
        XCTAssertTrue(allCases.contains(.low))
        XCTAssertTrue(allCases.contains(.audioOnly))
    }

    // MARK: - Location Model

    func testLocationCoordinateFormatting() {
        let loc = Location(
            latitude: 37.774900,
            longitude: -122.419400,
            accuracy: 10,
            timestamp: Date(),
            altitude: nil,
            speed: nil
        )
        XCTAssertEqual(loc.coordinate, "37.774900, -122.419400")
    }

    func testLocationMapsURL() {
        let loc = Location(
            latitude: 37.7749,
            longitude: -122.4194,
            accuracy: 10,
            timestamp: Date(),
            altitude: nil,
            speed: nil
        )
        XCTAssertNotNil(loc.mapsURL)
        XCTAssertTrue(loc.mapsURL!.absoluteString.contains("maps.apple.com"))
    }

    func testLocationGoogleMapsURL() {
        let loc = Location(
            latitude: 37.7749,
            longitude: -122.4194,
            accuracy: 10,
            timestamp: Date(),
            altitude: nil,
            speed: nil
        )
        XCTAssertNotNil(loc.googleMapsURL)
        XCTAssertTrue(loc.googleMapsURL!.absoluteString.contains("google.com/maps"))
    }

    func testLocationEquality() {
        let date = Date()
        let loc1 = Location(latitude: 37.7749, longitude: -122.4194, accuracy: 10, timestamp: date, altitude: 50, speed: 5)
        let loc2 = Location(latitude: 37.7749, longitude: -122.4194, accuracy: 10, timestamp: date, altitude: 50, speed: 5)
        let loc3 = Location(latitude: 40.7128, longitude: -74.0060, accuracy: 10, timestamp: date, altitude: nil, speed: nil)

        XCTAssertEqual(loc1, loc2)
        XCTAssertNotEqual(loc1, loc3)
    }

    func testLocationCodable() throws {
        let loc = Location(
            latitude: 37.7749,
            longitude: -122.4194,
            accuracy: 10,
            timestamp: Date(),
            altitude: 50.0,
            speed: 5.0
        )

        let data = try JSONEncoder().encode(loc)
        let decoded = try JSONDecoder().decode(Location.self, from: data)

        XCTAssertEqual(decoded.latitude, loc.latitude)
        XCTAssertEqual(decoded.longitude, loc.longitude)
        XCTAssertEqual(decoded.accuracy, loc.accuracy)
        XCTAssertEqual(decoded.altitude, loc.altitude)
        XCTAssertEqual(decoded.speed, loc.speed)
    }
}
