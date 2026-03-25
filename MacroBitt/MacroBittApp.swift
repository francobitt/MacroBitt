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
            // Schema changed or store is corrupt — wipe and recreate.
            // Acceptable during development; replace with a migration plan before shipping.
            let storeURL = URL.applicationSupportDirectory
                .appending(path: "default.store")
            try? FileManager.default.removeItem(at: storeURL)
            do {
                return try ModelContainer(for: schema, configurations: config)
            } catch let retryError {
                fatalError("ModelContainer failed even after store reset: \(retryError)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(container)
    }
}
