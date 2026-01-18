import Foundation
import CoreLocation
import Combine

/// Manages GPS tracking and location history
class LocationService: NSObject, ObservableObject {
    // MARK: - Published State

    @Published var currentLocation: Location?
    @Published var locationHistory: [Location] = []
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isTracking: Bool = false

    // MARK: - Private

    private let locationManager = CLLocationManager()
    private var trackingStartTime: Date?

    // MARK: - Configuration

    private let desiredAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private let distanceFilter: CLLocationDistance = 5 // meters
    private let maxHistoryCount: Int = 1000

    // MARK: - Initialization

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = desiredAccuracy
        locationManager.distanceFilter = distanceFilter
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        locationManager.showsBackgroundLocationIndicator = true
    }

    // MARK: - Authorization

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func requestAlwaysAuthorization() {
        locationManager.requestAlwaysAuthorization()
    }

    // MARK: - Tracking Control

    func startTracking() {
        guard CLLocationManager.locationServicesEnabled() else { return }

        trackingStartTime = Date()
        locationHistory = []
        isTracking = true

        locationManager.startUpdatingLocation()
    }

    func stopTracking() {
        locationManager.stopUpdatingLocation()
        isTracking = false
    }

    // MARK: - Location Utilities

    /// Gets the address string for a location (reverse geocoding)
    func getAddress(for location: Location) async -> String? {
        let geocoder = CLGeocoder()
        let clLocation = CLLocation(latitude: location.latitude, longitude: location.longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(clLocation)
            if let placemark = placemarks.first {
                return formatPlacemark(placemark)
            }
        } catch {
            print("[iWitness] Reverse geocoding failed: \(error)")
        }

        return nil
    }

    private func formatPlacemark(_ placemark: CLPlacemark) -> String {
        var components: [String] = []

        if let street = placemark.thoroughfare {
            if let number = placemark.subThoroughfare {
                components.append("\(number) \(street)")
            } else {
                components.append(street)
            }
        }

        if let city = placemark.locality {
            components.append(city)
        }

        if let state = placemark.administrativeArea {
            components.append(state)
        }

        return components.joined(separator: ", ")
    }

    /// Generates a shareable maps link
    func getMapsLink(for location: Location) -> URL? {
        return URL(string: "https://maps.apple.com/?ll=\(location.latitude),\(location.longitude)&q=iWitness%20Location")
    }

    /// Generates a Google Maps link (more universally accessible)
    func getGoogleMapsLink(for location: Location) -> URL? {
        return URL(string: "https://www.google.com/maps?q=\(location.latitude),\(location.longitude)")
    }

    // MARK: - Export

    /// Exports location history as GeoJSON for case packet
    func exportAsGeoJSON() -> Data? {
        let features = locationHistory.map { location -> [String: Any] in
            return [
                "type": "Feature",
                "geometry": [
                    "type": "Point",
                    "coordinates": [location.longitude, location.latitude]
                ],
                "properties": [
                    "timestamp": ISO8601DateFormatter().string(from: location.timestamp),
                    "accuracy": location.accuracy,
                    "altitude": (location.altitude as Any?) ?? NSNull(),
                    "speed": (location.speed as Any?) ?? NSNull()
                ]
            ]
        }

        let geoJSON: [String: Any] = [
            "type": "FeatureCollection",
            "features": features
        ]

        return try? JSONSerialization.data(withJSONObject: geoJSON, options: .prettyPrinted)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationService: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for clLocation in locations {
            let location = Location(
                latitude: clLocation.coordinate.latitude,
                longitude: clLocation.coordinate.longitude,
                accuracy: clLocation.horizontalAccuracy,
                timestamp: clLocation.timestamp,
                altitude: clLocation.altitude,
                speed: clLocation.speed >= 0 ? clLocation.speed : nil
            )

            currentLocation = location

            // Add to history, maintaining max count
            locationHistory.append(location)
            if locationHistory.count > maxHistoryCount {
                locationHistory.removeFirst()
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[iWitness] Location error: \(error)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }
}
