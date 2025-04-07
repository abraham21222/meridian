//
//  ContentView.swift
//  comps
//
//  Created by Abraham Bloom on 4/6/25.
//

import SwiftUI
import CoreLocation
import MapKit

struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    // Business types you want to filter by
    let businessTypes = ["cafe", "restaurant", "bar", "hotel", "business"]
    @State private var selectedBusinessType: String = "cafe"
    // Options for search radius in miles
    let radiusOptions: [Double] = [0.1, 0.5, 1, 2, 5]

    var body: some View {
        VStack(spacing: 0) {
            // Top filter controls
            VStack {
                HStack {
                    Picker("Business Type", selection: $selectedBusinessType) {
                        ForEach(businessTypes, id: \.self) { type in
                            Text(type.capitalized).tag(type)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal)

                    Picker("Radius (miles)", selection: $locationManager.searchRadiusMiles) {
                        ForEach(radiusOptions, id: \.self) { radius in
                            Text("\(radius, specifier: "%.1f") mi").tag(radius)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal)

                    Button(action: {
                        // Update the search query and trigger a new search if location exists.
                        locationManager.searchQuery = selectedBusinessType
                        if let loc = locationManager.location {
                            locationManager.searchNearbyPlaces(at: loc)
                        }
                    }) {
                        Text("Search")
                            .padding(8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(4)
                    }
                }
                .padding(.vertical, 8)
            }
            
            Map(
                coordinateRegion: $region,
                showsUserLocation: true,
                annotationItems: locationManager.nearbyPlaces
            ) { place in
                MapAnnotation(coordinate: place.coordinate) {
                    PlaceMarkerView(place: place,
                        index: locationManager.nearbyPlaces.firstIndex(where: { $0.id == place.id }) ?? 0)
                }
            }
            .frame(height: UIScreen.main.bounds.height * 0.5)
            
            List {
                ForEach(locationManager.nearbyPlaces) { place in
                    PlaceRowView(
                        place: place,
                        index: locationManager.nearbyPlaces.firstIndex(where: { $0.id == place.id }) ?? 0
                    )
                }
            }
        }
        .onAppear {
            locationManager.requestPermission()
            locationManager.startUpdatingLocation()
        }
        .onChange(of: locationManager.location) { _, newLocation in
            if let location = newLocation {
                region.center = location.coordinate
            }
        }
    }
}

struct PlaceMarkerView: View {
    let place: Place
    let index: Int

    var body: some View {
        VStack {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 30, height: 30)
                Text("\(index + 1)")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            Text(place.name)
                .font(.caption)
                .padding(4)
                .background(Color.white.opacity(0.8))
                .cornerRadius(4)
        }
    }
}

struct PlaceRowView: View {
    let place: Place
    let index: Int

    var body: some View {
        HStack {
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 30, height: 30)
                Text("\(index + 1)")
                    .foregroundColor(.white)
                    .font(.headline)
            }
            VStack(alignment: .leading) {
                Text(place.name)
                    .font(.headline)
                Text(String(format: "%.1f miles away", place.distance * 0.000621371))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if let lastDeal = place.lastLeaseDealClosureDate {
                    Text("Last lease deal: \(lastDeal, style: .date)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Last lease deal: N/A")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct PlaceAnnotationView: View {
    let rank: Int
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue)
                .frame(width: 30, height: 30)
            
            Text("\(rank)")
                .foregroundColor(.white)
                .font(.system(size: 16, weight: .bold))
        }
    }
}

struct NearestPlaceRow: View {
    let rank: Int
    let place: Place
    let distance: Double?
    
    var body: some View {
        HStack(spacing: 12) {
            // Rank Circle
            ZStack {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 36, height: 36)
                
                Text("\(rank)")
                    .foregroundColor(.white)
                    .font(.system(size: 18, weight: .bold))
            }
            
            // Place Details
            VStack(alignment: .leading, spacing: 4) {
                Text(place.name)
                    .font(.system(size: 17, weight: .semibold))
                
                if let distance = distance {
                    Text(formatDistance(distance))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Direction arrow
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private func formatDistance(_ distance: Double) -> String {
        if distance < 1000 {
            return String(format: "%.0f meters away", distance)
        } else {
            return String(format: "%.1f km away", distance / 1000)
        }
    }
}

extension CLLocationCoordinate2D {
    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

#Preview {
    ContentView()
}
