# MacroBitt

A native iOS food and macro tracking app built with SwiftUI and SwiftData.

## Features

- **Food Log** — log meals by day, organized into Breakfast, Lunch, Dinner, and Snacks
- **Food Search** — keyword search and natural language search powered by the Nutritionix API (e.g. "large coffee with oat milk")
- **Barcode Scanner** — scan packaged food barcodes using the device camera for instant nutrition lookup
- **Macro Validation** — every entry is validated against the formula `(fat × 9) + (carbs × 4) + (protein × 4) ≈ calories` with a ±5 kcal tolerance; mismatches are flagged with a warning indicator
- **Daily Summary** — per-day calorie and macro totals displayed at the top of the log
- **Edit & Delete** — tap any entry to edit, swipe to delete

## Requirements

- Xcode 16+
- iOS 26.2+ deployment target
- A [Nutritionix](https://developer.nutritionix.com) API key (free trial available)

## Setup

1. Clone the repo and open `MacroBitt.xcodeproj` in Xcode.
2. Copy the credentials template and fill in your Nutritionix App ID and Key:

```bash
cp MacroBitt/Config.example.swift.txt MacroBitt/Config.swift
```

3. Select a simulator or device and press **Run** (⌘R).

## Architecture

MVVM with SwiftUI. Local persistence via SwiftData, with iCloud sync configured via CloudKit entitlements.

| Layer | Contents |
|-------|----------|
| `Models/` | SwiftData `@Model` types: `FoodEntry`, `DailyLog`, `UserSettings`, `MealType` |
| `Services/` | `NutritionixService` — async/throws networking client; `NutritionixModels` — domain and Codable types |
| `Utilities/` | `MacroValidator` — macro-calorie consistency validation |
| `Views/` | SwiftUI views organized by tab: `FoodLog/`, `Dashboard/`, `Weight/`, `Settings/` |

### Navigation

`ContentView` hosts a `TabView` with four tabs, each in its own `NavigationStack`:

| Tab | View |
|-----|------|
| Dashboard | `DashboardView` |
| Log Food | `FoodLogView` |
| Weight | `WeightView` |
| Settings | `SettingsView` |

### Nutritionix Integration

`NutritionixServiceProtocol` defines four async methods:

- `naturalLanguageSearch(query:)` — POST `/v2/natural/nutrients`
- `barcodeSearch(upc:)` — GET `/v2/search/item?upc=`
- `nixItemIdSearch(id:)` — GET `/v2/search/item?nix_item_id=`
- `keywordSearch(query:)` — GET `/v2/search/instant?query=`

## Testing

Unit tests use Swift Testing (`import Testing`, `#expect`).

```bash
xcodebuild test \
  -project MacroBitt.xcodeproj \
  -scheme MacroBittTests \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

| Suite | Tests | Description |
|-------|-------|-------------|
| `MacroValidatorTests` | 6 | Tolerance boundary, valid/invalid, negative difference |
| `MockNutritionixServiceTests` | 6 | Protocol-level mock tests |
| `NutritionixServiceParsingTests` | 10 | Real JSON parsing via `StubURLProtocol` (no network required) |

## Security

`Config.swift` containing API credentials is gitignored and never committed. See `.gitignore`.
