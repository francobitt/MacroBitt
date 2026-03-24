# NutritionixService Design

**Date:** 2026-03-24
**Feature:** Nutritionix API v2 service layer
**Status:** Approved

## Overview

Add a `NutritionixService` to `MacroBitt/Services/` that wraps the Nutritionix v2 API. It supports three search modes (natural language, barcode, keyword autocomplete), parses all responses into a common `NutritionixFoodItem` struct, and runs every result through `MacroValidator` before returning it to callers. Credentials are stored in a gitignored `Config.swift` file.

---

## 1. File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create (gitignored) | `MacroBitt/Config.swift` | API credentials |
| Create (checked in) | `MacroBitt/Config.example.swift` | Placeholder showing required keys |
| Create | `MacroBitt/Services/NutritionixModels.swift` | Domain types, error enum, internal Codable response structs |
| Create | `MacroBitt/Services/NutritionixService.swift` | Protocol + concrete service implementation |
| Create | `MacroBittTests/NutritionixServiceTests.swift` | Unit tests via `MockNutritionixService` |
| Modify | `.gitignore` | Add `MacroBitt/Config.swift` |

---

## 2. Credentials — Config.swift

`Config.swift` is gitignored and never committed. `Config.example.swift` is checked in as a template.

**`MacroBitt/Config.swift`** (gitignored):
```swift
// DO NOT COMMIT — copy of Config.example.swift with real credentials
enum Config {
    static let nutritionixAppID  = "your-app-id-here"
    static let nutritionixAppKey = "your-app-key-here"
}
```

**`MacroBitt/Config.example.swift`** (checked in):
```swift
// Copy to Config.swift and fill in real credentials. Never commit Config.swift.
enum Config {
    static let nutritionixAppID  = "REPLACE_ME"
    static let nutritionixAppKey = "REPLACE_ME"
}
```

`.gitignore` addition:
```
MacroBitt/Config.swift
```

---

## 3. Data Models — NutritionixModels.swift

### 3a. NutritionixFoodItem

Fully parsed, macro-validated domain type returned from `naturalLanguageSearch` and `barcodeSearch`.

```swift
struct NutritionixFoodItem {
    let name: String
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let servingQuantity: Double    // e.g. 1.0
    let servingUnit: String        // e.g. "cup"
    let servingSize: Double        // weight in grams, e.g. 240.0
    let photoURL: URL?
    let brandName: String?         // nil for common (unbranded) foods
    let validation: MacroValidator.Result
}
```

`validation` is always present — every item is passed through `MacroValidator.validate()` at parse time. Callers read `item.validation.isValid` to decide whether to show a mismatch warning before the user saves to SwiftData.

### 3b. NutritionixSuggestion

Lightweight autocomplete result from `keywordSearch`. Contains no nutrition data — the caller passes `suggestion.name` to `naturalLanguageSearch` to retrieve full macros when the user taps an item.

```swift
struct NutritionixSuggestion {
    enum Kind { case common, branded }
    let name: String
    let brandName: String?
    let photoURL: URL?
    let kind: Kind
}
```

### 3c. NutritionixError

Typed error enum covering all failure modes:

```swift
enum NutritionixError: LocalizedError {
    case invalidCredentials          // HTTP 401
    case rateLimitExceeded           // HTTP 429
    case httpError(statusCode: Int)  // other 4xx / 5xx
    case networkFailure(URLError)
    case decodingFailure(DecodingError)
    case noResults
}
```

`rateLimitExceeded` is a first-class case so UIs can show a specific message ("Too many searches — wait a moment") rather than a generic error.

### 3d. Internal Codable types

Internal `NXFood`, `NXPhoto`, `NXNaturalResponse`, `NXSearchItemResponse`, and `NXInstantResponse` structs decode raw Nutritionix JSON. All are `private` to the module (declared in `NutritionixModels.swift` with `internal` access but never exposed through the protocol). Field names use Nutritionix's snake_case directly to avoid custom `CodingKeys`.

Key fields mapped from the API:

| Nutritionix field | Maps to |
|---|---|
| `food_name` | `name` |
| `nf_calories` | `calories` |
| `nf_protein` | `protein` |
| `nf_total_carbohydrate` | `carbs` |
| `nf_total_fat` | `fat` |
| `serving_qty` | `servingQuantity` |
| `serving_unit` | `servingUnit` |
| `serving_weight_grams` | `servingSize` |
| `photo.thumb` | `photoURL` |
| `brand_name` | `brandName` |

