import Foundation
import CoreLocation

// Models for ACRIS data
struct ACRISErrorResponse: Codable {
    let code: String
    let error: Bool
    let message: String
}

// Updated ACRISMaster model using only the fields we need.
struct ACRISMaster: Codable {
    let documentId: String
    let recordType: String
    let propertyType: String
    let streetNumber: String?
    let streetName: String?
    let goodThroughDate: String?
    
    enum CodingKeys: String, CodingKey {
        case documentId   = "document_id"
        case recordType   = "record_type"
        case propertyType = "property_type"
        case streetNumber = "street_number"
        case streetName   = "street_name"
        case goodThroughDate = "good_through_date"
    }
}

// New model for property parties.
struct ACRISParty: Codable {
    let documentId: String
    let partyName: String
    let partyType: String        // e.g., GRANTOR, GRANTEE, MORTGAGEE, etc.
    
    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case partyName  = "name"
        case partyType  = "party_type"
    }
}

// New model for HPD Registration Contacts.
struct HPDContact: Codable {
    let bbl: String
    let contactType: String   // e.g., Owner, Agent, HeadOfficer, etc.
    let name: String?
    let phone: String?
    
    enum CodingKeys: String, CodingKey {
        case bbl
        case contactType = "type"
        case name
        case phone
    }
}

class ACRISClient {
    private let apiKey: String
    private let appToken: String
    private let baseURL = "https://data.cityofnewyork.us/resource/8h5j-fqxa.json"
    
    init(appToken: String) {
        self.apiKey = "e35ety80w5ox612qvdm1utrwf"
        self.appToken = appToken
        print("DEBUG: ACRISClient initialized with API key and App Token")
    }
    
    // Fetch property master records.
    func fetchPropertyInfo(borough: String, block: String, lot: String) async throws -> [ACRISMaster] {
        print("DEBUG: Starting ACRIS fetch for borough: \(borough), block: \(block), lot: \(lot)")
        var urlComponents = URLComponents(string: baseURL)!
        
        // Format block and lot as needed.
        let formattedBlock = block.hasPrefix("0") ? block : String(format: "%05d", Int(block) ?? 0)
        let formattedLot = lot.hasPrefix("0") ? lot : String(format: "%04d", Int(lot) ?? 0)
        
        let query = "borough='\(borough)' AND block='\(formattedBlock)' AND lot='\(formattedLot)'"
        urlComponents.queryItems = [
            URLQueryItem(name: "$where", value: query),
            URLQueryItem(name: "$$app_token", value: appToken),
            URLQueryItem(name: "$order", value: "good_through_date DESC"),
            URLQueryItem(name: "$limit", value: "10")
        ]
        
        guard let url = urlComponents.url else {
            print("DEBUG: Failed to construct URL")
            throw URLError(.badURL)
        }
        
        print("DEBUG: Requesting URL: \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.setValue(appToken, forHTTPHeaderField: "X-App-Token")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: HTTP Status Code: \(httpResponse.statusCode)")
        }
        
        print("DEBUG: Received data length: \(data.count) bytes")
        return try JSONDecoder().decode([ACRISMaster].self, from: data)
    }
    
    // Fetch property parties using the document IDs from the master records.
    func fetchParties(for documentIds: [String]) async throws -> [ACRISParty] {
        guard !documentIds.isEmpty else { return [] }
        
        var comps = URLComponents(string: "https://data.cityofnewyork.us/resource/636b-3b5g.json")!
        let list = documentIds.map { "'\($0)'" }.joined(separator: ",")
        comps.queryItems = [
            URLQueryItem(name: "$where", value: "document_id in (\(list))"),
            URLQueryItem(name: "$limit", value: "1000")
        ]
        guard let url = comps.url else { throw URLError(.badURL) }
        
        print("DEBUG: Fetching parties from URL: \(url.absoluteString)")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([ACRISParty].self, from: data)
    }
    
    // Fetch HPD contacts.
    func fetchHPDContacts(bbl: String) async throws -> [HPDContact] {
        var comps = URLComponents(string: "https://data.cityofnewyork.us/resource/feu5-w2e2.json")!
        comps.queryItems = [
            URLQueryItem(name: "bbl", value: bbl),
            URLQueryItem(name: "$limit", value: "50")
        ]
        guard let url = comps.url else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Check if the returned data starts with an array bracket '['.
        if let jsonString = String(data: data, encoding: .utf8),
           let firstChar = jsonString.trimmingCharacters(in: .whitespacesAndNewlines).first,
           firstChar != "[" {
            print("DEBUG: HPD contact data not in expected array format. Returning empty array. Raw response: \(jsonString)")
            return []
        }
        return try JSONDecoder().decode([HPDContact].self, from: data)
    }
}

// MARK: – GeoClient models
struct GeoClientEnvelope<T: Decodable>: Decodable {  // top‑level key varies (address, bbl, …)
    let address: T?
}

struct GeoClientAddress: Decodable {
    let bbl: String
    let bblBoroughCode: String
    let bblTaxBlock: String
    let bblTaxLot: String
    let latitude: Double?
    let longitude: Double?
    
    enum CodingKeys: String, CodingKey {
        case bbl
        case bblBoroughCode
        case bblTaxBlock
        case bblTaxLot
        case latitude
        case longitude
    }
}

