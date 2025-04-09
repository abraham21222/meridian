import Foundation

actor NewsClient {
    public let apiKey = "57468a02261e4306a05c8a82e1fbb899"
    private let base = "https://newsapi.org/v2"
    
    func recentExpansionArticles(for brand: String) async throws -> Int {
        let keywords = [brand, "opens", "expands", "raises"]
        let query = keywords.joined(separator: " OR ")
        
        var comps = URLComponents(string: "\(base)/everything")!
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "from", value: lastMonthDate),
            .init(name: "to", value: todayDate),
            .init(name: "sortBy", value: "relevancy"),
            .init(name: "apiKey", value: apiKey)
        ]
        
        let (data, response) = try await URLSession.shared.data(from: comps.url!)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("DEBUG: NewsClient - Status Code: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("DEBUG: NewsClient - Error response: \(String(data: data, encoding: .utf8) ?? "nil")")
                return 0
            }
        }
        
        do {
            struct Response: Decodable {
                let totalResults: Int
                let articles: [Article]
                
                struct Article: Decodable {
                    let title: String
                }
            }
            let response = try JSONDecoder().decode(Response.self, from: data)
            return response.totalResults
        } catch {
            print("DEBUG: NewsClient - Decoding error: \(error)")
            return 0
        }
    }
    
    func getNewsSearchURL(query: String) -> URL? {
        var comps = URLComponents(string: "\(base)/everything")!
        comps.queryItems = [
            .init(name: "q", value: query),
            .init(name: "from", value: lastMonthDate),
            .init(name: "to", value: todayDate),
            .init(name: "sortBy", value: "relevancy"),
            .init(name: "apiKey", value: apiKey)
        ]
        return comps.url
    }
    
    public var todayDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        return dateFormatter.string(from: Date())
    }
    
    public var lastMonthDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let date = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        return dateFormatter.string(from: date)
    }
}
