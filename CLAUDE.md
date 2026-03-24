# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

Build and run exclusively through Xcode (open `MacroBitt.xcodeproj`). There are no CLI build scripts — use `xcodebuild` only if needed:

```bash
# Build (simulator)
xcodebuild -project MacroBitt.xcodeproj -scheme MacroBitt -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run unit tests
xcodebuild test -project MacroBitt.xcodeproj -scheme MacroBittTests -destination 'platform=iOS Simulator,name=iPhone 16'

# Run UI tests
xcodebuild test -project MacroBitt.xcodeproj -scheme MacroBittUITests -destination 'platform=iOS Simulator,name=iPhone 16'
```

- **iOS Deployment Target**: 26.2
- **Bundle ID**: `francobitt.MacroBitt`

## Architecture

MVVM with SwiftUI. The project is in **Phase 0** (scaffold only) — directories exist but are empty:
- `Models/` — SwiftData `@Model` types (not yet created)
- `ViewModels/` — ObservableObject/Observable view models (not yet created)
- `Services/` — HealthKit & CloudKit service layers (not yet created)
- `Utilities/` — Helpers (not yet created)

### Navigation

`ContentView` hosts a `TabView` with 4 tabs, each in its own `NavigationStack`:

| Tab | View | Icon |
|-----|------|------|
| Dashboard | `DashboardView` | chart.bar.fill |
| Log Food | `FoodLogView` | fork.knife |
| Weight | `WeightView` | scalemass.fill |
| Settings | `SettingsView` | gearshape.fill |

### Data Layer (planned)

- **SwiftData** for local persistence. A `ModelContainer` was removed (commit `3fa4f51`) because it crashed with an empty schema — it must only be re-added once `@Model` types are defined.
- **CloudKit** sync is configured in entitlements (`iCloud.com.TEAMID.MacroBitt`).
- **HealthKit** is enabled in entitlements for fitness/health data integration.

## Key Constraints

- Do not add a `ModelContainer` to `MacroBittApp` until at least one `@Model` type exists — an empty schema crashes on launch.
- HealthKit and CloudKit entitlements are already configured; use them without modifying the entitlements file unless adding new capabilities.

## Data Integrity Rules

**MACRO-CALORIE RULE:** All food entries must be validated with the formula
`(fat × 9) + (carbs × 4) + (protein × 4) = total calories`, with a tolerance
of 5 calories. Entries outside this tolerance must be flagged (`isFlagged = true`,
`calorieDiscrepancy` set to the signed total difference). This validation applies
to every code path that creates or modifies a FoodEntry — no exceptions.

Use `MacroValidator.validate(calories:protein:carbs:fat:)` in
`MacroBitt/Utilities/MacroValidator.swift`.
