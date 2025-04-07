import Foundation
import MapKit
import Combine

final class FavoritesManager: ObservableObject {
    @Published var favorites: [Place] = []

    func isFavorite(place: Place) -> Bool {
        return favorites.contains(where: { $0.id == place.id })
    }

    func toggleFavorite(place: Place) {
        if isFavorite(place: place) {
            removeFavorite(place: place)
        } else {
            addFavorite(place: place)
        }
    }

    func addFavorite(place: Place) {
        if !isFavorite(place: place) {
            favorites.append(place)
            saveFavorites()
        }
    }

    func removeFavorite(place: Place) {
        favorites.removeAll { $0.id == place.id }
        saveFavorites()
    }

    func saveFavorites() {
        // Persistence using UserDefaults can be implemented here.
        // For now, this demo does not persist favorites between launches.
    }

    func loadFavorites() {
        // Load favorites from persistence if implemented.
    }
}