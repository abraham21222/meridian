import Foundation
import CoreLocation

enum ProspectError: Error {
    case yelpError(String)
    case newsError(String)
    case networkError(Error)
    case unknown
}

@MainActor
class TenantScorerViewModel: ObservableObject {
    @Published var prospects: [TenantProspect] = []
    @Published var isLoading = false
    @Published var error: Error?
    private let scorer = TenantScorer()
    
    func fetchProspects(category: String, coordinate: CLLocationCoordinate2D) async {
        print("DEBUG: ViewModel - Starting prospect fetch for category: \(category)")
        isLoading = true
        error = nil
        
        do {
            print("DEBUG: ViewModel - Calling scorer.prospects")
            self.prospects = try await scorer.prospects(category: category, around: coordinate)
            print("DEBUG: ViewModel - Successfully fetched \(prospects.count) prospects")
        } catch {
            print("DEBUG: ViewModel - Error fetching prospects: \(error)")
            self.error = error
            self.prospects = []
        }
        
        self.isLoading = false
    }
}
