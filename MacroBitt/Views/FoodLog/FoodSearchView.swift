//
//  FoodSearchView.swift
//  MacroBitt
//

import SwiftUI
import SwiftData

// MARK: - Search Mode

private enum SearchMode { case keyword, naturalLanguage }

// MARK: - Identifiable Wrapper

// NutritionixFoodItem is a plain struct; wrap it for .sheet(item:)
private struct SelectedItem: Identifiable {
    let id = UUID()
    let foodItem: NutritionixFoodItem
}

// MARK: - FoodSearchView

struct FoodSearchView: View {
    // MARK: Dependencies

    let targetDate: Date
    let service: any NutritionixServiceProtocol

    // MARK: State

    @State private var searchMode: SearchMode = .keyword
    @State private var query: String = ""
    @State private var debounceTask: Task<Void, Never>? = nil

    @State private var keywordResults: [NutritionixSuggestion] = []
    @State private var nlResults: [NutritionixFoodItem] = []

    @State private var isLoading = false
    @State private var errorMessage: String? = nil

    @State private var fetchingDetailForId: String? = nil
    @State private var selectedItem: SelectedItem? = nil

    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SearchBar(
                    text: $query,
                    placeholder: searchMode == .keyword
                        ? "Search foods..."
                        : "e.g. large coffee with oat milk"
                )
                .padding(.top, 8)

                Picker("Mode", selection: $searchMode) {
                    Text("Quick Search").tag(SearchMode.keyword)
                    Text("Describe Food").tag(SearchMode.naturalLanguage)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 10)

                Divider()

                contentArea
            }
            .navigationTitle("Search Food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: query) { _, newValue in
                debounceTask?.cancel()
                guard !newValue.trimmingCharacters(in: .whitespaces).isEmpty else {
                    clearResults()
                    return
                }
                debounceTask = Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    guard !Task.isCancelled else { return }
                    await performSearch(query: newValue)
                }
            }
            .onChange(of: searchMode) { _, _ in
                debounceTask?.cancel()
                clearResults()
                let q = query.trimmingCharacters(in: .whitespaces)
                guard !q.isEmpty else { return }
                Task { await performSearch(query: q) }
            }
            .sheet(item: $selectedItem) { wrapper in
                AddFoodEntryView(nutritionixItem: wrapper.foodItem, date: targetDate)
            }
        }
    }

    // MARK: Content Area

    @ViewBuilder
    private var contentArea: some View {
        let hasResults = !keywordResults.isEmpty || !nlResults.isEmpty
        let queryEmpty = query.trimmingCharacters(in: .whitespaces).isEmpty

        if isLoading && !hasResults {
            ProgressView("Searching…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ErrorStateView(message: error)
        } else if queryEmpty {
            EmptyPromptView(mode: searchMode)
        } else if !hasResults {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if searchMode == .keyword {
                    ForEach(Array(keywordResults.enumerated()), id: \.offset) { _, suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            isLoadingDetail: fetchingDetailForId == (suggestion.nixItemId ?? suggestion.name)
                        ) {
                            fetchDetail(for: suggestion)
                        }
                    }
                } else {
                    ForEach(Array(nlResults.enumerated()), id: \.offset) { _, item in
                        NLResultRow(item: item) {
                            openDirectly(item)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: Search

    private func performSearch(query: String) async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            if searchMode == .keyword {
                let results = try await service.keywordSearch(query: query)
                await MainActor.run { keywordResults = results; nlResults = [] }
            } else {
                let results = try await service.naturalLanguageSearch(query: query)
                await MainActor.run { nlResults = results; keywordResults = [] }
            }
        } catch {
            let msg = (error as? NutritionixError)?.errorDescription ?? error.localizedDescription
            await MainActor.run { errorMessage = msg; clearResults() }
        }
        await MainActor.run { isLoading = false }
    }

    private func clearResults() {
        keywordResults = []
        nlResults = []
        errorMessage = nil
    }

    // MARK: Detail Fetch

    private func fetchDetail(for suggestion: NutritionixSuggestion) {
        let fetchId = suggestion.nixItemId ?? suggestion.name
        fetchingDetailForId = fetchId
        Task {
            do {
                let item: NutritionixFoodItem
                if suggestion.kind == .branded, let id = suggestion.nixItemId {
                    item = try await service.nixItemIdSearch(id: id)
                } else {
                    guard let first = try await service.naturalLanguageSearch(query: suggestion.name).first else {
                        throw NutritionixError.noResults
                    }
                    item = first
                }
                selectedItem = SelectedItem(foodItem: item)
            } catch {
                let msg = (error as? NutritionixError)?.errorDescription ?? error.localizedDescription
                errorMessage = msg
            }
            fetchingDetailForId = nil
        }
    }

    private func openDirectly(_ item: NutritionixFoodItem) {
        selectedItem = SelectedItem(foodItem: item)
    }
}

// MARK: - SearchBar

private struct SearchBar: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .padding(.horizontal)
    }
}

// MARK: - SuggestionRow (keyword mode)

private struct SuggestionRow: View {
    let suggestion: NutritionixSuggestion
    let isLoadingDetail: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.name)
                        .foregroundStyle(.primary)
                    if let brand = suggestion.brandName {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isLoadingDetail {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .disabled(isLoadingDetail)
    }
}

// MARK: - NLResultRow (natural language mode)

private struct NLResultRow: View {
    let item: NutritionixFoodItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .foregroundStyle(.primary)
                    if let brand = item.brandName {
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(item.calories)) kcal")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("P \(fmt(item.protein))g · C \(fmt(item.carbs))g · F \(fmt(item.fat))g")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
    }

    private func fmt(_ v: Double) -> String {
        v.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Empty / Error States

private struct EmptyPromptView: View {
    let mode: SearchMode

    var body: some View {
        ContentUnavailableView(
            mode == .keyword ? "Search for a food" : "Describe what you ate",
            systemImage: "magnifyingglass",
            description: Text(
                mode == .keyword
                    ? "Start typing to see suggestions."
                    : "Describe a meal in plain language."
            )
        )
    }
}

private struct ErrorStateView: View {
    let message: String

    var body: some View {
        ContentUnavailableView(
            "Something went wrong",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }
}

// MARK: - Preview

#Preview {
    FoodSearchView(
        targetDate: Calendar.current.startOfDay(for: Date()),
        service: PreviewNutritionixService()
    )
    .modelContainer(for: [FoodEntry.self, DailyLog.self], inMemory: true)
}

private final class PreviewNutritionixService: NutritionixServiceProtocol, @unchecked Sendable {
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem] { [] }
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem { throw NutritionixError.noResults }
    func nixItemIdSearch(id: String) async throws -> NutritionixFoodItem { throw NutritionixError.noResults }
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion] { [] }
}
