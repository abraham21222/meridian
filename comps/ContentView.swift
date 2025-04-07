//
//  ContentView.swift
//  comps
//
//  Created by Abraham Bloom on 4/6/25.
//

import SwiftUI
import CoreLocation
import MapKit

// Update main ContentView to include a TabView with two tabs.
struct ContentView: View {
    @StateObject private var locationManager = LocationManager()
    @EnvironmentObject var favoritesManager: FavoritesManager
    private let acrisClient = ACRISClient(appToken: "hqj3OZ7DD43Q4cMZjcEznPLF1") // Fixed the token to match exactly
    
    // Default region for the map remains unchanged.
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7580, longitude: -73.9855),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    // Business types and radius options remain.
    let businessTypes = ["cafe", "restaurant", "bar", "hotel", "business"]
    @State private var selectedBusinessType: String = "cafe"
    let radiusOptions: [Double] = [0.1, 0.5, 1, 2, 5]
    @State private var selectedBuildingInfo: BuildingInfo?
    @State private var isLoadingProperty = false
    @State private var propertyError: String?
    
    var body: some View {
        TabView {
            NavigationView {
                VStack(spacing: 0) {
                    // Top filter controls for search.
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
                            PlaceRowView(place: place,
                                       index: locationManager.nearbyPlaces.firstIndex(where: { $0.id == place.id }) ?? 0)
                                .onTapGesture {
                                    fetchPropertyDetails(for: place)
                                }
                        }
                    }
                }
//                .navigationTitle("Search")
                .sheet(item: $selectedBuildingInfo) { _ in
                    propertyDetailsSheet
                }
                .overlay(
                    Group {
                        if isLoadingProperty {
                            ProgressView("Loading property details...")
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .shadow(radius: 4)
                        }
                    }
                )
                .alert("Error", isPresented: .constant(propertyError != nil)) {
                    Button("OK") { propertyError = nil }
                } message: {
                    Text(propertyError ?? "Unknown error")
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
            .tabItem {
                Image(systemName: "magnifyingglass")
                Text("Search")
            }

            NavigationView {
                FavoritesView()
                    .navigationTitle("Favorites")
            }
            .tabItem {
                Image(systemName: "star.fill")
                Text("Favorites")
            }
        }
    }
    
    private func fetchPropertyDetails(for place: Place) {
        isLoadingProperty = true
        propertyError = nil
        
        print("DEBUG: Starting property fetch for place: \(place.name)")
        print("DEBUG: Coordinates - Lat: \(place.coordinate.latitude), Long: \(place.coordinate.longitude)")
        
        Task {
            do {
                print("DEBUG: Converting coordinates to borough/block/lot")
                let location = CLLocation(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude)
                let (borough, block, lot) = try await location.fetchBBL()
                print("DEBUG: Converted to - Borough: \(borough), Block: \(block), Lot: \(lot)")
                
                print("DEBUG: Fetching ACRIS master records")
                let masters = try await acrisClient.fetchPropertyInfo(borough: borough, block: block, lot: lot)
                let docIds = masters.map { $0.documentId }
                print("DEBUG: Fetched \(masters.count) master records")
                
                print("DEBUG: Fetching property parties")
                let parties = try await acrisClient.fetchParties(for: docIds)
                print("DEBUG: Fetched \(parties.count) parties")
                
                print("DEBUG: Fetching HPD contacts")
                let contacts = try await acrisClient.fetchHPDContacts(bbl: "\(borough)\(block)\(lot)")
                print("DEBUG: Fetched \(contacts.count) HPD contacts")
                
                await MainActor.run {
                    print("DEBUG: Creating BuildingInfo object")
                    self.selectedBuildingInfo = BuildingInfo(
                        address: place.name,
                        masterRecords: masters,
                        parties: parties,
                        hpdContacts: contacts
                    )
                    print("DEBUG: BuildingInfo created successfully")
                    self.isLoadingProperty = false
                }
            } catch {
                print("DEBUG: Error occurred: \(error.localizedDescription)")
                await MainActor.run {
                    self.propertyError = error.localizedDescription
                    self.isLoadingProperty = false
                }
            }
        }
    }
    
    var propertyDetailsSheet: some View {
        NavigationView {
            ScrollView {
                if let info = selectedBuildingInfo {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Property Address")
                            .font(.headline)
                        Text(info.address)
                            .padding(.bottom)
                        
                        // Display HPD Contact Information
                        Text("Registered Contacts")
                            .font(.headline)
                        if info.hpdContacts.isEmpty {
                            Text("No HPD registration on file.")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(info.hpdContacts, id: \.phone) { c in
                                VStack(alignment: .leading) {
                                    Text("\(c.contactType): \(c.name ?? "N/A")")
                                        .font(.subheadline)
                                    if let phone = c.phone {
                                        Button(action: {
                                            if let url = URL(string: "tel://\(phone.replacingOccurrences(of: "-", with: ""))"),
                                               UIApplication.shared.canOpenURL(url) {
                                                UIApplication.shared.open(url)
                                            }
                                        }) {
                                            Label(phone, systemImage: "phone.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        
                        // Display recent property parties (e.g., owners, lenders)
                        Text("Most Recent Filings")
                            .font(.headline)
                        ForEach(info.parties.prefix(10), id: \.documentId) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(p.partyType.capitalized): \(p.partyName)")
                                    .font(.subheadline)
                                // Optionally match each party with a master record date.
                                if let master = info.masterRecords.first(where: { $0.documentId == p.documentId }),
                                   let date = master.goodThroughDate {
                                    Text("Filed through: \(date)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Property Details")
            .navigationBarItems(trailing: Button("Close") {
                selectedBuildingInfo = nil
            })
        }
    }
}

// New view for displaying favorite places.
struct FavoritesView: View {
    @EnvironmentObject var favoritesManager: FavoritesManager

    var body: some View {
        List {
            ForEach(favoritesManager.favorites) { place in
                PlaceRowView(place: place, index: 0)
            }
        }
        .listStyle(PlainListStyle())
    }
}

// Updated PlaceRowView with a star button and a phone number button.
struct PlaceRowView: View {
    let place: Place
    let index: Int
    @EnvironmentObject var favoritesManager: FavoritesManager

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
            Spacer()
            
            // ADD: Button for making a call to the business
            if let phoneNumber = place.mapItem.phoneNumber {
                Button(action: {
                    callBusiness(phoneNumber: phoneNumber)
                }) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.green)
                        .padding()
                }
                .buttonStyle(BorderlessButtonStyle())
            }

            // Star button remains unchanged
            Button(action: {
                favoritesManager.toggleFavorite(place: place)
            }) {
                Image(systemName: favoritesManager.isFavorite(place: place) ? "star.fill" : "star")
                    .foregroundColor(.yellow)
            }
            .buttonStyle(BorderlessButtonStyle())
        }
        .padding(.vertical, 4)
    }

    // Function to initiate a call
    private func callBusiness(phoneNumber: String) {
        guard let url = URL(string: "tel://\(phoneNumber)") else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}

// Existing PlaceMarkerView and other views remain unchanged.
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

struct BuildingInfo: Identifiable {
    let id = UUID()
    let address: String
    let masterRecords: [ACRISMaster]
    let parties: [ACRISParty]
    let hpdContacts: [HPDContact]
}

//struct ACRISClient {
//    let appToken: String
//
//    func fetchPropertyInfo(borough: String, block: String, lot: String) async throws -> [ACRISResponse] {
//        // Implement your ACRIS API call here
//        return []
//    }
//}
//
//struct ACRISResponse: Identifiable {
//    let id = UUID()
//    let documentId: String
//    let documentType: String
//    let name: String
//    let recordedDateTime: Date?
//}

#Preview {
    ContentView()
        .environmentObject(FavoritesManager())
}
