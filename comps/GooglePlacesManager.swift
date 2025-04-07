import Foundation
import CoreLocation
import GooglePlaces

class GooglePlacesManager: NSObject, ObservableObject {
    private var placesClient: GMSPlacesClient!
    @Published var nearbyPlaces: [GooglePlace] = []
    
    override init() {
        super.init()
        placesClient = GMSPlacesClient.shared()
    }
    
    func findNearbyPlaces(at location: CLLocation) {
        // Create the nearby search request
        let location = location.coordinate
        
        let placeFields: GMSPlaceField = [.name, .coordinate, .types]
        
        // Search in a 100m radius
        placesClient.findPlaceLikelihoodsFromCurrentLocation { [weak self] (placeLikelihoods, error) in
            guard let self = self else { return }
            
            if let error = error {
                print("[GooglePlaces] Error: \(error.localizedDescription)")
                return
            }
            
            guard let placeLikelihoods = placeLikelihoods else {
                print("[GooglePlaces] No places found")
                return
            }
            
            // Convert and sort places by distance
            let sortedPlaces = placeLikelihoods
                .compactMap { likelihood -> GooglePlace? in
                    guard let place = likelihood.place else { return nil }
                    let placeLocation = CLLocation(latitude: place.coordinate.latitude, 
                                                 longitude: place.coordinate.longitude)
                    let distance = location.location.distance(from: placeLocation)
                    return GooglePlace(
                        name: place.name ?? "Unknown Place",
                        coordinate: place.coordinate,
                        distance: distance
                    )
                }
                .sorted { $0.distance < $1.distance }
                .prefix(5)
            
            DispatchQueue.main.async {
                self.nearbyPlaces = Array(sortedPlaces)
                print("[GooglePlaces] Found \(self.nearbyPlaces.count) nearby places:")
                self.nearbyPlaces.forEach { place in
                    print(" - \(place.name) (\(Int(place.distance))m)")
                }
            }
        }
    }
}

struct GooglePlace: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distance: Double
}