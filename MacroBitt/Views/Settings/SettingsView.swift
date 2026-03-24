//
//  SettingsView.swift
//  MacroBitt
//

import SwiftUI
import SwiftData

// MARK: - Root Tab View

struct SettingsView: View {
    @Query private var allSettings: [UserSettings]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            if let settings = allSettings.first {
                SettingsFormView(settings: settings)
            }
        }
        .onAppear {
            // Use a synchronous fetch (not the @Query array) to avoid
            // any async-population race and prevent duplicate records.
            guard (try? modelContext.fetch(FetchDescriptor<UserSettings>()))?.isEmpty == true else { return }
            modelContext.insert(UserSettings())
        }
    }
}

// MARK: - Form View

private struct SettingsFormView: View {
    @Bindable var settings: UserSettings

    var body: some View {
        Form {
            Section("Daily Goal") {
                GoalField(label: "Calories", value: $settings.dailyCalorieGoal, unit: "kcal")
            }

            Section(
                header: Text("Macro Goals"),
                footer: Text("All macro goals are in grams per day.")
            ) {
                GoalField(label: "Protein", value: $settings.proteinGoal, unit: "g")
                GoalField(label: "Carbs",   value: $settings.carbsGoal,   unit: "g")
                GoalField(label: "Fat",     value: $settings.fatGoal,     unit: "g")
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Goal Field

private struct GoalField: View {
    let label: String
    @Binding var value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: $value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .leading)
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
