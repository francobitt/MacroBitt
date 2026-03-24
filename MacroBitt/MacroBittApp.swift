//
//  MacroBittApp.swift
//  MacroBitt
//
//  Created by francobitt on 3/23/26.
//

import SwiftUI
import SwiftData

@main
struct MacroBittApp: App {
    let container: ModelContainer = {
        let schema = Schema([FoodEntry.self, DailyLog.self, UserSettings.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
