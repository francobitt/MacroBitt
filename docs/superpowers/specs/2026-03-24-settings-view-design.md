# Settings View Design

**Date:** 2026-03-24
**Feature:** Settings tab — daily calorie and macro goals
**Status:** Approved

## Overview

Implement `SettingsView` (the Settings tab) so users can set their daily calorie goal and per-macro gram targets. Values auto-save to the `UserSettings` SwiftData model. On first launch, sensible defaults are pre-populated automatically.

## Architecture

**File:** `MacroBitt/Views/Settings/SettingsView.swift`

Two structs (same outer/inner split as `FoodLogView` / `FoodLogContentView`):

### `SettingsView` (public, outer)
- `@Query private var allSettings: [UserSettings]`
- `@Environment(\.modelContext) private var modelContext`
- Owns the `NavigationStack` (consistent with `FoodLogView` — each tab owns its own stack)
- On `.onAppear`: use a synchronous `modelContext.fetch(FetchDescriptor<UserSettings>())` to check for an existing record, and insert `UserSettings()` only if the result is empty. Using a direct fetch (not the `@Query` array) avoids any async population race and prevents duplicate records on repeated tab appearances.
- Body: `NavigationStack` → `SettingsFormView(settings:)` when `allSettings.first` is non-nil; a brief empty state otherwise (imperceptible on first launch since the insert is synchronous)

### `SettingsFormView` (private, inner)
- Receives non-optional `UserSettings`
- Declares it `@Bindable` for direct property bindings
- Does NOT need `@Environment(\.modelContext)` — auto-save is implicit via SwiftData's `@Observable` mutation tracking; no explicit save or context reference required
- Renders the `Form`

### `GoalField` (private subview)
```swift
private struct GoalField: View {
    let label: String
    @Binding var value: Double
    let unit: String
}
```
- `TextField("0", value: $value, format: .number)` with `.keyboardType(.decimalPad)` and `.multilineTextAlignment(.trailing)`
- Same HStack layout as `MacroField` in `AddFoodEntryView` but binds `Double` directly
- When the field is cleared or contains an unparseable value, `TextField(value:format:)` does not update the binding — the last valid value is silently retained. Zero is a valid input. Negative values cannot be entered via `.decimalPad`. No explicit validation UI is required.

`MacroField` is NOT reused — it binds `String` and requires the caller to manage parsing.

## Form Layout

```
NavigationStack
  .navigationTitle("Settings")

  Form
    Section("Daily Goal")
      GoalField  Calories  dailyCalorieGoal  kcal

    Section(header: Text("Macro Goals"),
            footer: Text("All macro goals are in grams per day."))
      GoalField  Protein   proteinGoal  g
      GoalField  Carbs     carbsGoal    g
      GoalField  Fat       fatGoal      g
```

No `.listStyle` modifier needed — `Form` applies inset-grouped style automatically on iOS.

## Data Model

`UserSettings` (`Models/UserSettings.swift`) — already implemented and already registered in `MacroBittApp`'s `ModelContainer` schema (`Schema([FoodEntry.self, DailyLog.self, UserSettings.self])`):
- `dailyCalorieGoal: Double` (default 2000)
- `proteinGoal: Double` (default 150)
- `carbsGoal: Double` (default 200)
- `fatGoal: Double` (default 65)

No model changes required.

## First Launch Behavior

`UserSettings` has no `@Attribute(.unique)`. The uniqueness guarantee is enforced by the synchronous `FetchDescriptor` guard in `SettingsView.onAppear` — the same pattern used by `fetchOrCreateDailyLog` in `AddFoodEntryView`. The view always reads `allSettings.first`.

## Preview

```swift
#Preview {
    SettingsView()
        .modelContainer(for: UserSettings.self, inMemory: true)
}
```

An in-memory container is required for Xcode Previews because `@Query` must have a `ModelContainer` in scope.

## Verification

1. Build and run — Settings tab shows form with pre-populated defaults on first launch (2000 kcal, 150g protein, 200g carbs, 65g fat)
2. Change a value — switch to Log Food tab and back; confirm the value persisted (auto-save)
3. Kill and relaunch — goals survive (SwiftData on-disk persistence)
4. Launch the app multiple times — confirm only one `UserSettings` record exists (no duplicates)
