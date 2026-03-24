//
//  FoodLogView.swift
//  MacroBitt
//

import SwiftUI
import SwiftData

// MARK: - Root Tab View

struct FoodLogView: View {
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingAddEntry = false
    @State private var entryToEdit: FoodEntry?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DateNavigationBar(date: $selectedDate)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(.bar)

                FoodLogContentView(
                    date: selectedDate,
                    entryToEdit: $entryToEdit
                )
            }
            .navigationTitle("Food Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                AddFoodEntryView(date: selectedDate)
            }
            .sheet(item: $entryToEdit) { entry in
                AddFoodEntryView(editing: entry)
            }
        }
    }
}

// MARK: - Date Navigation Bar

private struct DateNavigationBar: View {
    @Binding var date: Date

    private let calendar = Calendar.current
    private var isToday: Bool { calendar.isDateInToday(date) }

    private var title: String {
        if calendar.isDateInToday(date)      { return "Today" }
        if calendar.isDateInYesterday(date)  { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    var body: some View {
        HStack {
            Button {
                date = calendar.date(byAdding: .day, value: -1, to: date) ?? date
            } label: {
                Image(systemName: "chevron.left")
                    .fontWeight(.semibold)
            }

            Spacer()

            Text(title)
                .font(.headline)
                .animation(.none, value: date)

            Spacer()

            Button {
                date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
            } label: {
                Image(systemName: "chevron.right")
                    .fontWeight(.semibold)
            }
            .disabled(isToday)
            .opacity(isToday ? 0.3 : 1)
        }
    }
}

// MARK: - Content View (dynamic @Query)

private struct FoodLogContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var logs: [DailyLog]
    @Binding var entryToEdit: FoodEntry?

    private var log: DailyLog? { logs.first }
    private var entries: [FoodEntry] { log?.entries ?? [] }

    init(date: Date, entryToEdit: Binding<FoodEntry?>) {
        _logs = Query(filter: #Predicate<DailyLog> { $0.date == date })
        _entryToEdit = entryToEdit
    }

    var body: some View {
        if entries.isEmpty {
            emptyState
        } else {
            List {
                SummaryCard(entries: entries)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)

                ForEach(MealType.allCases, id: \.self) { meal in
                    let mealEntries = entries.filter { $0.mealType == meal }
                    if !mealEntries.isEmpty {
                        MealSection(
                            meal: meal,
                            entries: mealEntries,
                            onEdit: { entryToEdit = $0 },
                            onDelete: delete
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No entries",
            systemImage: "fork.knife",
            description: Text("Tap + to log your first meal.")
        )
    }

    private func delete(_ entry: FoodEntry) {
        if let log {
            log.entries.removeAll { $0.id == entry.id }
        }
        modelContext.delete(entry)
        try? modelContext.save()
    }
}

// MARK: - Summary Card

private struct SummaryCard: View {
    let entries: [FoodEntry]

    private var totalCalories: Double { entries.reduce(0) { $0 + $1.calories } }
    private var totalProtein:  Double { entries.reduce(0) { $0 + $1.protein  } }
    private var totalCarbs:    Double { entries.reduce(0) { $0 + $1.carbs    } }
    private var totalFat:      Double { entries.reduce(0) { $0 + $1.fat      } }

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(totalCalories.formatted(.number.precision(.fractionLength(0))))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("kcal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            }

            HStack(spacing: 0) {
                MacroPill(label: "Protein", value: totalProtein,  color: .blue)
                Spacer()
                MacroPill(label: "Carbs",   value: totalCarbs,    color: .orange)
                Spacer()
                MacroPill(label: "Fat",     value: totalFat,      color: .yellow)
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct MacroPill: View {
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text(value.formatted(.number.precision(.fractionLength(1))) + "g")
                .font(.system(.body, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Meal Section

private struct MealSection: View {
    let meal: MealType
    let entries: [FoodEntry]
    let onEdit: (FoodEntry) -> Void
    let onDelete: (FoodEntry) -> Void

    var body: some View {
        Section(meal.rawValue) {
            ForEach(entries) { entry in
                FoodEntryRow(entry: entry)
                    .contentShape(Rectangle())
                    .onTapGesture { onEdit(entry) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(entry)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
    }
}

// MARK: - Entry Row

private struct FoodEntryRow: View {
    let entry: FoodEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.name)
                    .font(.body)
                Spacer()
                Text(entry.calories.formatted(.number.precision(.fractionLength(0))) + " kcal")
                    .font(.body)
                    .fontWeight(.medium)
            }

            HStack(spacing: 12) {
                if let size = entry.servingSize {
                    Text(size)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CompactMacros(protein: entry.protein, carbs: entry.carbs, fat: entry.fat)
            }
            .font(.caption)
        }
        .padding(.vertical, 2)
    }
}

private struct CompactMacros: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    private func fmt(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)))
    }

    var body: some View {
        HStack(spacing: 6) {
            Label("P \(fmt(protein))g", systemImage: "")
                .foregroundStyle(.blue)
            Label("C \(fmt(carbs))g", systemImage: "")
                .foregroundStyle(.orange)
            Label("F \(fmt(fat))g", systemImage: "")
                .foregroundStyle(.yellow)
        }
        .labelStyle(.titleOnly)
    }
}

// MARK: - Preview

#Preview {
    FoodLogView()
        .modelContainer(for: [FoodEntry.self, DailyLog.self], inMemory: true)
}
