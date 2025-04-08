//
//  PLUTOLot.swift
//  comps
//
//  Created by Abraham Bloom on 4/8/25.
//


import Foundation

// ----------  PLUTO  ----------
struct PLUTOLot: Decodable {
    let bbl: String                 // master key
    let landUse: String?            // 01‑10 use code
    let lotArea: String?            // square feet
    let bldgArea: String?
    let yearBuilt: String?
    let unitsRes: String?
    let unitsTotal: String?
    let zoning: String?

    enum CodingKeys: String, CodingKey {
        case bbl
        case landUse   = "landuse"
        case lotArea   = "lotarea"
        case bldgArea  = "bldgarea"
        case yearBuilt = "yearbuilt"
        case unitsRes  = "unitsres"
        case unitsTotal = "unitstotal"
        case zoning    = "zonedist1"
    }
}

// ----------  DOB VIOLATIONS  ----------
struct DOBViolation: Decodable, Identifiable {
    var id: String { isnDobViolation }
    let isnDobViolation: String     // unique key
    let issueDate: String?
    let violationType: String?
    let violationStatus: String?
    let description: String?

    enum CodingKeys: String, CodingKey {
        case isnDobViolation = "isn_dob_violation"
        case issueDate       = "issue_date"
        case violationType   = "violation_type_code"
        case violationStatus = "violation_status"
        case description
    }
}

final class NYCOpenDataClient {
    private let appToken: String
    init(appToken: String) { self.appToken = appToken }

    // --- PLUTO ---
    func fetchPLUTOLot(bbl: String) async throws -> PLUTOLot? {
        var comps = URLComponents(string: "https://data.cityofnewyork.us/resource/64uk-42ks.json")!
        comps.queryItems = [
            .init(name: "bbl", value: bbl),
            .init(name: "$limit", value: "1"),
            .init(name: "$$app_token", value: appToken)
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try JSONDecoder().decode([PLUTOLot].self, from: data).first
    }

    // --- DOB Violations ---
    func fetchDOBViolations(boroughCode: String, block: String, lot: String) async throws -> [DOBViolation] {
        var comps = URLComponents(string: "https://data.cityofnewyork.us/resource/3h2n-5cm9.json")!
        comps.queryItems = [
            .init(name: "boro",  value: boroughCode),   // 1‑5
            .init(name: "block", value: block),
            .init(name: "lot",   value: lot),
            .init(name: "$limit", value: "200"),
            .init(name: "$$app_token", value: appToken)
        ]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try JSONDecoder().decode([DOBViolation].self, from: data)
    }
}