// MARK: – Thin service wrapper
enum GeoClient {
    private static let base = URL(string: "https://api.nyc.gov/geo/geoclient")!
    private static let id   = "91dcd87e256e47ff8dee27bf0ed5c4be"
    private static let key  = "dd41f7b4c57944e7926fbe9d511fd5f4"

    static func lookupAddress(house: String,
                            street: String,
                            borough: String) async throws -> GeoClientAddress {
        print("DEBUG: GeoClient - Creating request URL")
        var comps = URLComponents(url: base.appendingPathComponent("v1/address.json"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "houseNumber", value: house),
            .init(name: "street", value: street),
            .init(name: "borough", value: borough)
        ]
        
        guard let url = comps.url else {
            print("DEBUG: GeoClient - Failed to construct URL")
            throw URLError(.badURL)
        }
        
        print("DEBUG: GeoClient - Making request to URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        // Use the correct header name for Azure API Management
        request.addValue(id, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        
        print("DEBUG: GeoClient - Request headers: \(request.allHTTPHeaderFields ?? [:])")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: GeoClient - HTTP Status Code: \(httpResponse.statusCode)")
            print("DEBUG: GeoClient - Response headers: \(httpResponse.allHeaderFields)")
        }
        
        print("DEBUG: GeoClient - Received data: \(String(data: data, encoding: .utf8) ?? "nil")")
        
        let envelope = try JSONDecoder().decode(GeoClientEnvelope<GeoClientAddress>.self, from: data)
        
        guard let addr = envelope.address else {
            print("DEBUG: GeoClient - No address in response")
            throw URLError(.badServerResponse)
        }
        
        print("DEBUG: GeoClient - Successfully decoded address response")
        return addr
    }
}


extension CLLocation {
    /// Returns the official BBL by calling GeoClient
    func fetchBBL() async throws -> (borough: String, block: String, lot: String) {
        print("DEBUG: fetchBBL - Starting reverse geocoding for location: \(coordinate.latitude), \(coordinate.longitude)")
        
        // 1. Reverse‑geocode to get a mailing address
        let placemark = try await CLGeocoder().reverseGeocodeLocation(self).first
            ?? { throw URLError(.cannotFindHost) }()
        
        print("DEBUG: fetchBBL - Received placemark:")
        print("  - Name: \(placemark.name ?? "nil")")
        print("  - SubThoroughfare: \(placemark.subThoroughfare ?? "nil")")
        print("  - Thoroughfare: \(placemark.thoroughfare ?? "nil")")
        print("  - SubLocality: \(placemark.subLocality ?? "nil")")
        print("  - Locality: \(placemark.locality ?? "nil")")
        print("  - SubAdministrativeArea: \(placemark.subAdministrativeArea ?? "nil")")
        print("  - AdministrativeArea: \(placemark.administrativeArea ?? "nil")")
        
        guard
            let house = placemark.subThoroughfare,
            let street = placemark.thoroughfare,
            let rawBorough = placemark.subAdministrativeArea  // "Manhattan", "Brooklyn", …
        else {
            print("DEBUG: fetchBBL - Missing required address components:")
            print("  - House: \(placemark.subThoroughfare ?? "missing")")
            print("  - Street: \(placemark.thoroughfare ?? "missing")")
            print("  - Borough: \(placemark.subAdministrativeArea ?? "missing")")
            throw URLError(.badURL)
        }
        
        // Format borough name according to NYC Geoclient API requirements
        let borough = formatBorough(rawBorough)
        print("DEBUG: fetchBBL - Formatted address components:")
        print("  - House: \(house)")
        print("  - Street: \(street)")
        print("  - Borough (raw): \(rawBorough)")
        print("  - Borough (formatted): \(borough)")
        
        // 2. Ask GeoClient for the BBL
        print("DEBUG: fetchBBL - Calling GeoClient.lookupAddress")
        let gc = try await GeoClient.lookupAddress(
            house: house,
            street: street,
            borough: borough
        )
        
        print("DEBUG: fetchBBL - GeoClient response:")
        print("  - BBL: \(gc.bbl ?? "nil")")
        print("  - Borough Code: \(gc.bblBoroughCode)")
        print("  - Tax Block: \(gc.bblTaxBlock)")
        print("  - Tax Lot: \(gc.bblTaxLot)")
        
        return (gc.bblBoroughCode, gc.bblTaxBlock, gc.bblTaxLot)
    }
    
    // Helper function to format borough names
    private func formatBorough(_ borough: String) -> String {
        let normalized = borough.uppercased()
        // New York County = Manhattan
        if normalized.contains("NEW YORK") || normalized.contains("MANHATTAN") {
            return "MANHATTAN"
        }
        switch normalized {
        case "BRONX", "THE BRONX":
            return "BRONX"
        case "KINGS COUNTY", "BROOKLYN":
            return "BROOKLYN"
        case "QUEENS COUNTY", "QUEENS":
            return "QUEENS"
        case "RICHMOND COUNTY", "STATEN ISLAND":
            return "STATEN ISLAND"
        default:
            print("DEBUG: Unknown borough format: \(borough)")
            return "MANHATTAN" // Default to Manhattan if unknown
        }
    }
}
