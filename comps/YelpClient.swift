import Foundation
import CoreLocation

struct YelpBiz: Decodable, Identifiable {
    let id: String
    let name: String
    let review_count: Int
    let rating: Double
    let phone: String?
    let location: Location
    
    struct Location: Decodable {
        let address1: String?
    }
}

final class YelpClient {
    private let apiKey = "qnXLobh-_HZFqIR3lWENdhIWC--_oZgFQQVKT33hYDTlKdaHWIVmhusvi5KNAbFu_8Jqo0eHULBL1j35GGpSEYPZOIE-uJbHvPq-WpgIGjLMqCAIDUdLLSElb1L1Z3Yx"
    // TODO: Replace with your key
    private let base = "https://api.yelp.com/v3"
    
    func search(term: String,
               coordinate: CLLocationCoordinate2D,
               radiusMeters: Int = 16093,   // 10 mi
               limit: Int = 50) async throws -> [YelpBiz] {
        
        print("DEBUG: YelpClient - Starting search for term: \(term)")
        print("DEBUG: YelpClient - Location: \(coordinate.latitude), \(coordinate.longitude)")
        
        var comps = URLComponents(string: "\(base)/businesses/search")!
        comps.queryItems = [
            .init(name: "term", value: term),
            .init(name: "latitude", value: "\(coordinate.latitude)"),
            .init(name: "longitude", value: "\(coordinate.longitude)"),
            .init(name: "radius", value: "\(radiusMeters)"),
            .init(name: "limit", value: "\(limit)")
        ]
        
        guard let url = comps.url else {
            print("DEBUG: YelpClient - Failed to construct URL")
            throw URLError(.badURL)
        }
        
        print("DEBUG: YelpClient - Requesting URL: \(url.absoluteString)")
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        print("DEBUG: YelpClient - Request headers: \(req.allHTTPHeaderFields ?? [:])")
        
        let (data, response) = try await URLSession.shared.data(for: req)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: YelpClient - HTTP Status Code: \(httpResponse.statusCode)")
            print("DEBUG: YelpClient - Response headers: \(httpResponse.allHeaderFields)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("DEBUG: YelpClient - Error response: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw URLError(.badServerResponse)
            }
        }
        
        print("DEBUG: YelpClient - Received data length: \(data.count) bytes")
        print("DEBUG: YelpClient - Response data: \(String(data: data, encoding: .utf8) ?? "nil")")
        
        struct Envelope: Decodable { 
            let businesses: [YelpBiz]
            let total: Int
        }
        
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            print("DEBUG: YelpClient - Successfully decoded \(envelope.businesses.count) businesses")
            return envelope.businesses
        } catch {
            print("DEBUG: YelpClient - JSON Decoding error: \(error)")
            throw error
        }
    }
    
    func countLocations(brand: String) async throws -> Int {
        print("DEBUG: YelpClient - Counting locations for brand: \(brand)")
        
        var comps = URLComponents(string: "\(base)/businesses/search")!
        let encodedBrand = brand.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? brand
        
        // Add quotes for exact name match and limit to NYC area
        comps.queryItems = [
            .init(name: "term", value: "\"\(encodedBrand)\""), // Exact match
            .init(name: "location", value: "New York, NY"),
            .init(name: "radius", value: "40000"), // 25 mile radius
            .init(name: "limit", value: "50"),
            // Add categories to filter out irrelevant businesses
            .init(name: "categories", value: "restaurants,food,bars")
        ]
        
        guard let url = comps.url else {
            print("DEBUG: YelpClient - Failed to construct URL for count")
            throw URLError(.badURL)
        }
        
        print("DEBUG: YelpClient - Count URL: \(url.absoluteString)")
        
        var req = URLRequest(url: url)
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: req)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: YelpClient - Count HTTP Status: \(httpResponse.statusCode)")
            guard (200...299).contains(httpResponse.statusCode) else {
                print("DEBUG: YelpClient - Count error response: \(String(data: data, encoding: .utf8) ?? "nil")")
                throw URLError(.badServerResponse)
            }
        }
        
        struct Envelope: Decodable { 
            let total: Int
            let businesses: [YelpBiz]
        }
        
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            
            // Additional validation - only count businesses that have exact name match
            let exactMatches = envelope.businesses.filter { business in
                business.name.lowercased() == brand.lowercased()
            }
            
            let count = exactMatches.count
            print("DEBUG: YelpClient - Found \(count) exact matching locations")
            return count
            
        } catch {
            print("DEBUG: YelpClient - Count JSON Decoding error: \(error)")
            throw error
        }
    }
}
