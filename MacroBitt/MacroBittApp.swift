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
    let modelContainer: ModelContainer = {
        let schema = Schema([])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
