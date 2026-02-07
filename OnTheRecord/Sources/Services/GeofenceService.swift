import Foundation
import CoreLocation

/// Monitors geographic zones and triggers auto-recording when entering high-risk areas
@MainActor
class GeofenceService: NSObject, ObservableObject {
    static let shared = GeofenceService()

    // MARK: - Published State

    @Published var monitoredZones: [GeofenceZone] = []
    @Published var isMonitoring: Bool = false
    @Published var lastTriggeredZone: GeofenceZone?

    // MARK: - Types

    struct GeofenceZone: Codable, Identifiable {
        let id: UUID
        var name: String
        var latitude: Double
        var longitude: Double
        var radiusMeters: Double
        var isEnabled: Bool
        var autoRecordDelay: TimeInterval // seconds before recording starts

        init(name: String, latitude: Double, longitude: Double, radiusMeters: Double = 200, autoRecordDelay: TimeInterval = 0) {
            self.id = UUID()
            self.name = name
            self.latitude = latitude
            self.longitude = longitude
            self.radiusMeters = radiusMeters
            self.isEnabled = true
            self.autoRecordDelay = autoRecordDelay
        }

        var coordinate: CLLocationCoordinate2D {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }

        var region: CLCircularRegion {
            let region = CLCircularRegion(center: coordinate, radius: radiusMeters, identifier: id.uuidString)
            region.notifyOnEntry = true
            region.notifyOnExit = false
            return region
        }
    }

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private let maxRegions = 20 // iOS limit

    /// Called when a geofence triggers and recording should start
    var onZoneEntered: ((GeofenceZone) -> Void)?

    // MARK: - Initialization

    override init() {
        super.init()
        locationManager.delegate = self
        loadZones()
    }

    // MARK: - Zone Management

    func addZone(_ zone: GeofenceZone) {
        guard monitoredZones.count < maxRegions else {
            debugLog("[GeofenceService] Max \(maxRegions) regions reached (iOS limit)")
            return
        }
        monitoredZones.append(zone)
        saveZones()

        if isMonitoring && zone.isEnabled {
            locationManager.startMonitoring(for: zone.region)
        }
    }

    func removeZone(_ zone: GeofenceZone) {
        locationManager.stopMonitoring(for: zone.region)
        monitoredZones.removeAll { $0.id == zone.id }
        saveZones()
    }

    func updateZone(_ zone: GeofenceZone) {
        if let index = monitoredZones.firstIndex(where: { $0.id == zone.id }) {
            // Stop monitoring old region
            locationManager.stopMonitoring(for: monitoredZones[index].region)
            monitoredZones[index] = zone
            saveZones()

            // Start monitoring new region if enabled
            if isMonitoring && zone.isEnabled {
                locationManager.startMonitoring(for: zone.region)
            }
        }
    }

    // MARK: - Monitoring Control

    func startMonitoring() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
            debugLog("[GeofenceService] Region monitoring not available")
            return
        }

        isMonitoring = true
        UserDefaults.standard.set(true, forKey: "geofence_monitoring_enabled")

        for zone in monitoredZones where zone.isEnabled {
            locationManager.startMonitoring(for: zone.region)
        }

        debugLog("[GeofenceService] Monitoring \(monitoredZones.filter(\.isEnabled).count) zones")
    }

    func stopMonitoring() {
        isMonitoring = false
        UserDefaults.standard.set(false, forKey: "geofence_monitoring_enabled")

        for zone in monitoredZones {
            locationManager.stopMonitoring(for: zone.region)
        }
    }

    // MARK: - Persistence

    private func saveZones() {
        if let data = try? JSONEncoder().encode(monitoredZones) {
            UserDefaults.standard.set(data, forKey: "geofence_zones")
        }
    }

    private func loadZones() {
        if let data = UserDefaults.standard.data(forKey: "geofence_zones"),
           let zones = try? JSONDecoder().decode([GeofenceZone].self, from: data) {
            monitoredZones = zones
        }

        // Resume monitoring if it was active
        if UserDefaults.standard.bool(forKey: "geofence_monitoring_enabled") {
            startMonitoring()
        }
    }

    /// Add current location as a zone (convenience)
    func addCurrentLocationAsZone(name: String, radius: Double = 200) {
        locationManager.requestLocation()
        // Will be handled in delegate
        pendingZoneName = name
        pendingZoneRadius = radius
    }

    private var pendingZoneName: String?
    private var pendingZoneRadius: Double = 200
}

// MARK: - CLLocationManagerDelegate

extension GeofenceService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard let circularRegion = region as? CLCircularRegion else { return }

        Task { @MainActor in
            guard let zone = monitoredZones.first(where: { $0.id.uuidString == circularRegion.identifier }) else { return }

            debugLog("[GeofenceService] Entered zone: \(zone.name)")
            lastTriggeredZone = zone

            if zone.autoRecordDelay > 0 {
                try? await Task.sleep(nanoseconds: .seconds(zone.autoRecordDelay))
            }

            onZoneEntered?(zone)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            if let name = pendingZoneName {
                let zone = GeofenceZone(
                    name: name,
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    radiusMeters: pendingZoneRadius
                )
                addZone(zone)
                pendingZoneName = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        debugLog("[GeofenceService] Location error: \(error)")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        debugLog("[GeofenceService] Monitoring failed for \(region?.identifier ?? "unknown"): \(error)")
    }
}
