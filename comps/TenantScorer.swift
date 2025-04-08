import Foundation
import CoreLocation

struct TenantProspect: Identifiable {
    let id = UUID()
    let name: String
    let score: Double
    let yelp: YelpBiz
    let chainCount: Int
    let newsHits: Int
    
    var formattedScore: String {
        String(format: "%.2f", score)
    }
}

actor TenantScorer {
    let yelp = YelpClient()
    let news = NewsClient()
    
    func prospects(category: String,
                  around coord: CLLocationCoordinate2D) async throws -> [TenantProspect] {
        
        print("DEBUG: TenantScorer - Starting prospect search for \(category)")
        
        do {
            print("DEBUG: TenantScorer - Fetching Yelp candidates")
            let candidates = try await yelp.search(term: category, coordinate: coord)
            print("DEBUG: TenantScorer - Found \(candidates.count) initial candidates")
            
            var results = [TenantProspect]()
            
            for biz in candidates {
                print("DEBUG: TenantScorer - Processing business: \(biz.name)")
                
                do {
                    async let chainCount = yelp.countLocations(brand: biz.name)
                    async let newsHits = news.recentExpansionArticles(for: biz.name)
                    
                    let count = try await chainCount
                    let news = try await newsHits
                    
                    print("DEBUG: TenantScorer - \(biz.name) has \(count) locations and \(news) news hits")
                    
                    let score = compositeScore(
                        chain: count,
                        reviews: biz.review_count,
                        rating: biz.rating,
                        news: news
                    )
                    
                    print("DEBUG: TenantScorer - Calculated score for \(biz.name): \(score)")
                    
                    results.append(.init(
                        name: biz.name,
                        score: score,
                        yelp: biz,
                        chainCount: count,
                        newsHits: news
                    ))
                } catch {
                    print("DEBUG: TenantScorer - Error processing \(biz.name): \(error)")
                    // Continue with next business instead of failing completely
                    continue
                }
            }
            
            let sortedResults = results.sorted { $0.score > $1.score }
            print("DEBUG: TenantScorer - Returning \(sortedResults.count) sorted prospects")
            return sortedResults
            
        } catch {
            print("DEBUG: TenantScorer - Critical error in prospects search: \(error)")
            throw error
        }
    }
    
    private func compositeScore(chain: Int,
                              reviews: Int,
                              rating: Double,
                              news: Int) -> Double {
        
        let chainScore = min(Double(chain) / 10.0, 1.0) * 0.40
        let reviewScore = min(Double(reviews) / 300.0, 1.0) * 0.20
        let ratingScore = (rating / 5.0) * 0.15
        let newsScore = min(Double(news) / 5.0, 1.0) * 0.15
        
        let total = (chainScore + reviewScore + ratingScore + newsScore) * 10.0
        
        print("DEBUG: TenantScorer - Score breakdown for business:")
        print("  Chain Score: \(chainScore * 10.0)")
        print("  Review Score: \(reviewScore * 10.0)")
        print("  Rating Score: \(ratingScore * 10.0)")
        print("  News Score: \(newsScore * 10.0)")
        print("  Total Score: \(total)")
        
        return total
    }
}
