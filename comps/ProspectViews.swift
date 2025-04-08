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
    
    let categories = ["restaurant", "cafe", "gym", "retail", "salon"]
    
    var body: some View {
        VStack {
            Picker("Category", selection: $selectedCategory) {
                ForEach(categories, id: \.self) { category in
                    Text(category.capitalized).tag(category)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .onChange(of: selectedCategory) { _, newValue in
                if let location = locationManager.location {
                    Task {
                        await viewModel.fetchProspects(
                            category: newValue,
                            coordinate: location.coordinate
                        )
                    }
                }
            }
            
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
                            Task {
                                await viewModel.fetchProspects(
                                    category: selectedCategory,
                                    coordinate: location.coordinate
                                )
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            } else {
                List(viewModel.prospects, id: \.id) { prospect in
                    ProspectRow(prospect: prospect)
                }
            }
        }
        .navigationTitle("Expansion Prospects")
        .onAppear {
            if let location = locationManager.location {
                Task {
                    await viewModel.fetchProspects(
                        category: selectedCategory,
                        coordinate: location.coordinate
                    )
                }
            }
        }
    }
}

#Preview {
    NavigationView {
        ProspectsView(locationManager: LocationManager())
    }
}
