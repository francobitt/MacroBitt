# Nutritionix Service Design

**Date:** 2026-03-24
**Feature:** NutritionixService — API client for food search and barcode lookup
**Status:** Approved

## Overview

A typed, async/await Swift service that wraps the Nutritionix v2 API. Exposes three search methods (natural language, barcode, keyword autocomplete), parses all results into a common domain struct, and runs every result through `MacroValidator` before returning to callers. Backed by a protocol for testability.

---

## 1. File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create (gitignored) | `MacroBitt/Config.swift` | API credentials — `enum Config` with `nutritionixAppID` and `nutritionixAppKey` |
| Create (committed) | `MacroBitt/Config.example.swift` | Placeholder copy of `Config.swift` checked into source control |
| Create | `MacroBitt/Services/NutritionixModels.swift` | `NutritionixFoodItem`, `NutritionixSuggestion`, `NutritionixError`, internal Codable response types |
| Create | `MacroBitt/Services/NutritionixService.swift` | `NutritionixServiceProtocol` + `NutritionixService: NutritionixServiceProtocol` |
| Create | `MacroBittTests/NutritionixServiceTests.swift` | Unit tests using `MockNutritionixService` — no real network calls |
| Modify | `.gitignore` | Add `MacroBitt/Config.swift` entry |

---

## 2. Credentials — Config.swift

`Config.swift` is a gitignored Swift file containing a plain `enum` with two static string properties. The build fails at compile time if the file is absent, preventing silent misconfiguration.

**`Config.swift`** (gitignored, never committed):
```swift
// MacroBitt/Config.swift
// DO NOT COMMIT — add your real keys here
enum Config {
    static let nutritionixAppID  = "YOUR_APP_ID"
    static let nutritionixAppKey = "YOUR_APP_KEY"
}
```

**`Config.example.swift`** (committed):
```swift
// MacroBitt/Config.example.swift
// Copy this file to Config.swift and fill in your Nutritionix credentials.
// Get keys at: https://developer.nutritionix.com
enum Config {
    static let nutritionixAppID  = "<your-nutritionix-app-id>"
    static let nutritionixAppKey = "<your-nutritionix-app-key>"
}
```

`.gitignore` addition:
```
# API credentials — never commit
MacroBitt/Config.swift
```

No `Info.plist` changes and no Xcode build settings are needed.

---

## 3. Data Models (`NutritionixModels.swift`)

### 3a. NutritionixFoodItem

The fully-parsed domain struct returned by `naturalLanguageSearch` and `barcodeSearch`. `validation` is computed at parse time — every item has `MacroValidator.validate()` applied before it leaves the service layer.

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

**MacroValidator integration:** Inside the private `parse(_:) -> NutritionixFoodItem` method, after extracting macros from the Nutritionix response, call:

```swift
let validation = MacroValidator.validate(
    calories: calories, protein: protein, carbs: carbs, fat: fat)
```

Store the result on `NutritionixFoodItem.validation`. Callers read `item.validation.isValid` to decide whether to show a warning in the UI. This is a pre-save advisory check — the save-time flagging in `AddFoodEntryView.save()` is a separate, mandatory persistence-layer check and both must remain.

### 3b. NutritionixSuggestion

Lightweight struct returned by `keywordSearch`. Contains no nutrition data. The caller passes `suggestion.name` to `naturalLanguageSearch` to retrieve full nutrition when the user selects an item.

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

`rateLimitExceeded` is a first-class case so callers can show a targeted message ("Too many searches — wait a moment") rather than a generic error alert.

### 3d. Internal Codable types

Internal structs prefixed `NX` decode the raw Nutritionix JSON and are not exposed outside `NutritionixModels.swift`. Key fields mapped from the API:

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

---

## 4. Protocol & Service (`NutritionixService.swift`)

### 4a. Protocol

```swift
protocol NutritionixServiceProtocol {
    func naturalLanguageSearch(query: String) async throws -> [NutritionixFoodItem]
    func barcodeSearch(upc: String) async throws -> NutritionixFoodItem
    func keywordSearch(query: String) async throws -> [NutritionixSuggestion]
}
```

