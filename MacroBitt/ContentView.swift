//
//  ContentView.swift
//  MacroBitt
//
//  Created by francobitt on 3/23/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }

            FoodLogView()
                .tabItem {
                    Label("Log Food", systemImage: "fork.knife")
                }

            WeightView()
                .tabItem {
                    Label("Weight", systemImage: "scalemass.fill")
                }

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
    }
}

#Preview {
    ContentView()
}
