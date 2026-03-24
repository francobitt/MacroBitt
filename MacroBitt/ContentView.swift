//
//  ContentView.swift
//  MacroBitt
//
//  Created by francobitt on 3/23/26.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.fill")
                }
                .tag(0)

            FoodLogView()
                .tabItem {
                    Label("Log Food", systemImage: "fork.knife")
                }
                .tag(1)

            WeightView()
                .tabItem {
                    Label("Weight", systemImage: "scalemass.fill")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(3)
        }
    }
}

#Preview {
    ContentView()
}