- `naturalLanguageSearch` — POSTs `{ "query": query }` to `/v2/natural/nutrients`. Returns one `NutritionixFoodItem` per food detected in the query string.
- `barcodeSearch` — GETs `/v2/search/item?upc=<upc>`. Returns exactly one item or throws `noResults`.
- `keywordSearch` — GETs `/v2/search/instant?query=<query>`. Returns `[NutritionixSuggestion]` combining both `branded` and `common` result arrays from the response.

### 4b. Concrete Implementation

```swift
final class NutritionixService: NutritionixServiceProtocol {
    private let session: URLSession
    private let appID: String
    private let appKey: String

    init(
        session: URLSession = .shared,
        appID: String = Config.nutritionixAppID,
        appKey: String = Config.nutritionixAppKey
    ) {
        self.session = session
        self.appID = appID
        self.appKey = appKey
    }
}
```

**`session` is injectable** so tests can pass a `URLProtocol`-stubbed session. `appID`/`appKey` default to `Config` values but are overridable.

### 4c. Private Helpers

**`authorizedRequest(url:method:body:) -> URLRequest`**
Constructs a `URLRequest` and attaches three headers to every outbound call:
- `x-app-id: <appID>`
- `x-app-key: <appKey>`
- `Content-Type: application/json` (on POST requests)

**`perform<T: Decodable>(_ request: URLRequest) async throws -> T`**
Calls `session.data(for:)`, checks the HTTP status code via `mapStatusCode(_:)`, decodes the response body as `T`, and wraps errors:
- `URLError` → `NutritionixError.networkFailure`
- `DecodingError` → `NutritionixError.decodingFailure`

**`mapStatusCode(_ response: HTTPURLResponse) throws`**
- 401 → `.invalidCredentials`
- 429 → `.rateLimitExceeded`
- 200–299 → no throw
- All other codes → `.httpError(statusCode:)`

**`parse(_ nxFood: NXFood) -> NutritionixFoodItem`**
Maps one internal `NXFood` response struct to a `NutritionixFoodItem`, calling `MacroValidator.validate()` in the process.

---

## 5. Tests (`NutritionixServiceTests.swift`)

Tests use `MockNutritionixService: NutritionixServiceProtocol` — a simple struct with injectable return values and no network I/O.

Test cases:
1. `naturalLanguageSearch` returns correctly parsed items
2. `naturalLanguageSearch` attaches `MacroValidator.Result` to each item
3. `barcodeSearch` returns single item for valid UPC
4. `barcodeSearch` throws `noResults` for empty response
5. `keywordSearch` returns `NutritionixSuggestion` array with correct `kind`
6. `rateLimitExceeded` error is thrown for HTTP 429
7. `invalidCredentials` error is thrown for HTTP 401
8. `decodingFailure` error is thrown for malformed JSON

---

## 6. API Endpoints Reference

Base URL: `https://trackapi.nutritionix.com`

| Method | Endpoint | Auth | Notes |
|--------|----------|------|-------|
| POST | `/v2/natural/nutrients` | headers | Body: `{ "query": "2 eggs and toast" }` |
| GET | `/v2/search/item?upc=<code>` | headers | Branded items only |
| GET | `/v2/search/instant?query=<term>` | headers | Returns `branded` + `common` arrays |

All requests require `x-app-id` and `x-app-key` headers.

---

## 7. Verification

1. Build succeeds with `Config.swift` present
2. Build fails with `Config.swift` absent (missing type `Config`)
3. `naturalLanguageSearch("2 eggs and toast")` returns 2 items with correct macros
4. Each returned item has `validation` populated (not nil)
5. `barcodeSearch("049000028911")` returns a single branded item
6. `keywordSearch("chicken")` returns suggestions without triggering a full nutrition fetch
7. Removing `Config.swift` from `.gitignore` keeps it out of commits
