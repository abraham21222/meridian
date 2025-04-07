import Foundation
import CoreLocation
import Combine // Needed for PassthroughSubject

// Manager class to handle location updates and permissions
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    @Published var location: CLLocation? = nil
    @Published var authorizationStatus: CLAuthorizationStatus

    // PassthroughSubject to publish building names (we'll use this later)
    let buildingPublisher = PassthroughSubject<String, Never>()

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest // High accuracy needed for buildings
        locationManager.distanceFilter = 5 // Update every 5 meters
    }

    // Request permission when needed
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }

    // Start tracking location
    func startUpdatingLocation() {
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        } else {
            // Handle cases where permission is not granted yet or denied
            print("Location permission not granted.")
            requestPermission() // Request again if not determined
        }
    }

    // Stop tracking location
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate Methods

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            // If permission granted, start updating
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                self.startUpdatingLocation()
            } else {
                // Handle denial or restriction
                print("Location permission denied or restricted.")
                self.stopUpdatingLocation() // Ensure updates are stopped
                self.location = nil // Clear last known location
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.location = location
            // TODO: Add logic here to look up building based on location coordinates
            // For now, we'll just publish a placeholder
            self.lookupBuilding(at: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Failed to get user location: \(error.localizedDescription)")
        // Optionally publish an error state
    }

    // Placeholder for building lookup logic
    private func lookupBuilding(at location: CLLocation) {
        // In a real app, you would use MKLocalSearch, Google Places API, OpenStreetMap data, etc.
        // For this example, we'll just simulate finding a building name based on coordinates.
        let buildingName = "Building near (\(String(format: "%.4f", location.coordinate.latitude)), \(String(format: "%.4f", location.coordinate.longitude)))"
        buildingPublisher.send(buildingName)
    }
}