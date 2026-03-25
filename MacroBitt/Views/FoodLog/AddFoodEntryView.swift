//
//  AddFoodEntryView.swift
//  MacroBitt
//
//  Created by francobitt on 3/23/26.
//

import SwiftUI
import SwiftData

struct AddFoodEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // MARK: - Mode

    private let editingEntry: FoodEntry?
    private let targetDate: Date

    // MARK: - Form State

    @State private var name: String
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String
    @State private var servingSize: String
    @State private var servingCount: Double
    @State private var mealType: MealType

    // MARK: - Init (Add)

    init(date: Date = Date()) {
        self.editingEntry = nil
        self.targetDate = Calendar.current.startOfDay(for: date)
        _name         = State(initialValue: "")
        _caloriesText = State(initialValue: "")
        _proteinText  = State(initialValue: "")
        _carbsText    = State(initialValue: "")
        _fatText      = State(initialValue: "")
        _servingSize  = State(initialValue: "")
        _servingCount = State(initialValue: 1.0)
        _mealType     = State(initialValue: MealType.defaultForCurrentTime())
    }

    // MARK: - Init (Edit)

    init(editing entry: FoodEntry) {
        self.editingEntry = entry
        self.targetDate = Calendar.current.startOfDay(for: entry.timestamp)
        let count = max(entry.servingCount, 0.5)
        _name         = State(initialValue: entry.name)
        _caloriesText = State(initialValue: Self.format(entry.calories / count))
        _proteinText  = State(initialValue: Self.format(entry.protein  / count))
        _carbsText    = State(initialValue: Self.format(entry.carbs    / count))
        _fatText      = State(initialValue: Self.format(entry.fat      / count))
        _servingSize  = State(initialValue: entry.servingSize ?? "")
        _servingCount = State(initialValue: count)
        _mealType     = State(initialValue: entry.mealType)
    }

    // MARK: - Init (Nutritionix)

    init(nutritionixItem item: NutritionixFoodItem, date: Date = Date()) {
        self.editingEntry = nil
        self.targetDate   = Calendar.current.startOfDay(for: date)
        _name         = State(initialValue: item.name)
        _caloriesText = State(initialValue: Self.format(item.calories))
        _proteinText  = State(initialValue: Self.format(item.protein))
        _carbsText    = State(initialValue: Self.format(item.carbs))
        _fatText      = State(initialValue: Self.format(item.fat))
        _servingSize  = State(initialValue: "\(Self.format(item.servingQuantity)) \(item.servingUnit)")
        _servingCount = State(initialValue: 1.0)
        _mealType     = State(initialValue: MealType.defaultForCurrentTime())
    }

    // MARK: - Computed

    private var calories: Double { Double(caloriesText) ?? 0 }
    private var protein:  Double { Double(proteinText)  ?? 0 }
    private var carbs:    Double { Double(carbsText)    ?? 0 }
    private var fat:      Double { Double(fatText)      ?? 0 }

    private var validationResult: MacroValidator.Result? {
        guard let cal  = Double(caloriesText),
              let prot = Double(proteinText),
              let carb = Double(carbsText),
              let fat  = Double(fatText)
        else { return nil }
        return MacroValidator.validate(
            calories: cal, protein: prot, carbs: carb, fat: fat)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !caloriesText.isEmpty
    }

    private var isEditing: Bool { editingEntry != nil }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Serving size (e.g. 100g, 1 cup)", text: $servingSize)
                }

                Section("Macros per serving") {
                    MacroField(label: "Calories", unit: "kcal", text: $caloriesText)
                    MacroField(label: "Protein",  unit: "g",    text: $proteinText)
                    MacroField(label: "Carbs",    unit: "g",    text: $carbsText)
                    MacroField(label: "Fat",      unit: "g",    text: $fatText)

                    if let result = validationResult, !result.isValid {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Calculated: \(Int(result.calculatedCalories)) kcal · Entered: \(Int(calories)) kcal · Difference: \(Int(abs(result.difference)))")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        .listRowBackground(Color.orange.opacity(0.12))
                    }
                }

                Section("Servings") {
                    Stepper(value: $servingCount, in: 0.5...20, step: 0.5) {
                        HStack {
                            Text("Serving count")
                            Spacer()
                            Text(servingCount.formatted())
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Meal") {
                    Picker("Meal type", selection: $mealType) {
                        ForEach(MealType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                if servingCount != 1.0 && canSave {
                    Section("Total for \(servingCount.formatted()) serving\(servingCount == 1 ? "" : "s")") {
                        MacroSummaryRow(label: "Calories", value: calories * servingCount, unit: "kcal")
                        MacroSummaryRow(label: "Protein",  value: protein  * servingCount, unit: "g")
                        MacroSummaryRow(label: "Carbs",    value: carbs    * servingCount, unit: "g")
                        MacroSummaryRow(label: "Fat",      value: fat      * servingCount, unit: "g")
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Food" : "Add Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let totalCalories = calories * servingCount
        let totalProtein  = protein  * servingCount
        let totalCarbs    = carbs    * servingCount
        let totalFat      = fat      * servingCount
        let sizeValue     = servingSize.isEmpty ? nil : servingSize

        if let entry = editingEntry {
            entry.name         = trimmedName
            entry.calories     = totalCalories
            entry.protein      = totalProtein
            entry.carbs        = totalCarbs
            entry.fat          = totalFat
            entry.servingSize  = sizeValue
            entry.servingCount = servingCount
            entry.mealType     = mealType
            let validation = MacroValidator.validate(
                calories: calories, protein: protein, carbs: carbs, fat: fat)
            entry.isFlagged          = !validation.isValid
            entry.calorieDiscrepancy = validation.difference * servingCount
        } else {
            let entry = FoodEntry(
                name:         trimmedName,
                calories:     totalCalories,
                protein:      totalProtein,
                carbs:        totalCarbs,
                fat:          totalFat,
                servingSize:  sizeValue,
                servingCount: servingCount,
                mealType:     mealType
            )
            let log = fetchOrCreateDailyLog(for: targetDate)
            log.entries.append(entry)
            let validation = MacroValidator.validate(
                calories: calories, protein: protein, carbs: carbs, fat: fat)
            entry.isFlagged          = !validation.isValid
            entry.calorieDiscrepancy = validation.difference * servingCount
        }

        try? modelContext.save()
        dismiss()
    }

    private func fetchOrCreateDailyLog(for date: Date) -> DailyLog {
        let descriptor = FetchDescriptor<DailyLog>(
            predicate: #Predicate { $0.date == date }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            return existing
        }
        let log = DailyLog(date: date)
        modelContext.insert(log)
        return log
    }

    private static func format(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(Int(value))
            : String(format: "%.1f", value)
    }
}

// MARK: - Subviews

struct MacroField: View {
    let label: String
    let unit: String
    @Binding var text: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .leading)
        }
    }
}

struct MacroSummaryRow: View {
    let label: String
    let value: Double
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - MealType helpers

extension MealType {
    static func defaultForCurrentTime() -> MealType {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11:  return .breakfast
        case 11..<15: return .lunch
        case 15..<20: return .dinner
        default:      return .snack
        }
    }
}

#Preview("Add") {
    AddFoodEntryView()
        .modelContainer(for: [FoodEntry.self, DailyLog.self], inMemory: true)
}
