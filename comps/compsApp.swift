//
//  compsApp.swift
//  comps
//
//  Created by Abraham Bloom on 4/6/25.
//

import SwiftUI

@main
struct compsApp: App {
    @StateObject private var favoritesManager = FavoritesManager()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(favoritesManager)
        }
    }
}
