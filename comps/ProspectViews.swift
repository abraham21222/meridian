import SwiftUI

struct ProspectRow: View {
    let prospect: TenantProspect
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(prospect.name)
                .font(.headline)
                .lineLimit(2)
            
            HStack {
                Label("\(prospect.chainCount) locations", systemImage: "building.2")
                Spacer()
                Label("\(prospect.yelp.rating, specifier: "%.1f")/5", systemImage: "star.fill")
                    .foregroundColor(.yellow)
            }
            .font(.caption)
            
            Text("Reviews: \(prospect.yelp.review_count)")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text("Expansion Score: \(prospect.formattedScore)")
                .font(.subheadline)
                .foregroundColor(prospect.score > 7 ? .green : .orange)
            
            if let phone = prospect.yelp.phone {
                Button {
                    if let url = URL(string: "tel://\(phone.replacingOccurrences(of: "-", with: ""))") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Call", systemImage: "phone.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 8)
    }
}

struct ProspectsView: View {
    let locationManager: LocationManager
    @StateObject private var viewModel = TenantScorerViewModel()
    @State private var selectedCategory = "restaurant"
    
    // Hold the row the user tapped
    @State private var selectedProspect: TenantProspect?
    
    let categories = ["restaurant", "cafe", "gym", "retail", "salon"]
    
    var body: some View {
        VStack {
            // Category picker
            Picker("Category", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { category in
                    Text(category.capitalized).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedCategory) { _, newValue in
                if let location = locationManager.location {
                    Task { await viewModel.fetchProspects(category: newValue,
                                                          coordinate: location.coordinate) }
                }
            }
            
            // Main content
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.error != nil {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Unable to load prospects")
                        .font(.headline)
                    Text("Please try again later")
                        .foregroundColor(.secondary)
                    Button("Retry") {
                        if let location = locationManager.location {
                            Task { await viewModel.fetchProspects(category: selectedCategory,
                                                                  coordinate: location.coordinate) }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else {
                List(viewModel.prospects, id: \.id) { prospect in
                    ProspectRow(prospect: prospect)
                        .contentShape(Rectangle())    // make the whole row tappable
                        .onTapGesture {               // open the sheet
                            selectedProspect = prospect
                        }
                }
            }
        }
        .navigationTitle("Expansion Prospects")
        .onAppear {
            if let location = locationManager.location {
                Task { await viewModel.fetchProspects(category: selectedCategory,
                                                      coordinate: location.coordinate) }
            }
        }
        // Sheet that appears when a row is tapped
        .sheet(item: $selectedProspect) { prospect in
            NavigationStack {                         // so NewsView gets a nav bar
                NewsView(businessName: prospect.name)
            }
        }
    }
}
struct NewsView: View {
    let businessName: String
    @Environment(\.dismiss) var dismiss
    @State private var articles: [Article] = []
    @State private var isLoading = true
    
    struct Article: Identifiable {
        let id = UUID()
        let title: String
        let url: URL
        let publishedAt: String
    }
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if articles.isEmpty {
                VStack {
                    Image(systemName: "newspaper")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                    Text("No recent real estate news found")
                        .foregroundColor(.secondary)
                }
            } else {
                List(articles) { article in
                    Link(destination: article.url) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(article.title)
                                .foregroundColor(.primary)
                            Text(article.publishedAt)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Real Estate News")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .task {
            await loadNews()
        }
    }
    
    func loadNews() async {
        isLoading = true
        let newsClient = NewsClient()
        
        do {
            let keywords = [
                businessName,
                "real estate",
                "lease",
                "retail space",
                "commercial property",
                "expansion",
                "location"
            ].map { "\"\($0)\"" }
            
            let query = keywords.joined(separator: " OR ")
            let url = URL(string: "https://newsapi.org/v2/everything?q=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&from=\(newsClient.lastMonthDate)&to=\(newsClient.todayDate)&sortBy=relevancy&apiKey=\(newsClient.apiKey)")!
            
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(NewsResponse.self, from: data)
            
            articles = response.articles
                .filter { article in
                    let lowercaseTitle = article.title.lowercased()
                    return lowercaseTitle.contains("space") ||
                           lowercaseTitle.contains("property") ||
                           lowercaseTitle.contains("retail") ||
                           lowercaseTitle.contains("lease") ||
                           lowercaseTitle.contains("location") ||
                           lowercaseTitle.contains("expansion")
                }
                .map { Article(
                    title: $0.title,
                    url: URL(string: $0.url)!,
                    publishedAt: formatDate($0.publishedAt)
                )}
        } catch {
            print("Error loading news: \(error)")
        }
        
        isLoading = false
    }
    
    private func formatDate(_ dateString: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        
        guard let date = dateFormatter.date(from: dateString) else {
            return "Recent"
        }
        
        let displayFormatter = DateFormatter()
        displayFormatter.dateStyle = .medium
        return displayFormatter.string(from: date)
    }
}

fileprivate struct NewsResponse: Decodable {
    let articles: [NewsArticle]
    
    struct NewsArticle: Decodable {
        let title: String
        let url: String
        let publishedAt: String
    }
}

#Preview {
    NavigationView {
        ProspectsView(locationManager: LocationManager())
    }
}
