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
    private let openDataClient = NYCOpenDataClient(appToken: "hqj3OZ7DD43Q4cMZjcEznPLF1")
    
    // Default region for the map remains unchanged.
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7359, longitude: -73.9911),
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
        
        Task {
            do {
                // 1. Convert lat/long to borough/block/lot
                let location = CLLocation(latitude: place.coordinate.latitude,
                                        longitude: place.coordinate.longitude)
                let (boroughCode, block, lot) = try await location.fetchBBL()
                let bbl = "\(boroughCode)\(block)\(lot)"
                
                // 2. Fetch all data sequentially to avoid capturing async let variables
                let mastersRecords = try await acrisClient.fetchPropertyInfo(borough: boroughCode, block: block, lot: lot)
                let partiesResult = try await acrisClient.fetchParties(for: mastersRecords.map { $0.documentId })
                let hpdContactsResult = try await acrisClient.fetchHPDContacts(bbl: bbl)
                let plutoResult = try await openDataClient.fetchPLUTOLot(bbl: bbl)
                let violationsResult = try await openDataClient.fetchDOBViolations(boroughCode: boroughCode, block: block, lot: lot)
                
                // 3. Update UI on MainActor with all results
                await MainActor.run {
                    self.selectedBuildingInfo = BuildingInfo(
                        address: place.name,
                        masterRecords: mastersRecords,
                        parties: partiesResult,
                        hpdContacts: hpdContactsResult,
                        plutoLot: plutoResult,
                        dobViolations: violationsResult
                    )
                    self.isLoadingProperty = false
                }
            } catch {
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
                        // Property Overview
                        Group {
                            Text("Property Overview")
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(info.address).bold()
                                if let stats = info.buildingStats {
                                    Text(stats)
                                        .foregroundColor(.secondary)
                                }
                                if let mix = info.unitMix {
                                    Text(mix)
                                        .foregroundColor(.secondary)
                                }
                                if let zoning = info.zoning {
                                    Text("Zoning: \(zoning)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Financial Metrics
                        Group {
                            Text("Financial Overview")
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 8) {
                                if let sale = info.mostRecentSale {
                                    Text("Last Sale: \(sale.price)")
                                        .bold()
                                    Text("Date: \(sale.date)")
                                        .foregroundColor(.secondary)
                                }
                                if let ppsf = info.pricePerSqFt {
                                    Text("Price per Square Foot: \(ppsf)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Risk Assessment
                        Group {
                            Text("Risk Assessment")
                                .font(.headline)
                            let risk = info.riskScore
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Risk Score: \(risk.score)")
                                        .bold()
                                        .foregroundColor(risk.score > 80 ? .green : 
                                                       risk.score > 60 ? .orange : .red)
                                    Spacer()
                                }
                                ForEach(risk.factors, id: \.self) { factor in
                                    Text("• \(factor)")
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(8)
                        }
                        
                        // Key Contacts
                        Group {
                            Text("Key Contacts")
                                .font(.headline)
                            ForEach(info.keyContacts, id: \.name) { contact in
                                VStack(alignment: .leading) {
                                    Text("\(contact.role): \(contact.name)")
                                        .font(.subheadline)
                                    if let phone = contact.phone {
                                        Button {
                                            if let url = URL(string: "tel://\(phone.replacingOccurrences(of: "-", with: ""))"),
                                               UIApplication.shared.canOpenURL(url) {
                                                UIApplication.shared.open(url)
                                            }
                                        } label: {
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
                        
                        // Recent Transactions
                        Group {
                            Text("Recent Transactions")
                                .font(.headline)
                            ForEach(info.recentTransactions, id: \.party) { transaction in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(transaction.type): \(transaction.party)")
                                        .font(.subheadline)
                                    if let date = transaction.date {
                                        Text("Filed: \(date)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding()
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Property Details")
        .navigationBarItems(trailing: Button("Close") {
            selectedBuildingInfo = nil
        })
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

// BuildingInfo.swift  (or just extend the struct you already have)
struct BuildingInfo: Identifiable {
    let id = UUID()

    // existing
    let address: String
    let masterRecords: [ACRISMaster]
    let parties: [ACRISParty]
    let hpdContacts: [HPDContact]

    // new
    let plutoLot: PLUTOLot?
    let dobViolations: [DOBViolation]
    
    // MARK: - Real Estate Metrics
    
    // Format large numbers with commas
    private func formatNumber(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: number)) ?? String(number)
    }
    
    // Format currency
    private func formatCurrency(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }
    
    var mostRecentSale: (date: String, price: String)? {
        guard let sale = masterRecords.first(where: { $0.recordType == "DEED" }),
              let price = Double(sale.documentId.prefix(while: { $0.isNumber })) else {
            return nil
        }
        return (sale.goodThroughDate ?? "Unknown", formatCurrency(price))
    }
    
    var pricePerSqFt: String? {
        guard let lot = plutoLot,
              let bldgArea = Int(lot.bldgArea ?? "0"),
              let sale = mostRecentSale,
              let price = Double(sale.price.filter { $0.isNumber }) else {
            return nil
        }
        
        let ppsf = price / Double(bldgArea)
        return formatCurrency(ppsf) + "/sq.ft"
    }
    
    var buildingStats: String? {
        guard let lot = plutoLot else { return nil }
        
        var stats = [String]()
        
        if let year = lot.yearBuilt {
            stats.append("Built in \(year)")
        }
        
        if let area = lot.bldgArea {
            stats.append("\(formatNumber(Int(area) ?? 0)) sq.ft")
        }
        
        if let units = lot.unitsTotal {
            stats.append("\(units) total units")
        }
        
        return stats.isEmpty ? nil : stats.joined(separator: " • ")
    }
    
    var unitMix: String? {
        guard let lot = plutoLot,
              let total = Int(lot.unitsTotal ?? "0"),
              let res = Int(lot.unitsRes ?? "0") else {
            return nil
        }
        
        let comm = total - res
        var mix = [String]()
        
        if res > 0 {
            mix.append("\(res) residential")
        }
        if comm > 0 {
            mix.append("\(comm) commercial")
        }
        
        return mix.isEmpty ? nil : mix.joined(separator: ", ")
    }
    
    var zoning: String? {
        return plutoLot?.zoning
    }
    
    var riskScore: (score: Int, factors: [String]) {
        var score = 100
        var factors = [String]()
        
        // Deduct points for violations
        if !dobViolations.isEmpty {
            score -= dobViolations.count * 5
            factors.append("\(dobViolations.count) open DOB violations")
        }
        
        // Check building age
        if let year = Int(plutoLot?.yearBuilt ?? "0"), year < 1950 {
            score -= 10
            factors.append("Building over 70 years old")
        }
        
        // Check if properly registered with HPD
        if hpdContacts.isEmpty {
            score -= 15
            factors.append("No HPD registration")
        }
        
        return (max(0, score), factors)
    }
    
    var keyContacts: [(role: String, name: String, phone: String?)] {
        return hpdContacts.map { contact in
            (
                role: contact.contactType,
                name: contact.name ?? "Unknown",
                phone: contact.phone
            )
        }
    }
    
    var recentTransactions: [(type: String, party: String, date: String?)] {
        return parties.prefix(5).map { party in
            let master = masterRecords.first { $0.documentId == party.documentId }
            return (
                type: party.partyType,
                party: party.partyName,
                date: master?.goodThroughDate
            )
        }
    }
}

// Existing code ...

#Preview {
    ContentView()
        .environmentObject(FavoritesManager())
}

struct KeyValueRow: View {
    let key: String; let value: String?
    var body: some View {
        HStack {
            Text(key + ":").fontWeight(.semibold)
            Spacer()
            Text(value ?? "N/A")
        }
    }
}

struct SpecsView: View {
    let lot: PLUTOLot
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            KeyValueRow(key: "Year Built",       value: lot.yearBuilt)
            KeyValueRow(key: "Units (res/total)",value: "\(lot.unitsRes ?? "–") / \(lot.unitsTotal ?? "–")")
            KeyValueRow(key: "Lot Area (sf)",    value: lot.lotArea)
            KeyValueRow(key: "Building Area",    value: lot.bldgArea)
            KeyValueRow(key: "Zoning",           value: lot.zoning)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
}