All numeric fields are `Double?` in the Codable struct; missing values default to `0` in the `parse` method.

---

## 4. Service — NutritionixService.swift

### 4a. Protocol

```swift
protocol NutritionixServiceProtocol {
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem]
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion]
}
```

`barcodeSearch` returns a single item (one UPC → one product) or throws `noResults`. The other two return arrays.

### 4b. Concrete NutritionixService

```swift
final class NutritionixService: NutritionixServiceProtocol {
    private let session: URLSession
    private let appID: String
    private let appKey: String

    init(session: URLSession = .shared,
         appID: String = Config.nutritionixAppID,
         appKey: String = Config.nutritionixAppKey)
}
```

`session` is injectable for tests (pass a `URLProtocol`-stubbed session). `appID`/`appKey` default to `Config` values but can be overridden.

### 4c. Request construction

A private helper attaches auth headers to every request:

```swift
private func authorizedRequest(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest
```

Headers added to every request:
- `x-app-id: <appID>`
- `x-app-key: <appKey>`
- `Content-Type: application/json` (when body is present)

### 4d. Endpoints

| Method | Endpoint | HTTP | Body |
|--------|----------|------|------|
| `naturalLanguageSearch` | `https://trackapi.nutritionix.com/v2/natural/nutrients` | POST | `{"query": "<text>"}` |
| `barcodeSearch` | `https://trackapi.nutritionix.com/v2/search/item?upc=<upc>` | GET | none |
| `keywordSearch` | `https://trackapi.nutritionix.com/v2/search/instant?query=<text>` | GET | none |

### 4e. Error mapping

A private `mapHTTPError(_ response: HTTPURLResponse) -> NutritionixError` converts status codes:
- 401 → `.invalidCredentials`
- 429 → `.rateLimitExceeded`
- all other non-2xx → `.httpError(statusCode:)`

### 4f. MacroValidator integration

Applied inside the private `parse(_ item: NXFood) -> NutritionixFoodItem` method:

```swift
private func parse(_ item: NXFood) -> NutritionixFoodItem {
    let cal  = item.nf_calories ?? 0
    let prot = item.nf_protein ?? 0
    let carb = item.nf_total_carbohydrate ?? 0
    let fat  = item.nf_total_fat ?? 0

    return NutritionixFoodItem(
        name: item.food_name,
        calories: cal, protein: prot, carbs: carb, fat: fat,
        servingQuantity: item.serving_qty ?? 1,
        servingUnit: item.serving_unit ?? "serving",
        servingSize: item.serving_weight_grams ?? 0,
        photoURL: item.photo.flatMap { URL(string: $0.thumb) },
        brandName: item.brand_name,
        validation: MacroValidator.validate(calories: cal, protein: prot,
                                            carbs: carb, fat: fat)
    )
}
```

This is called for every item from every endpoint. No `NutritionixFoodItem` can be constructed without a `validation` result attached.

The existing `AddFoodEntryView.save()` validation is unchanged and complementary: the service warns at search time, `save()` flags at persist time.

---

## 5. Unit Tests — NutritionixServiceTests.swift

Tests use a `MockNutritionixService: NutritionixServiceProtocol` — no real network calls. Coverage:

1. `naturalLanguageSearch` returns correctly parsed `NutritionixFoodItem` array
2. `barcodeSearch` returns single item or throws `noResults` for empty response
3. `keywordSearch` returns `NutritionixSuggestion` array with correct `kind` values
4. Valid macros produce `validation.isValid == true`
5. Mismatched macros (Nutritionix data with calorie rounding errors) produce `validation.isValid == false`
6. `rateLimitExceeded` is thrown correctly (mock throws this error, caller handles it)

---

## 6. Verification

1. Build succeeds: `** BUILD SUCCEEDED **`
2. All unit tests pass (mock-based, no network required)
3. `Config.swift` is in `.gitignore` and does not appear in `git status`
4. `Config.example.swift` is tracked by git
5. Each service method returns the expected type; `NutritionixFoodItem.validation` is always populated
