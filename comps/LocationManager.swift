import Foundation
import CoreLocation
import Combine
import MapKit

// MARK: – Model
struct Place: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem
    let distance: Double
    let lastLeaseDealClosureDate: Date?
    
    init(mapItem: MKMapItem, distance: Double, lastLeaseDealClosureDate: Date? = nil) {
        self.name = mapItem.name ?? "Unknown Place"
        self.coordinate = mapItem.placemark.coordinate
        self.mapItem = mapItem
        self.distance = distance
        self.lastLeaseDealClosureDate = lastLeaseDealClosureDate
    }
}

extension CLLocation {
    func getBoroughBlockLot() async throws -> (borough: String, block: String, lot: String) {
        print("DEBUG: Starting geocoding for location: \(coordinate.latitude), \(coordinate.longitude)")
        
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(self)
            print("DEBUG: Received \(placemarks.count) placemarks")
            
            guard let placemark = placemarks.first else {
                print("DEBUG: No placemark found")
                throw NSError(domain: "Geocoding", code: 1, userInfo: [NSLocalizedDescriptionKey: "No placemark found"])
            }
            
            print("DEBUG: Placemark details:")
            print("  - Administrative Area: \(placemark.administrativeArea ?? "nil")")
            print("  - SubAdministrative Area: \(placemark.subAdministrativeArea ?? "nil")")
            print("  - Locality: \(placemark.locality ?? "nil")")
            
            // NYC Borough codes
            let boroughCodes = [
                "Manhattan": "1",
                "Bronx": "2",
                "Brooklyn": "3",
                "Queens": "4",
                "Staten Island": "5"
            ]
            
            let borough = boroughCodes[placemark.subAdministrativeArea ?? ""] ?? "1"
            print("DEBUG: Determined borough code: \(borough)")
            
            let block = String(format: "%04d", Int(abs(coordinate.latitude * 100)))
            let lot = String(format: "%04d", Int(abs(coordinate.longitude * 100)))
            
            print("DEBUG: Calculated block: \(block), lot: \(lot)")
            
            return (borough, block, lot)
        } catch {
            print("DEBUG: Geocoding error: \(error.localizedDescription)")
            throw error
        }
    }
}

// MARK: – Location‑search manager
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()

    @Published var location: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var nearbyPlaces: [Place] = []
    @Published var searchQuery: String = "business" // default query
    @Published var searchRadiusMiles: Double = 0.5

    private var currentSearch: MKLocalSearch?

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()

        locationManager.delegate        = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.distanceFilter  = 5        // update every 5 m
    }

    // MARK: – Permission helpers
    func requestPermission() { locationManager.requestWhenInUseAuthorization() }
    func startUpdatingLocation() { locationManager.startUpdatingLocation() }
    func stopUpdatingLocation()  { locationManager.stopUpdatingLocation()  }

    // MARK: – CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {

        guard let location = locations.last else { return }
        
        DispatchQueue.main.async {
            self.location = location
            self.searchNearbyPlaces(at: location)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                self.startUpdatingLocation()
            } else {
                self.stopUpdatingLocation()
                self.location = nil
                self.nearbyPlaces = []
            }
        }
    }

    // MARK: – Nearby café search
    public func searchNearbyPlaces(at location: CLLocation) {
        currentSearch?.cancel()
        
        let request = MKLocalSearch.Request()
        // Use the dynamic search query from the published property
        request.naturalLanguageQuery = self.searchQuery
        request.resultTypes = [.pointOfInterest]
        
        // Convert the chosen searchRadiusMiles to meters.
        let radiusInMeters = searchRadiusMiles * 1609.34
        request.region = MKCoordinateRegion(
            center: location.coordinate,
            latitudinalMeters: radiusInMeters,
            longitudinalMeters: radiusInMeters
        )
        
        print("DEBUG: Current location: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        print("DEBUG: Search query: \(self.searchQuery)")
        print("DEBUG: Search region center: \(request.region.center.latitude), \(request.region.center.longitude) with radius: \(radiusInMeters) meters")
        
        let search = MKLocalSearch(request: request)
        currentSearch = search
        
        search.start { [weak self] response, error in
            guard let self = self else { return }
            DispatchQueue.main.async {
                if let error = error {
                    print("DEBUG: Search error: \(error.localizedDescription)")
                    return
                }
                guard let response = response else {
                    print("DEBUG: No response received")
                    return
                }
                
                print("DEBUG: Total map items in raw response: \(response.mapItems.count)")
                let allPlaces = response.mapItems.compactMap { item -> Place? in
                    guard let loc = item.placemark.location else { return nil }
                    let distance = location.distance(from: loc)
                    return Place(mapItem: item, distance: distance)
                }
                
                // Debug each result in miles.
                for (index, place) in allPlaces.enumerated() {
                    let miles = place.distance * 0.000621371
                    print("DEBUG: [\(index)] '\(place.name)' at (\(place.coordinate.latitude), \(place.coordinate.longitude)) with distance: \(miles) miles")
                }

                // Filter to only include places within the search radius.
                let filteredPlaces = allPlaces.filter { $0.distance <= radiusInMeters }
                // If there are none within the threshold, use all available sorted by distance.
                let finalPlaces = filteredPlaces.isEmpty ? allPlaces.sorted { $0.distance < $1.distance } : filteredPlaces.sorted { $0.distance < $1.distance }
                self.nearbyPlaces = finalPlaces
                
                print("DEBUG: Final closest places for radius \(self.searchRadiusMiles) miles:")
                for place in self.nearbyPlaces {
                    let miles = place.distance * 0.000621371
                    print("DEBUG: '\(place.name)' - \(miles) miles away")
                }
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}
