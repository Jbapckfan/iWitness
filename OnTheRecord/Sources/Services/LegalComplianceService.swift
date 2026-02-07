import Foundation
import CoreLocation
import Combine

/// Enum representing the legal requirement for recording consent
enum RecordingConsentLaw: String {
    case oneParty = "One-Party Consent"
    case twoParty = "Two-Party Consent"
    case unknown = "Unknown Jurisdiction"
    
    var warningMessage: String? {
        switch self {
        case .twoParty:
            return "⚠️ You are in a Two-Party Consent state. Recording audio without consent may be a felony. Consider disabling audio or ensuring visibility."
        case .oneParty:
            return nil // Generally safe if the recorder is a party to the conversation
        case .unknown:
            return "⚠️ Unable to verify local recording laws. Please check local regulations."
        }
    }
}

/// Service to monitor location and determine applicable recording laws
final class LegalComplianceService: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LegalComplianceService()
    
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    
    @Published var currentLaw: RecordingConsentLaw = .unknown
    @Published var currentISOStateCode: String?
    
    // List of All-Party/Two-Party Consent States (US)
    // As of 2025. Note: Laws vary by context, this is a general guardrail.
    // CLGeocoder.administrativeArea returns full state names (e.g. "California"),
    // so we store both full names and abbreviations for reliable matching.
    private let twoPartyStates: Set<String> = [
        "CA", "California",
        "CT", "Connecticut",
        "FL", "Florida",
        "IL", "Illinois",
        "MD", "Maryland",
        "MA", "Massachusetts",
        "MI", "Michigan",
        "MT", "Montana",
        "NH", "New Hampshire",
        "PA", "Pennsylvania",
        "WA", "Washington"
    ]
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers // Low power, just need state
    }
    
    func checkCompliance() {
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else if status == .authorizedWhenInUse || status == .authorizedAlways {
            locationManager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Reverse geocode to get state
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self,
                  let placemark = placemarks?.first,
                  let stateCode = placemark.administrativeArea else {
                return
            }

            DispatchQueue.main.async {
                self.currentISOStateCode = stateCode
                self.determineLaw(for: stateCode)
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        debugLog("[LegalComplianceService] Location error: \(error.localizedDescription)")
    }
    
    private func determineLaw(for stateCode: String) {
        // Assume US for this specific logic
        // Future: Check country code first
        
        if twoPartyStates.contains(stateCode) {
            currentLaw = .twoParty
        } else {
            currentLaw = .oneParty
        }
        
        debugLog("[LegalComplianceService] State: \(stateCode), Law: \(currentLaw.rawValue)")
    }
}
